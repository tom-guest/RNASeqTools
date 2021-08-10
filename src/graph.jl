mutable struct Interactions <: InteractionContainer
    graph::MetaDiGraph
    replicate_ids::Vector{Symbol}
end

function order(tu::Tuple{String,String}, alignment::AlignedRead)
    for (i, part) in enumerate(alignment)
        (name(part), type(part)) == tu && (return i)
    end
    return -1
end

function order(tu::Tuple{String,String}, alignment1::AlignedRead, alignment2::AlignedRead)
    o1 = order(tu, alignment1)
    if o1 == -1 
        o2 = order(tu, alignment2)
        o2 == -1 && error("$tu not found in any alignment!")
        return o2 + length(alignment1)
    else
        return o1
    end
end

function ordered(tu_set::AbstractSet, alignment1::AlignedRead, alignment2::AlignedRead)
    c = collect(tu_set)
    i = sortperm([order(tu, alignment1, alignment2) for tu in c])
    return c[i]
end

function refname(tu::Tuple{String,String}, alignment1::AlignedRead, alignment2::AlignedRead)
    for part in alignment1
        (name(part), type(part)) == tu && (return refname(part))
    end
    for part in alignment2
        (name(part), type(part)) == tu && (return refname(part))
    end
    return "NA"
end

function positions(tu::Tuple{String,String}, alignment1::AlignedRead, alignment2::AlignedRead)
    lp, rp = 2^63-1, -1
    for part in alignment1
        (name(part), type(part)) == tu && (lp = min(lp,leftposition(part)); rp = max(rp,rightposition(part)))
    end
    for part in alignment2
        (name(part), type(part)) == tu && (lp = min(lp,leftposition(part)); rp = max(rp,rightposition(part)))
    end
    return (lp, rp)
end

function nodestrand(tu::Tuple{String,String}, alignment1::AlignedRead, alignment2::AlignedRead)
    for part in alignment1
        (name(part), type(part)) == tu && (return strand(part))
    end
    for part in alignment2
        (name(part), type(part)) == tu && (return strand(part))
    end
    return 'o'
end

mutable struct AlignmentInfo
    name::String
    type::String
    left::Int
end

function info_dict(alignment1::Alignment, alignment2::Alignment)
    d = Dict{String, Tuple{}}
    for part in alignment1
        hasannotation(part) || continue
        n = name(part)
        if n in keys(d)
        end
    end
end

function update_stats!(stats::NTuple{6, Dict{Int64, Int64}}, l1::Int, r1::Int, l2::Int, r2::Int)
    d1, d2 = r1-l1+1, r2-l2+1
    for (i, x) in enumerate((d1,d2,l1,l2,r1,r2))
        x in keys(stats[i]) ? stats[i][x] += 1 : stats[i][x] = 1
    end
end

