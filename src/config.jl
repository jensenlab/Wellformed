"""
    Config

Runtime settings, normally loaded from a TOML file with [`load_config`](@ref). See
`wellformed.example.toml` for every key.
"""
Base.@kwdef struct Config
    watch_dirs::Vector{String} = String[]
    recursive::Bool = false
    extensions::Vector{String} = [".xlsx", ".xls", ".ses", ".csv", ".txt", ".xml"]
    poll_seconds::Float64 = 2.0
    settle_seconds::Float64 = 5.0
    check_existing::Bool = false
    unrecognized_is_failure::Bool = true
    alert_on_warnings::Bool = false
    log_path::String = "wellformed.log"
    machine_name::String = gethostname()
    popup_enabled::Bool = true
    basecamp_enabled::Bool = false
    basecamp_url::String = ""
end

_get(t, k, default) = get(t, k, default)

function load_config(path::AbstractString)
    t = TOML.parsefile(path)
    popup = get(t, "popup", Dict{String,Any}())
    bc = get(t, "basecamp", Dict{String,Any}())
    d = Config()
    # The chatbot URL is a secret; allow it to come from the environment instead of the file.
    url = get(ENV, "WELLFORMED_BASECAMP_URL", string(get(bc, "url", "")))
    logp = get(t, "log_path", d.log_path)
    isabspath(logp) || (logp = joinpath(dirname(abspath(path)), logp))   # relative to the config file, not the cwd
    return Config(;
        watch_dirs = String.(get(t, "watch_dirs", d.watch_dirs)),
        recursive = get(t, "recursive", d.recursive),
        extensions = lowercase.(String.(get(t, "extensions", d.extensions))),
        poll_seconds = Float64(get(t, "poll_seconds", d.poll_seconds)),
        settle_seconds = Float64(get(t, "settle_seconds", d.settle_seconds)),
        check_existing = get(t, "check_existing", d.check_existing),
        unrecognized_is_failure = get(t, "unrecognized_is_failure", d.unrecognized_is_failure),
        alert_on_warnings = get(t, "alert_on_warnings", d.alert_on_warnings),
        log_path = logp,
        machine_name = get(t, "machine_name", d.machine_name),
        popup_enabled = get(popup, "enabled", d.popup_enabled),
        basecamp_enabled = get(bc, "enabled", d.basecamp_enabled),
        basecamp_url = url,
    )
end

"Where the per-user config lives when no path is given (also holds the log by default)."
function config_path()
    haskey(ENV, "WELLFORMED_CONFIG") && return ENV["WELLFORMED_CONFIG"]
    dir = if Sys.iswindows()
        joinpath(get(ENV, "APPDATA", homedir()), "Wellformed")
    elseif Sys.isapple()
        joinpath(homedir(), "Library", "Application Support", "Wellformed")
    else
        joinpath(get(ENV, "XDG_CONFIG_HOME", joinpath(homedir(), ".config")), "wellformed")
    end
    return joinpath(dir, "config.toml")
end

"Copy of `cfg` with some fields replaced."
with(cfg::Config; kw...) =
    Config(; merge(NamedTuple{fieldnames(Config)}(getfield.(Ref(cfg), fieldnames(Config))), NamedTuple(kw))...)

"Write `cfg` as TOML (creating the folder). The file holds the Basecamp URL, so it is made owner-only on Unix."
function save_config(cfg::Config, path::AbstractString)
    mkpath(dirname(abspath(path)))
    d = Dict{String,Any}(
        "watch_dirs" => cfg.watch_dirs, "recursive" => cfg.recursive, "extensions" => cfg.extensions,
        "poll_seconds" => cfg.poll_seconds, "settle_seconds" => cfg.settle_seconds,
        "check_existing" => cfg.check_existing, "unrecognized_is_failure" => cfg.unrecognized_is_failure,
        "alert_on_warnings" => cfg.alert_on_warnings, "log_path" => cfg.log_path,
        "machine_name" => cfg.machine_name,
        "popup" => Dict{String,Any}("enabled" => cfg.popup_enabled),
        "basecamp" => Dict{String,Any}("enabled" => cfg.basecamp_enabled, "url" => cfg.basecamp_url),
    )
    open(io -> TOML.print(io, d; sorted=true), path, "w")
    Sys.iswindows() || chmod(path, 0o600)
    return path
end
