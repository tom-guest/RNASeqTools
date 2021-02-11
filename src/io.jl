function write_file(filename::String, content::String)
    open(filename, "w") do f
        write(f, content)
    end
end

function strandint(record::BAM.Record; is_rev=false)
    BAM.ispositivestrand(record) ? strand = 1 : strand = -1
    is_rev ? (return strand * -1) : (return strand)
end

@inline function translated_data(data::Array{UInt8,1})::String
    for i in 1:length(data)
        (data[i] == 0x00) && (return String(data[1:i-1]))
    end
end

@inline function get_NM_tag(data::Array{UInt8,1})::Int
    for i in 1:length(data)-2
      (0x4d == data[i]) & (0x43 == data[i+1]) && (return Int(data[i+2]))
    end
    return -1
end

@inline function get_XA_tag(data::Array{UInt8,1})::String
    t = UInt8['X', 'A']
    for i in 1:length(data)-2
        (0x00 == data[i]) & (t[1] == data[i+1]) & (t[2] == data[i+2]) && 
        (return translated_data(data[i+4:end]))
    end
    return "-"
end

function merge_bam_row!(a::DataFrameRow, b::DataFrameRow)
    (start1, stop1, start2, stop2) = sort([a[:start], a[:stop], b[:start], b[:stop]])
    a[:start] = start1
    a[:stop] = stop2
    a[:nm] = a[:nm] + b[:nm] + start2 - stop1
end

function read_bam(bam_file::String; nb_reads::Int = -1)
    record::BAM.Record = BAM.Record()
    reader = BAM.Reader(open(bam_file), index=bam_file*".bai")
    aligned_reads = DataFrame(name=String[], start=Int[], stop=Int[], chr=String[], nm=Int[], aux=String[], cigar=String[])
    c::Int = 0
    while !eof(reader)
        read!(reader, record)
        !BAM.ismapped(record) && continue
        (start, stop) = sort([BAM.position(record)*strandint(record), BAM.rightposition(record)*strandint(record)])
        aux_data = BAM.auxdata(record).data
        new_row = DataFrame(name=BAM.tempname(record), start=start, stop=stop, chr=BAM.refname(record), 
                            nm=get_NM_tag(aux_data), aux=get_XA_tag(aux_data), cigar=BAM.cigar(record))
        index = aligned_reads[!, :name] .== new_row[1, :name]
        (sum(index) > 0) ? merge_bam_row!(@view(aligned_reads[argmax(index), :]), new_row[1, :]) : append!(aligned_reads, new_row)
        ((nb_reads > 0) & (c >= nb_reads)) && break 
    end
    close(reader)
    return aligned_reads
end

function read_gff(gff_file::String, annotation_types = ["CDS"])::Dict{String, DataFrame}
    
    results::Dict{String, DataFrame} = Dict()
    open(gff_file) do file
        gff = readlines(file)
        for line in gff
            startswith(line, "#") && continue
            chr, _, typ, start, stop, _, strand, _, aux = split(line, "\t")
            typ in annotation_types || continue
            start_int = parse(Int, start)
            stop_int = parse(Int, stop)
            (strand == "-") && ((start_int, stop_int) = (-stop_int, -start_int))
            name = split(aux, ";")[1][6:end]
            row = DataFrame(name=name, start=start_int, stop=stop_int)
            chr in keys(results) ? append!(results[chr], row) : results[chr] = row
        end
    end
    return results
end

function read_wig(wig_file::String)
    coverages::Vector{Dict{String,Vector{Float64}}} = []
    temp_collect = Dict()
    track = ""
    span = 0
    chr = ""
    text = ""
    open(wig_file, "r") do file
        lines = readlines(file)
        for line in lines
            if startswith(line, "track")
                track = split(split(line, " ")[2],"=")[2]
                temp_collect[track] = Dict()
            elseif startswith(line, "variableStep")
                span = parse(Int, split(split(line, " ")[3],"=")[2]) - 1
                chr = split(split(line, " ")[2],"=")[2]
                temp_collect[track][chr] = Tuple{Int, Float64}[]
            else
                str_index, str_value = split(line, " ")
                index = parse(Int, str_index)
                value = parse(Float64, str_value)
                for i in index:index+span
                    push!(temp_collect[track][chr], (i, value))
                end
            end
        end
        for (track, collection) in temp_collect
            coverage = Dict()
            for (chr, points) in collection
                coverage[chr] = zeros(Float64, points[end][1])
                for (index, value) in points
                    coverage[chr][index] = value
                end
            end
            push!(coverages, coverage)
        end
    end
    return coverages
end

function write_wig(coverage_reps::Vector{Dict{String,Vector{Float64}}}, wig_file::String; track_name="\"\"")

    open(wig_file, "w") do file
        for (i,coverage) in enumerate(coverage_reps)
            println(file, "track type=wiggle_$i name=$track_name")
            for (chr, cov) in coverage
                println(file, "variableStep chrom=$chr span=1")
                for (ii,value) in enumerate(cov)
                    (value == zero(value)) || println(file, "$ii $value")
                end
            end
        end
    end
end

struct Genome <: SequenceContainer
    seq::LongDNASeq
    chrs::Dict{String, UnitRange{Int}}
    spec::String
end