function integrate!(graph::MetaDiGraph, alignments::PairedAlignments; replicate_id=:first, min_distance=1000, filter_types=[])
    trans = Dict{Tuple{String,String}, Int}()
    for node in vertices(graph)
        trans[(get_prop(graph, node, :name), get_prop(graph, node, :type))] = node
    end
    stats = Dict{LightGraphs.SimpleGraphs.SimpleEdge, NTuple{6, Dict{Int64, Int64}}}()
    for (alignment1, alignment2) in alignments
        if hasannotation(alignment1) && hasannotation(alignment2)
            !isempty(filter_types) && typein(alignment1, alignment2, filter_types) && continue
            chimeric = ischimeric(alignment1, alignment2; min_distance=min_distance)
            tu_set = union(Set((name(part),type(part)) for part in alignment1 if hasannotation(part)), Set((name(part),type(part)) for part in alignment2 if hasannotation(part)))
            tus = ordered(tu_set, alignment1, alignment2)
            nb_diff = length(Set(tu[1] for tu in tus))
            for tu in tus
                if !(tu in keys(trans))
                    trans[tu] = length(trans) + 1
                    add_vertex!(graph)
                    set_props!(graph, nv(graph), Dict(:name=>first(tu), :type=>last(tu), :refname=>refname(tu, alignment1, alignment2), 
                                                        :nb_ints=>0, :nb_single=>0, :strand=>nodestrand(tu, alignment1, alignment2)))
                end
                chimeric ?
                set_prop!(graph, trans[tu], :nb_ints, get_prop(graph, trans[tu], :nb_ints)+nb_diff-1) :
                set_prop!(graph, trans[tu], :nb_single, get_prop(graph, trans[tu], :nb_single)+1)
            end

            if chimeric
                multi = nb_diff > 2
                for ((a, tu1), (b,tu2)) in combinations([(trans[tu], tu) for tu in tus], 2)
                    get_prop(graph, a, :name) == get_prop(graph, b, :name) && continue
                    left1, right1 = positions(tu1, alignment1, alignment2)
                    left2, right2 = positions(tu2, alignment1, alignment2)
                    e = LightGraphs.SimpleGraphs.SimpleEdge(a,b)
                    e in keys(stats) || (stats[e] = Tuple(Dict{Int,Int}() for _ in 1:6))
                    update_stats!(stats[e], left1, right1, left2, right2)
                    
                    if add_edge!(graph, e)
                        set_props!(graph, e, Dict(:nb_ints=>1, :nb_multi=> (multi ? 1 : 0), replicate_id=>1, :minleft1=>left1, :maxright1=>right1, 
                                                        :minleft2=>left2, :maxright2=>right2))
                    else
                        set_prop!(graph, e, :nb_ints , get_prop(graph, e, :nb_ints) + 1)
                        set_prop!(graph, e, :nb_multi , get_prop(graph, e, :nb_multi) + (multi ? 1 : 0))
                        set_prop!(graph, e, :minleft1 , min(get_prop(graph, e, :minleft1), left1))
                        set_prop!(graph, e, :maxright1 , max(get_prop(graph, e, :maxright1), right1))
                        set_prop!(graph, e, :minleft2 , min(get_prop(graph, e, :minleft2), left2))
                        set_prop!(graph, e, :maxright2 , max(get_prop(graph, e, :maxright2), right2))
                    end
                    has_prop(graph, e, replicate_id) || set_prop!(graph, e, replicate_id, 1)
                end
            end
        end
    end
    for (e, distributions) in stats
        for (key_symbol, distribution) in zip((:length1, :length2, :modeleft1, :modeleft2, :moderight1, :moderight2), distributions)
            vs = has_prop(graph, e, key_symbol) ? get_prop(graph, e, key_symbol) : Vector{Int}()
            set_prop!(graph, e, key_symbol, push!(vs, argmax(distribution)))
        end
    end
end

function Interactions()
    return Interactions(MetaDiGraph(), [])
end

function Interactions(alignments::PairedAlignments; replicate_id=:first, min_distance=1000, filter_types=[])
    graph = MetaDiGraph()
    integrate!(graph, alignments; replicate_id=replicate_id, min_distance=min_distance, filter_types=filter_types)
    return Interactions(graph, [replicate_id])
end

function Base.append!(interactions::Interactions, alignments::PairedAlignments; replicate_id=:second, min_distance=1000, filter_types=[])
    integrate!(interactions.graph, alignments; replicate_id=replicate_id, min_distance=min_distance, filter_types=filter_types)
    push!(interactions.replicate_ids, replicate_id)
end

