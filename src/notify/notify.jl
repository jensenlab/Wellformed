"""
    Notifier

Something that can tell a person a file is bad. Implement `notify(n, result, cfg)`. Errors thrown
by a notifier are caught by the caller and logged; they never stop the watcher.
"""
abstract type Notifier end

function alert_text(r::CheckResult, cfg::Config)
    io = IOBuffer()
    println(io, r.status == FAIL ? "Data file problem on $(cfg.machine_name)" :
                                   "Data file warning on $(cfg.machine_name)")
    println(io, "File: ", basename(r.path))
    for i in r.issues
        println(io, "- [", i.severity, "] ", i.message)
    end
    r.status == FAIL && print(io, "Do not discard the plate until the data has been re-exported and rechecked.")
    return strip(String(take!(io)))
end

include("popup.jl")
include("basecamp.jl")
include("log.jl")

function default_notifiers(cfg::Config)
    ns = Notifier[]
    cfg.popup_enabled && push!(ns, PopupNotifier())
    cfg.basecamp_enabled && push!(ns, BasecampNotifier(cfg.basecamp_url))
    return ns
end
