function split_libs(infile1::String, prefixfile1::Union{String,Nothing}, infile2::Union{String,Nothing}, barcodes::Dict{String,String}, output_path::String; overwrite_existing=false)

    dplxr = Demultiplexer(LongDNASeq.(collect(values(barcodes))), n_max_errors=1, distance=:hamming)
    bc_len = [length(v) for v in values(barcodes)][1]
    output_files = isnothing(infile2) ? 
    [joinpath(output_path, "$(name).fastq.gz") for name in keys(barcodes)] :
    [[joinpath(output_path, "$(name)_1.fastq.gz"), joinpath(output_path, "$(name)_2.fastq.gz")] for name in keys(barcodes)]
    for file in output_files
        isnothing(infile2) ?
        (isfile(file) && return) :
        ((isfile(file[1]) || isfile(file[2])) && return)
    end
    stats::Array{Int,1} = zeros(Int, length(barcodes))
    record1::FASTQ.Record = FASTQ.Record()
    isnothing(infile2) || (record2::FASTQ.Record = FASTQ.Record())
    isnothing(prefixfile1) || (recordp::FASTQ.Record = FASTQ.Record())
    endswith(infile1, ".gz") ? reader1 = FASTQ.Reader(GzipDecompressorStream(open(infile1, "r"))) : reader1 = FASTQ.Reader(open(infile1, "r"))
    isnothing(infile2) || (endswith(infile2, ".gz") ? 
                            reader2 = FASTQ.Reader(GzipDecompressorStream(open(infile2, "r"))) : 
                            reader2 = FASTQ.Reader(open(infile2, "r")))
    isnothing(prefixfile1) || (endswith(prefixfile1, ".gz") ? 
                                readerp = FASTQ.Reader(GzipDecompressorStream(open(prefixfile1, "r"))) : 
                                readerp = FASTQ.Reader(open(prefixfile1, "r")))
    writers = isnothing(infile2) ?
                [FASTQ.Writer(GzipCompressorStream(open(outfile1, "w"), level=2))
                for outfile1 in output_files] :
                [[FASTQ.Writer(GzipCompressorStream(open(outfile1, "w"), level=2)),
                FASTQ.Writer(GzipCompressorStream(open(outfile2, "w"), level=2))] 
                for (outfile1, outfile2) in output_files] 
    unidentified_writer = FASTQ.Writer(GzipCompressorStream(open(joinpath(output_path, "unidentified.fastq.gz"), "w"), level=2))
    c = 0
    while !eof(reader1)
        read!(reader1, record1)
        isnothing(infile2) || read!(reader2, record2)
        isnothing(prefixfile1) || read!(readerp, recordp)
        c += 1
        nb_errors = -1
        isnothing(prefixfile1) || (prefix = LongDNASeq(FASTQ.sequence(recordp)); (library_id, nb_errors) = demultiplex(dplxr, prefix))
        if (nb_errors == -1)
            read = LongDNASeq(FASTQ.sequence(record1))
            (library_id, nb_errors) = demultiplex(dplxr, read[1:bc_len])
            (nb_errors == -1) && (write(unidentified_writer, record1); isnothing(infile2) || write(unidentified_writer, record2); continue)
        end
        stats[library_id] += 1
        isnothing(infile2) ?
        write(writers[library_id], record1) :
        (write(writers[library_id][1], record1); write(writers[library_id][2], record2))
    end
    close(reader1)
    isnothing(infile2) || close(reader2)
    close(unidentified_writer)
    for w in writers
        isnothing(infile2) ?
        close(w) :
        (close(w[1]);close(w[2]))
    end
    count_string = join(["$(name) - $(stat)\n" for (name, stat) in zip(barcodes, stats)])
    count_string *= "\nnot identifyable - $(c-sum(stats))\n"
    count_string = "Counted $c entries in total\n\n$count_string\n"
    write(infile1 * ".log", count_string)
end

function split_libs(infile1::String, infile2::String, barcodes::Dict{String,String}, output_path::String)
    split_libs(infile1, nothing, infile2, barcodes, output_path)
end

function split_libs(infile::String, barcodes::Dict{String,String}, output_path::String)
    split_libs(infile, nothing, nothing, barcodes, output_path)
end

