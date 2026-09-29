mutable struct Watcher
    dirs::Vector{String}
    recursive::Bool
    extensions::Vector{String}
    settle::Float64
    seen::Dict{String,NamedTuple{(:size, :mtime, :since),Tuple{Int,Float64,Float64}}}
    done::Dict{String,Tuple{Int,Float64}}
end

Watcher(cfg::Config) = Watcher(cfg.watch_dirs, cfg.recursive, cfg.extensions, cfg.settle_seconds,
                               Dict(), Dict())

_is_candidate(w::Watcher, path) = begin
    name = basename(path)
    !startswith(name, "~\$") && !startswith(name, ".") &&
        lowercase(splitext(name)[2]) in w.extensions
end

function _list(w::Watcher)
    paths = String[]
    for d in w.dirs
        isdir(d) || continue
        if w.recursive
            for (root, _, files) in walkdir(d), f in files
                push!(paths, joinpath(root, f))
            end
        else
            for f in readdir(d; join=true)
                isfile(f) && push!(paths, f)
            end
        end
    end
    return filter(p -> _is_candidate(w, p), paths)
end

"""
    poll!(w::Watcher, now::Real) -> Vector{String}

One scan. Returns files that have been unchanged (size and mtime) for `settle` seconds and can be
opened for reading -- i.e. finished being written -- and that have not been returned before at that
size/mtime. A file that is still growing is never returned, so a partially-written export is not
mistaken for a truncated one.
"""
function poll!(w::Watcher, now::Real)
    ready = String[]
    present = _list(w)
    for p in present
        st = try stat(p) catch; continue end
        key = (Int(st.size), st.mtime)
        get(w.done, p, nothing) == key && continue
        e = get(w.seen, p, nothing)
        if e === nothing || (e.size, e.mtime) != key
            w.seen[p] = (size=key[1], mtime=key[2], since=Float64(now))
            continue
        end
        now - e.since >= w.settle || continue
        try
            open(io -> read(io, 1), p)   # still locked by the instrument software?
        catch
            continue
        end
        w.done[p] = key
        delete!(w.seen, p)
        push!(ready, p)
    end
    for p in collect(keys(w.seen))
        p in present || delete!(w.seen, p)
    end
    return ready
end

"Mark everything currently in the watch folders as already handled (used when `check_existing=false`)."
function mark_existing!(w::Watcher)
    for p in _list(w)
        st = stat(p)
        w.done[p] = (Int(st.size), st.mtime)
    end
end
