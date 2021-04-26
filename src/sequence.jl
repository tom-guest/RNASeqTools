struct Genome
    seq::LongDNASeq
    chrs::Dict{String, UnitRange{Int}}
end

function Genome(sequences::Vector{LongDNASeq}, names::Vector{String})
    seq = LongDNASeq()
    chrs = Dict{String, UnitRange{Int}}()
    sequence_position = 1
    for (sequence, name) in zip(sequences, names)
        seq *= sequence
        push!(chrs, name=>sequence_position:sequence_position+length(sequence)-1)
        sequence_position += length(sequence)
    end
    return Genome(seq, chrs)
end

function Genome(sequence::LongDNASeq, name::String)
    return Genome([sequence], [name])
end

function Genome(genome_fasta::String)
    (name, sequences) = read_genomic_fasta(genome_fasta)
    chrs::Dict{String,UnitRange{Int}} = Dict()
    total_seq = ""
    temp_start = 1
    for (chr, chr_seq) in sequences
        chrs[chr] = temp_start:(temp_start+length(chr_seq)-1)
        temp_start += length(chr_seq)
        total_seq *= chr_seq
    end
    Genome(LongDNASeq(total_seq), chrs)
end

Base.length(genome::Genome) = length(genome.seq)
Base.getindex(genome::Genome, key::String) = genome.seq[genome.chr[key]]

function chomosomecount(genome::Genome)
    return length(genome.chrs)
end

function Base.iterate(genome::Genome)
    (chr, slice) = first(genome.chrs)
    ((chr, genome.seq[slice]), 1)
end

function Base.iterate(genome::Genome, state::Int)
    state += 1
    state > genome.chrs.count && (return nothing)
    for (i, (chr, slice)) in enumerate(genome.chrs)
        (i == state) && (return ((chr, genome.seq[slice]), state))
    end
end

function Base.:*(genome1::Genome, genome2::Genome)
    return Genome(genome1.seq*genome2.seq, merge(genome1.chrs, Dict(key=>(range .+ length(genome1)) for (key, range) in genome2.chrs)))
end

function Base.write(file::String, genome::Genome)
    write_genomic_fasta(Dict(chr=>String(seq) for (chr, seq) in genome), file)
end

function read_genomic_fasta(fasta_file::String)
    genome::Dict{String, String} = Dict()
    chrs = String[]
    start_ids = Int[]
    name = ""
    open(fasta_file, "r") do file
        lines = readlines(file)
        startswith(lines[1], ">") && (name = join(split(lines[1])[2:end]))
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

function write_genomic_fasta(genome::Dict{String, String}, fasta_file::String; name=nothing, chars_per_row=80)
    open(fasta_file, "w") do file
        for (i, (chr, seq)) in enumerate(genome)
            s = String(seq)
            l = length(s)
            !isnothing(name) ? println(file, ">$chr") : println(file, ">$chr $name")
            for i in 0:length(seq)÷chars_per_row
                ((i+1)*chars_per_row > l) ? println(file, s[i*chars_per_row+1:end]) : println(file, s[i*chars_per_row+1:(i+1)*chars_per_row])
            end
        end
    end
end

function is_bitstring_fasta(file::String)
    (endswith(file, ".fasta") || endswith(file, ".fasta.gz")) || (return false)
    f = endswith(file, ".fasta.gz") ? GzipDecompressorStream(open(file, "r")) : open(file, "r")
    first_line = readline(f)
    close(f)
    ((length(first_line) == 65) && all([c in ['0', '1'] for c in first_line[2:end]])) && (return true)
    return false
end

struct PairedReads{T} <: SequenceContainer
    dict::Dict{T, LongDNASeqPair}
end

Base.length(reads::PairedReads) = length(reads.dict)
Base.keys(reads::PairedReads) = keys(reads.dict)
Base.values(reads::PairedReads) = values(reads.dict)
function Base.iterate(reads::PairedReads) 
    it = iterate(reads.dict)
    isnothing(it) ? (return nothing) : ((key, (read1, read2)), state) = it
    return ((read1, read2), state)
end
function Base.iterate(reads::PairedReads, state::Int) 
    it = iterate(reads.dict, state)
    isnothing(it) ? (return nothing) : ((key, (read1, read2)), state) = it
    return ((read1, read2), state)
end