function Genome(genome_fasta::String)
    (name, sequences) = read_genomic_fasta(genome_fasta)
    chrs::Dict{String,UnitRange{Int}} = Dict()
    seq = ""
    temp_start = 1
    for (chr, sequence) in sequences
        chrs[chr] = temp_start:(temp_start+length(seq)-1)
        temp_start += length(seq)
        seq *= sequence
    end
    return Genome(LongDNASeq(seq), chrs, name)
end

function Base.write(file::String, genome::Genome)
    write_genomic_fasta(Dict(chr=>String(genome.seq[s]) for (chr, s) in genome.chrs), file; name=genome.spec)
end

function read_genomic_fasta(fasta_file::String)
    genome::Dict{String, String} = Dict()
    chrs = String[]
    start_ids = Int[]
    name = ""
    open(fasta_file, "r") do file
        lines = readlines(file)
        startswith(lines[1], ">") && (name = split(join(split(lines[1])[2:end]), "hromosome")[1][1:end-2])
        for (i,line) in enumerate(lines)
            startswith(line, ">") &&  (push!(chrs, split(line," ")[1][2:end]); push!(start_ids, i))
        end
        push!(start_ids, length(lines)+1)
        for (chr, (from,to)) in zip(chrs, [@view(start_ids[i:i+1]) for i in 1:length(start_ids)-1])
            genome[chr] = join(lines[from+1:to-1])
        end
    end
    return name, genome
end

function write_genomic_fasta(genome::Dict{String, String}, fasta_file::String; name="", chars_per_row=80)
    open(fasta_file, "w") do file
        for (i, (chr, seq)) in enumerate(genome)
            s = String(seq)
            l = length(s)
            !isempty(name) ? println(file, ">$chr chromosome $i") : println(file, ">$chr $name chromosome $i")
            for i in 0:Int(length(seq)/chars_per_row)
                ((i+1)*chars_per_row > l) ? println(s[i*chars_per_row+1:end]) : println(s[i*chars_per_row+1:(i+1)*chars_per_row])
            end
        end
    end
end

struct FastaReads <: SequenceContainer
    seqs::Dict{String, LongDNASeq}
    desc::String
end

function FastaReads(fasta_file::String; description="")
    FastaReads(read_reads_fasta(fasta_file), description)
end

function read_reads_fasta(fasta_file::String; nb_reads=-1)
    reads::Dict{String, LongDNASeq} = Dict()
    endswith(fasta_file, ".gz") ?
    reader = FASTA.Reader(GzipDecompressorStream(open(fasta_file, "r"))) :
    reader = FASTA.Reader(open(fasta_file, "r"))
    record = FASTA.Record()
    c = 0
    while !eof(reader)
        c += 1
        read!(reader, record)
        push!(reads, FASTA.identifier(record)=>LongDNASeq(FASTA.sequence(record)))
        ((nb_reads > 0) & (c >= nb_reads)) && break
    end
    close(reader)
    return reads
end

struct FastqReads <: SequenceContainer
    seqs::Dict{String, LongDNASeq}
    qual::Dict{String, Vector{UInt8}}
    desc::String
end

function FastqReads(fastq_file::String; description="")
    (reads, quality) = read_reads_fastq(fastq_file)
    FastqReads(reads, quality, description)
end

function read_reads_fastq(fastq_file::String; nb_reads=-1)
    reads::Dict{String, LongDNASeq} = Dict()
    qual::Dict{String, UnitRange{Int}} = Dict()
    endswith(fastq_file, ".gz") ?
    reader = FASTQ.Reader(GzipDecompressorStream(open(fastq_file, "r"))) :
    reader = FASTQ.Reader(open(fastq_file, "r"))
    record = FASTQ.Record()
    c = 0
    while !eof(reader)
        c += 1
        read!(reader, record)
        push!(reads, FASTQ.identifier(record)=>LongDNASeq(FASTQ.sequence(record)))
        push!(qual, FASTQ.identifier(record)=>FASTQ.quality(record))
        ((nb_reads > 0) & (c >= nb_reads)) && break
    end
    close(reader)
    return reads, quality
end

function write_utrs_fasta(annotations::Dict{String,DataFrame}, genome::Dict{String,String}, threeUTR_fasta::String, fiveUTR_fasta::String)
    record = FASTA.Record()
    five_writer = FASTA.Writer(GzipCompressorStream(open(fiveUTR_fasta, "w")))
    three_writer = FASTA.Writer(GzipCompressorStream(open(threeUTR_fasta, "w")))
    for (chr, sequence) in genome
        for (i,row) in enumerate(eachrow(annotations[chr]))
            ((row[:threeType] == "max") || (row[:fiveType] == "max")) || continue
            name = row["name"]
            if (row[:threeType] == "max") 
                (row["start"] < 0) ? 
                threeUTR = reverse_complement(LongDNASeq(sequence[-row["threeUTR"]:-row["stop"]])) : 
                threeUTR = sequence[row["stop"]:row["threeUTR"]]
                if length(threeUTR) > 20
                    record = FASTA.Record("$(name)_threeUTR", threeUTR)
                    write(three_writer, record)
                end
            end
            if (row["fiveType"] == "max")
                (row["start"] < 0) ?
                fiveUTR = reverse_complement(LongDNASeq(sequence[-row["start"]:-row["fiveUTR"]])) :
                fiveUTR = sequence[row["fiveUTR"]:row["start"]]
                if length(fiveUTR) > 20
                    record = FASTA.Record("$(name)_fiveUTR", fiveUTR)
                    write(five_writer, record)
                end
            end
        end
    end
    close(five_writer)
    close(three_writer)
end