function annotate!(interactions::Interactions, features::Features; method=:disparity)
    @assert method in (:disparity, :fisher)
    pvalues = ones(ne(interactions.graph))
    all_interactions = sum(get_prop(interactions.graph, node, :nb_ints) for node in vertices(interactions.graph))
    tus = Dict{Tuple{String,String},Tuple{Int,Int}}((name(feature),type(feature))=>(leftposition(feature),rightposition(feature)) for feature in features)

    for (i,edge) in enumerate(edges(interactions.graph))
        if method === :fisher
            ints_between = get_prop(interactions.graph, edge, :nb_ints)
            ints_other_source = get_prop(interactions.graph, src(edge), :nb_ints) - ints_between
            ints_other_target = get_prop(interactions.graph, dst(edge), :nb_ints) - ints_between
            test = FisherExactTest(ints_between, ints_other_target, ints_other_source, all_interactions-ints_between-ints_other_source-ints_other_target)
            pvalues[i] = pvalue(test; tail=:right)
        elseif method === :disparity
            p_source = (1-get_prop(interactions.graph, edge, :nb_ints)/get_prop(interactions.graph, src(edge), :nb_ints))^(degree(interactions.graph, src(edge))-1)
            p_target = (1-get_prop(interactions.graph, edge, :nb_ints)/get_prop(interactions.graph, dst(edge), :nb_ints))^(degree(interactions.graph, dst(edge))-1)
            pvalues[i] = min(p_source, p_target)
        end
    end

    adjp = adjust(PValues(pvalues), BenjaminiHochberg())
    for (i, edge) in enumerate(edges(interactions.graph))
        set_prop!(interactions.graph, edge, :p_value, pvalues[i])
        set_prop!(interactions.graph, edge, :fdr, adjp[i])
        ispositive1 = get_prop(interactions.graph, src(edge), :strand) === STRAND_POS
        ispositive2 = get_prop(interactions.graph, dst(edge), :strand) === STRAND_POS
        rna1_pos = mean(get_prop(interactions.graph, edge, ispositive1 ? :moderight1 : :modeleft1))
        rna2_pos = mean(get_prop(interactions.graph, edge, ispositive2 ? :modeleft2 : :moderight2))
        (feature1_left, feature1_right) = tus[(get_prop(interactions.graph, src(edge), :name), get_prop(interactions.graph, src(edge), :type))]
        (feature2_left, feature2_right)  = tus[(get_prop(interactions.graph, dst(edge), :name), get_prop(interactions.graph, dst(edge), :type))]
        relpos1 = ispositive1 ? min(1.0, max(0.0, (rna1_pos - feature1_left)/(feature1_right - feature1_left))) : min(1.0, max(0.0, (feature1_right - rna1_pos)/(feature1_right - feature1_left)))
        relpos2 = ispositive2 ? min(1.0, max(0.0, (rna2_pos - feature2_left)/(feature2_right - feature2_left))) : min(1.0, max(0.0, (feature2_right - rna2_pos)/(feature2_right - feature2_left)))
        set_prop!(interactions.graph, edge, :relpos1, round(relpos1; digits=4))
        set_prop!(interactions.graph, edge, :relpos2, round(relpos2; digits=4))
    end
    return interactions
end