function PairedReads(file1::String, file2::String; stop_at=nothing, hash_id=true)
    reads1 = read_reads(file1; nb_reads=stop_at, hash_id=hash_id)
    reads2 = read_reads(file2; nb_reads=stop_at, hash_id=hash_id)
    @assert length(reads1) == length(reads2)
    @assert all([haskey(reads2, key) for key in keys(reads1)])
    PairedReads(Dict(key=>(reads1[key], reads2[key]) for key in keys(reads1)))
end

function Base.write(fasta_file1::String, fasta_file2::String, reads::PairedReads)
    f1 = endswith(fasta_file1, ".gz") ? GzipCompressorStream(open(fasta_file1, "w")) : open(fasta_file1, "w")
    f2 = endswith(fasta_file2, ".gz") ? GzipCompressorStream(open(fasta_file2, "w")) : open(fasta_file2, "w")
    for (key, (read1, read2)) in reads.dict
        str_key = bitstring(key)
        write(f1, ">$str_key\n$(String(read1))\n")
        write(f2, ">$str_key\n$(String(read2))\n")
    end
    close(f1)
    close(f2)
end

struct Reads{T} <: SequenceContainer
    dict::Dict{T, LongDNASeq}
end

Base.length(reads::Reads) = length(reads.dict)
Base.keys(reads::Reads) = keys(reads.dict)
Base.values(reads::Reads) = values(reads.dict)
function Base.iterate(reads::Reads) 
    it = iterate(reads.dict)
    isnothing(it) ? (return nothing) : ((key, read), state) = it
    return (read, state)
end
function Base.iterate(reads::Reads, state::Int) 
    it = iterate(reads.dict, state)
    isnothing(it) ? (return nothing) : ((key, read), state) = it
    return (read, state)
end

function Base.write(fasta_file::String, reads::Reads{T}) where {T}
    f = endswith(fasta_file, ".gz") ? GzipCompressorStream(open(fasta_file, "w")) : open(fasta_file, "w")
    for (key, read) in reads.dict
        T === String ? write(f, ">$key\n$(String(read))\n") : write(f, ">$(bitstring(key))\n$(String(read))\n")
    end
    close(f)
end

Reads(seqs::Vector{LongDNASeq}) = Reads(Dict(i::UInt=>read for (i,seq) in enumerate(seqs)))

function Reads(file::String; stop_at=nothing, hash_id=true)
    reads = read_reads(file, nb_reads=stop_at, hash_id=hash_id)
    Reads(reads)
end

function Reads(f, paired_reads::PairedReads{T}; use_when_tied=:none) where {T}
    @assert use_when_tied in [:none, :read1, :read2]
    reads = Dict{T, LongDNASeq}()
    for (key, (read1, read2)) in paired_reads
        if use_when_tied == :read1 
            f(read1) ? push!(reads, key=>copy(read1)) : (f(read2) && push!(reads, key=>copy(read2)))
        elseif use_when_tied == :read2
            f(read2) ? push!(reads, key=>copy(read2)) : (f(read1) && push!(reads, key=>copy(read1)))
        elseif use_when_tied == :none
            check1, check2 = f(read1), f(read2)
            check1 && check2 && continue
            check1 && push!(reads, key=>copy(read1))
            check2 && push!(reads, key=>copy(read2))
        end
    end
    Reads(reads)
end

function read_reads(file::String; nb_reads=nothing, hash_id=true)
    @assert any([endswith(file, ending) for ending in [".fastq", ".fastq.gz", ".fasta", ".fasta.gz"]])
    reads::Dict{hash_id ? UInt : String, LongDNASeq} = Dict()
    is_fastq = any([endswith(file, ending) for ending in [".fastq", ".fastq.gz"]])
    is_zipped = endswith(file, ".gz")
    is_bitstring = is_bitstring_fasta(file)
    f = is_zipped ? GzipDecompressorStream(open(file, "r")) : open(file, "r")
    reader = is_fastq ? FASTQ.Reader(f) : FASTA.Reader(f)
    record = is_fastq ? FASTQ.Record() : FASTA.Record()
    sequencer = is_fastq ? FASTQ.sequence : FASTA.sequence
    read_counter = 0
    while !eof(reader)
        read!(reader, record)
        id = !hash_id ? identifier(record) : 
                (is_bitstring ? parse(UInt, identifier(record); base=2) : hash(record.data[record.identifier]))
        push!(reads, id => LongDNASeq(record.data[record.sequence]))
        read_counter += 1
        isnothing(nb_reads) || (read_counter >= nb_reads && break)
    end
    close(reader)
    return reads
end

function rev_comp!(reads::Reads)
    for read in reads
        BioSequences.reverse_complement!(read)
    end
end

