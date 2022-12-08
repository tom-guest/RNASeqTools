module RNASeqTools

import XAM: BAM
using FASTX, CodecZlib, GFF3, BigWig, DelimitedFiles, BGZFStreams
using BioAlignments, BioSequences, GenomicFeatures, BioGenerics
import DataFrames: DataFrame, sort, nrow, names, innerjoin
using Statistics, HypothesisTests, MultipleTesting, Combinatorics, Random, Distributions, GLM, StatsBase
using IterTools

export align_mem, align_minimap, align_kraken2
export preprocess_data, trim_fastp, split_libs, download_prefetch, download_fasterq, transform, split_interleaved, split_each_read
export Genome, Sequences, PairedSequences, AlignedReads, AlignedInterval, AlignedRead, SingleTypeFiles, PairedSingleTypeFiles, Features, Coverage
export Annotation, AlignmentAnnotation, BaseAnnotation, BaseCoverage, Counts, FeatureCounts, GenomeComparison, Logo
export FastaFiles, FastagzFiles, FastqFiles, FastqgzFiles, BamFiles, GenomeFiles, GffFiles, CoverageFiles, CsvFiles
export PairedFastaFiles, PairedFastagzFiles, PaireFastqFiles, PairedFastqgzFiles
export cut!, nucleotidedistribution, annotate!, featureseqs, asdataframe, ispositivestrand, hasannotation, nannotated, editdistance
export nannotation, ischimeric, ismulti, refinterval, readrange, refrange, annotation, hasannotation, ispositivestrand, sameread, nread
export name, type, overlap, parts, refname, featureparams, featureparam, setfeatureparam!, hastype, hasname, typein, namein, distanceonread
export hasoverlap, firstoverlap, compute_coverage, merge!, merge, correlation, covratio, normalize!, hasannotationkey, readid, summarize
export add5utrs!, add3utrs!, addutrs!, addigrs!, maxdiffpositions, consensusseq, consensusbits, nintervals
export eachpair, isfirstread, sync!
export groupfiles, difference_table

include("types.jl")
include("files.jl")
include("preprocess.jl")
include("sequence.jl")
include("coverage.jl")
include("annotation.jl")
include("counts.jl")
include("alignment.jl")

const FASTQ_TYPES = (".fastq", ".fastq.gz", ".fq", ".fq.gz")
const FASTA_TYPES = (".fasta", ".fasta.gz", ".fa", ".fa.gz", ".fna", ".fna.gz")

end