function asdataframe(interactions::Interactions; output=:edges, min_interactions=5, max_fdr=0.05)
    if output === :edges
        frame = DataFrame(name1=repeat([""], ne(interactions.graph)), type1=repeat([""], ne(interactions.graph)), ref1=repeat([""], ne(interactions.graph)), 
                        name2=repeat([""], ne(interactions.graph)), type2=repeat([""], ne(interactions.graph)), ref2=repeat([""], ne(interactions.graph)), 
                        nb_chimeras=repeat([0], ne(interactions.graph)), nb_multi=repeat([0], ne(interactions.graph)), p_value=repeat([1.], ne(interactions.graph)),
                        fdr=repeat([1.], ne(interactions.graph)), in_libs=repeat([0], ne(interactions.graph)), strand1=repeat(['o'], ne(interactions.graph)),
                        modeleft1=repeat([-1], ne(interactions.graph)), moderight1=repeat([-1], ne(interactions.graph)), modeleft2=repeat([-1], ne(interactions.graph)), 
                        moderight2=repeat([-1], ne(interactions.graph)), strand2=repeat(['o'], ne(interactions.graph)), 
                        relpos1=repeat([-1.0], ne(interactions.graph)), relpos2=repeat([-1.0], ne(interactions.graph)), length1=repeat([0.0], ne(interactions.graph)), 
                        length2=repeat([0.0], ne(interactions.graph)), minleft1=repeat([-1], ne(interactions.graph)), maxright1=repeat([-1], ne(interactions.graph)),
                        minleft2=repeat([-1], ne(interactions.graph)), maxright2=repeat([-1], ne(interactions.graph)))
        for (i,edge) in enumerate(edges(interactions.graph))
            if has_prop(interactions.graph, edge, :fdr) 
                fdr = get_prop(interactions.graph, edge, :fdr)
                fdr > max_fdr && continue
                frame[i, :fdr] = fdr
            end
            has_prop(interactions.graph, edge, :p_value) && (frame[i, :p_value] = get_prop(interactions.graph, edge, :p_value))
            frame[i, :name1] = get_prop(interactions.graph, src(edge), :name)
            frame[i, :type1] = get_prop(interactions.graph, src(edge), :type)
            frame[i, :ref1] = get_prop(interactions.graph, src(edge), :refname)
            frame[i, :name2] = get_prop(interactions.graph, dst(edge), :name)
            frame[i, :type2] = get_prop(interactions.graph, dst(edge), :type)
            frame[i, :ref2] = get_prop(interactions.graph, dst(edge), :refname)
            frame[i, :minleft1] = get_prop(interactions.graph, edge, :minleft1)
            frame[i, :maxright1] = get_prop(interactions.graph, edge, :maxright1)
            frame[i, :minleft2] = get_prop(interactions.graph, edge, :minleft2)
            frame[i, :maxright2] = get_prop(interactions.graph, edge, :maxright2)
            frame[i, :modeleft1] = floor(mean(get_prop(interactions.graph, edge, :modeleft1)))
            frame[i, :moderight1] = floor(mean(get_prop(interactions.graph, edge, :moderight1)))
            frame[i, :modeleft2] = floor(mean(get_prop(interactions.graph, edge, :modeleft2)))
            frame[i, :moderight2] = floor(mean(get_prop(interactions.graph, edge, :moderight2)))
            frame[i, :strand1] = get_prop(interactions.graph, src(edge), :strand)
            frame[i, :strand2] = get_prop(interactions.graph, dst(edge), :strand)
            frame[i, :relpos1] = get_prop(interactions.graph, edge, :relpos1)
            frame[i, :relpos2] = get_prop(interactions.graph, edge, :relpos2)
            frame[i, :nb_chimeras] = get_prop(interactions.graph, edge, :nb_ints)
            frame[i, :nb_multi] = get_prop(interactions.graph, edge, :nb_multi)
            frame[i, :in_libs] = sum(has_prop(interactions.graph, edge, replicate_id) for replicate_id in interactions.replicate_ids)
            frame[i, :length1] = mean(get_prop(interactions.graph, edge, :length1))
            frame[i, :length2] = mean(get_prop(interactions.graph, edge, :length2))
        end
        return filter(:nb_chimeras => >=(min_interactions), sort(frame, :nb_chimeras; rev=true))
    elseif output === :nodes
        frame = DataFrame(name=repeat([""], nv(interactions.graph)), type=repeat([""], nv(interactions.graph)), ref=repeat([""], nv(interactions.graph)),
                            nb_single=repeat([0], nv(interactions.graph)))
        for (i,node) in enumerate(vertices(interactions.graph))
            frame[i, :name] = get_prop(interactions.graph, node, :name)
            frame[i, :type] = get_prop(interactions.graph, node, :type)
            frame[i, :ref] = get_prop(interactions.graph, node, :refname)
            frame[i, :nb_single] = get_prop(interactions.graph, node, :nb_single)
        end
        return sort(frame, :nb_single; rev=true)
    end     
end