function rev_comp!(reads::PairedReads; treat=:both)
    @assert treat in [:both, :read1, :read2]
    for (read1, read2) in reads
        treat in [:both, :read1] && BioSequences.reverse_complement!(read1)
        treat in [:both, :read2] && BioSequences.reverse_complement!(read2)
    end
end

#function rev_comp(files::SingleTypeFiles)
#    @assert files.type in [".fastq.gz", "fasta.gz", ".fastq", ".fasta"]
#    is_fastq = files.type in [".fastq", ".fastq.gz"]
#    is_zipped = endswith(files.type, ".gz")
#    record = is_fastq ? FASTQ.Record() : FASTA.Record()
#    sequencer = is_fastq ? FASTQ.sequence : FASTA.sequence
#    
#    for file in files
#        outfile = file * ".tmp"
#        f = is_zipped ? GzipDecompressorStream(open(file, "r")) : open(file, "r")
#        reader = is_fastq ? FASTQ.Reader(f) : FASTA.Reader(f)
#        writer = is_zipped ? GzipCompressorStream(open(outfile, "w")) : open(outfile, "w")
#        while !eof(reader)
#            read!(record, reader)
#        end
#    end
#end
#
#function rev_comp(files::PairedSingleTypeFiles; treat=:both)
#    @assert files.type in [".fastq.gz", "fasta.gz", ".fastq", ".fasta"]
#    @assert treat in [:both, :read1, :read2]
#    for (file1, file2) in files
#        reads = PairedReads(file1, file2)
#        rev_comp!(reads; treat=treat)
#        write(file1[1:end-length(files.type)] * ".fasta.gz", file2[1:end-length(files.type)] * ".fasta.gz", reads)
#    end
#end

function cut!(read::LongDNASeq, pos::Int; keep=:left, from=:left)
    0 <= pos <= length(read) || resize!(read, 0)
    
    if (from == :left) && (keep == :left)
        resize!(read, pos)

    elseif (from == :left) && (keep == :right)
        reverse!(resize!(reverse!(read), length(read)-pos, true))
    
    elseif (from == :right) && (keep == :left)
        resize!(read, length(read)-pos)
    
    elseif (from == :right) && (keep == :right)
        reverse!(resize!(reverse!(read), pos, true))
    end
end

function cut!(read::LongDNASeq, int::Tuple{Int, Int})
    (0 <= first(int) < last(int) <= length(read)) || resize!(read, 0)
    reverse!(resize!(reverse!(resize!(read, last(int), true)), length(read)-first(int)+1, true))
end

function cut!(reads::Reads, pos::Int; keep=:left, from=:left)
    for read in reads
        cut!(read, pos; keep=keep, from=from)
    end
end

function cut!(reads::PairedReads, pos::Int; keep=:left, from=:left)
    for (read1, read2) in reads
        ((pos > length(read1)) && (pos > length(read2))) && continue
        cut!(read1, pos; keep=keep, from=from)
        cut!(read2, pos; keep=keep, from=from)
    end
end

function cut!(reads::Reads, seq::LongDNASeq; keep=:left_of_query, from=:left)
    @assert keep in [:left_of_query, :right_of_query, :left_and_query, :right_and_query]
    @assert from in [:left, :right]
    for read in reads
        s = from == :left ? findfirst(seq, read) : findlast(seq, read)
        isnothing(s) && continue
        (start, stop) = s
        if keep == :right_of_query
            cut!(read, stop; keep=:right)
        elseif keep == :left_of_query
            cut!(read, start-1; keep=:left)
        elseif keep == :right_and_query
            cut!(read, start-1; keep=:right)
        elseif keep == :left_and_query
            cut!(read, stop; keep=:left)
        end
    end
end

function cut!(reads::PairedReads, seq::LongDNASeq; keep=:left_of_query, from=:left, treat=:both)
    @assert keep in [:left_of_query, :right_of_query, :left_and_query, :right_and_query]
    @assert treat in [:read1, :read2, :both]
    @assert from in [:left, :right]
    for (read1, read2) in reads
        s1 = treat in [:both, :read1] ? (from == :left ? findfirst(seq, read1) : findlast(seq, read1)) : nothing
        s2 = treat in [:both, :read2] ? (from == :left ? findfirst(seq, read2) : findlast(seq, read2)) : nothing
        if !isnothing(s1)
            start1, stop1 = s1
            if keep == :right_of_query
                cut!(read1, stop1; keep=:right)
            elseif keep == :left_of_query
                cut!(read1, start1-1; keep=:left)
            elseif keep == :right_and_query
                cut!(read1, start1-1; keep=:right)
            elseif keep == :left_and_query
                cut!(read1, stop1; keep=:left)
            end
        end
        if !isnothing(s2)
            start2, stop2 = s2
            if keep == :right_of_query
                cut!(read2, stop2; keep=:right)
            elseif keep == :left_of_query
                cut!(read2, start2-1; keep=:left)
            elseif keep == :right_and_query
                cut!(read2, start2-1; keep=:right)
            elseif keep == :left_and_query
                cut!(read2, stop2; keep=:left)
            end
        end
    end