function trim_fastp(input_files::Vector{Tuple{String, Union{String, Nothing}}}; 
    fastp_bin="fastp", prefix="trimmed_", adapter=nothing, umi=nothing, umi_loc=:read1, min_length=nothing, 
    cut_front=true, cut_tail=true, trim_poly_g=nothing, trim_poly_x=nothing, filter_complexity=nothing,
    average_window_quality=nothing, skip_quality_filtering=false, overwrite_existing=false)

    for (in_file1, in_file2) in input_files
        @assert endswith(in_file1, ".fasta") || endswith(in_file1, ".fasta.gz") || endswith(in_file1, ".fastq") || endswith(in_file1, ".fastq.gz")
        isnothing(in_file2) || (@assert endswith(in_file1, ".fasta") || endswith(in_file1, ".fasta.gz") || endswith(in_file1, ".fastq") || endswith(in_file1, ".fastq.gz"))
    end
    @assert umi_loc in [:read1, :read2]

    params = []
    skip_quality_filtering && push!(params, "--disable_quality_filtering")
    !skip_quality_filtering && !isnothing(average_window_quality) && push!(params, "--cut_mean_quality=$average_window_quality")
    !skip_quality_filtering && cut_tail && push!(params, "--cut_tail")
    !skip_quality_filtering && cut_front && push!(params, "--cut_front")

    !isnothing(filter_complexity) && append!(params, ["-y" "--complexity_threshold=$filter_complexity"])
    !isnothing(trim_poly_x) && append!(params, ["-x", "--poly_x_min_len=$trim_poly_x"])
    !isnothing(trim_poly_g) ? append!(params, ["-g", "--poly_g_min_len=$trim_poly_g"]) : push!(params,"-G")
    !isnothing(min_length) && push!(params, "--length_required=$min_length")
    !isnothing(umi) && append!(params, ["-U", "--umi_loc=$(String(umi_loc))", "--umi_len=$umi"])
    !isnothing(adapter) && push!(params, "--adapter_sequence=$adapter")

    for (in_file1, in_file2) in input_files
        startswith(basename(in_file1), prefix) && continue
        html_file = joinpath(dirname(in_file1), prefix * (endswith(in_file1, ".gz") ? basename(in_file1)[1:end-9] : basename(in_file1)[1:end-6]) * ".html")
        json_file = joinpath(dirname(in_file1), prefix * (endswith(in_file1, ".gz") ? basename(in_file1)[1:end-9] : basename(in_file1)[1:end-6]) * ".json")
        out_file1 = joinpath(dirname(in_file1), prefix * basename(in_file1))
        (isfile(out_file1) && !overwrite_existing) && continue
        out_file2 = !isnothing(in_file2) ? joinpath(dirname(in_file2), prefix * basename(in_file2)) : nothing
        file_params = ["--in1=$in_file1", "--out1=$out_file1", "--html=$(html_file)", "--json=$(json_file)"]
        !isnothing(in_file2) && append!(file_params, ["--in2=$in_file2", "--out2=$out_file2"])
        cmd = `$fastp_bin $file_params $params`
        run(cmd)
    end 

end

function trim_fastp(input_files::SingleTypeFiles; 
    fastp_bin="fastp", prefix="trimmed_", adapter=nothing, umi=nothing, min_length=25, 
    cut_front=true, cut_tail=true, trim_poly_g=nothing, trim_poly_x=10, filter_complexity=nothing,
    average_window_quality=25, skip_quality_filtering=false)

    files = Vector{Tuple{String, Union{String, Nothing}}}([(file, nothing) for file in input_files])
    trim_fastp(files; fastp_bin=fastp_bin, prefix=prefix, adapter=adapter, umi=umi, umi_loc=:read1, min_length=min_length,
        cut_front=cut_front, cut_tail=cut_tail, trim_poly_g=trim_poly_g, trim_poly_x=trim_poly_x, filter_complexity=filter_complexity, average_window_quality=average_window_quality, skip_quality_filtering=skip_quality_filtering)
    return SingleTypeFiles([joinpath(dirname(file),prefix*basename(file)) for file in input_files if !startswith(basename(file), prefix)], input_files.type)
end

function trim_fastp(input_files::PairedSingleTypeFiles; 
    fastp_bin="fastp", prefix="trimmed_", adapter=nothing, umi=nothing, umi_loc=:read1, min_length=25, 
    cut_front=true, cut_tail=true, trim_poly_g=nothing, trim_poly_x=10, filter_complexity=nothing,
    average_window_quality=25, skip_quality_filtering=false)

    files = Vector{Tuple{String, Union{String, Nothing}}}(input_files.list)
    trim_fastp(files; fastp_bin=fastp_bin, prefix=prefix, adapter=adapter, umi=umi, umi_loc=umi_loc, min_length=min_length, cut_front=cut_front,
        cut_tail=cut_tail, trim_poly_g=trim_poly_g, trim_poly_x=trim_poly_x, filter_complexity=filter_complexity, average_window_quality=average_window_quality, skip_quality_filtering=skip_quality_filtering)
    return PairedSingleTypeFiles([(joinpath(dirname(file1),prefix*basename(file1)), joinpath(dirname(file2),prefix*basename(file2))) for (file1, file2) in input_files if !startswith(basename(file1), prefix) | !startswith(basename(file2), prefix)], input_files.type, input_files.suffix1, input_files.suffix2)
end