end

function approxoccursin(s1::LongDNASeq, s2::LongDNASeq; k=1, check_indels=false)
    return approxsearch(s2, s1, k) != 0:-1
end

function Base.filter!(f, reads::Reads)
    for (key, read) in reads.dict
        f(read) || delete!(reads.dict, key)
    end
end

function Base.filter!(f, reads::PairedReads; logic=:or)
    @assert logic in [:or, :xor, :and]
    for (key, (read1, read2)) in reads.dict
        if logic == :and 
            f(read1) && f(read2) || delete!(reads.dict, key)
        elseif logic == :or
            f(read1) || f(read2) || delete!(reads.dict, key)
        elseif logic == :xor
            check1, check2 = f(read1), f(read2)
            ((check1 && !check2) || (!check1 && check2)) || delete!(reads.dict, key)
        end
    end
end

function similarity(read1::LongDNASeq, read2::LongDNASeq; score_model=nothing)
    isnothing(score_model) && (score_model = AffineGapScoreModel(match=1, mismatch=-1, gap_open=-1, gap_extend=-1))
    (length(read1) > length(read2)) ? ((short_seq, long_seq) = (read2, read1)) : ((short_seq, long_seq) = (read1, read2))
    aln = local_alignment(long_seq, short_seq, score_model)
    hasalignment(aln) || (return 0.0) 
    return count_matches(alignment(aln))/length(short_seq)
end

function similarity(reads::PairedReads{T}; window_size=10, step_size=2)
    similarities = Dict{T, Float64}()
    score_model = AffineGapScoreModel(match=1, mismatch=-1, gap_open=-1, gap_extend=-1)
    for (read1, read2) in reads
        push!(similarities, key=>similarity(read1, read2; score_model=score_model))
    end
    return similarities
end

function nucleotide_count(reads::Reads; normalize=true)
    max_length = maximum([length(read) for read in reads])
    count = Dict(DNA_A => zeros(max_length), DNA_T=>zeros(max_length), DNA_G=>zeros(max_length), DNA_C=>zeros(max_length), DNA_N=>zeros(max_length))
    nb_reads = length(reads)
    for read in reads
        (align==:left) ? 
        (index = 1:length(read)) : 
        (index = (max_length - length(read) + 1):max_length)
        for (i, n) in zip(index, read)
            count[n][i] += 1
        end
    end
    if normalize
        for (key, c) in count
            c /= length(reads)
        end
    end
    return count
end

function nucleotide_count(reads::PairedReads; normalize=true)
    max_length = maximum(vcat([[length(read1) length(read2)] for (read1, read2) in reads]...))
    count1 = Dict(DNA_A => zeros(max_length), DNA_T=>zeros(max_length), DNA_G=>zeros(max_length), DNA_C=>zeros(max_length), DNA_N=>zeros(max_length))
    count2 = Dict(DNA_A => zeros(max_length), DNA_T=>zeros(max_length), DNA_G=>zeros(max_length), DNA_C=>zeros(max_length), DNA_N=>zeros(max_length))
    nb_reads = length(reads)
    for (read1, read2) in reads
        (align==:left) ? 
        (index1 = 1:length(read1); index2 = 1:length(read2)) : 
        (index1 = (max_length - length(read1) + 1):max_length; index2 = (max_length - length(read2) + 1):max_length)
        for ((i1, n1),(i2, n2)) in zip(zip(index1, read1), zip(index2, read2))
            count1[n1][i1] += 1
            count2[n2][i2] += 1
        end
    end
    if normalize
        for ((key1, c1), (key2, c2)) in zip(count1, count2)
            c1 /= length(reads)
            c2 /= length(reads)
        end
    end
    return count1, count2
end

function extract_seqs(genome::Genome, features::Features)
    seqs = Vector{LongDNASeq}()
    for feature in features
        push!(seqs, genome[refname(feature)][leftposition(feature):rightposition(feature)])
    end
    return Reads(seqs)
end