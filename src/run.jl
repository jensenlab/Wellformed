should_alert(r::CheckResult, cfg::Config) = r.status == FAIL || (r.status == WARN && cfg.alert_on_warnings)

"""
    handle_result(cfg, r, notifiers)

Log `r`, then alert if warranted. Each notifier runs in its own task so a blocking popup never
delays the Basecamp post or the next file check; notifier errors are logged, not thrown.
"""
function handle_result(cfg::Config, r::CheckResult, notifiers::Vector{<:Notifier})
    log_result(cfg, r)
    tasks = Task[]
    should_alert(r, cfg) || return tasks
    for n in notifiers
        push!(tasks, @async try
            notify(n, r, cfg)
        catch e
            log_message(cfg, "$(nameof(typeof(n))) failed: " * _errmsg(e))
        end)
    end
    return tasks
end

"""
    run_watcher(cfg; notifiers=default_notifiers(cfg), stop=Ref(false), maxpolls=typemax(Int))

Poll the configured folders until `stop[]` is set (or `maxpolls` scans), checking each settled file.
"""
function run_watcher(cfg::Config; notifiers::Vector{<:Notifier}=default_notifiers(cfg),
                     stop::Ref{Bool}=Ref(false), maxpolls::Integer=typemax(Int))
    w = Watcher(cfg)
    cfg.check_existing || mark_existing!(w)
    log_message(cfg, "started; watching " * join(cfg.watch_dirs, ", "))
    tasks = Task[]
    for _ in 1:maxpolls
        stop[] && break
        for p in poll!(w, time())
            r = try
                check_file(p; unrecognized_is_failure=cfg.unrecognized_is_failure)
            catch e   # a bug in the checker must still surface to the operator
                CheckResult(p, FAIL, [Issue(FAIL, "checker error: " * _errmsg(e))], "", 0.0)
            end
            append!(tasks, handle_result(cfg, r, notifiers))
        end
        filter!(!istaskdone, tasks)
        sleep(cfg.poll_seconds)
    end
    foreach(wait, tasks)
    return nothing
end

function _usage()
    println("""
    wellformed [config.toml]          watch the folders in the config (default: ./wellformed.toml)
    wellformed --check FILE [FILE...] check files once, print results, exit 1 if any FAIL
    wellformed --test-alert [config.toml]  send a fake failure through the configured alerts
    """)
end

function main(args::Vector{String}=ARGS)
    if !isempty(args) && args[1] in ("-h", "--help")
        _usage(); return 0
    end
    if !isempty(args) && args[1] == "--check"
        files = args[2:end]
        isempty(files) && (_usage(); return 2)
        worst = OK
        for f in files
            r = check_file(f)
            println(rpad(string(r.status), 5), f, isempty(r.summary) ? "" : "  ($(r.summary))")
            foreach(i -> println("      [", i.severity, "] ", i.message), r.issues)
            worst = max(worst, r.status)
        end
        return worst == FAIL ? 1 : 0
    end
    if !isempty(args) && args[1] == "--test-alert"
        cfgpath = length(args) >= 2 ? args[2] : "wellformed.toml"
        cfg = isfile(cfgpath) ? load_config(cfgpath) : Config()
        r = CheckResult("TEST_ALERT.xlsx", FAIL,
                        [Issue(FAIL, "this is a test of the Wellformed alert path; no real file is affected")], "", 0.0)
        ns = default_notifiers(cfg)
        println("sending test alert via: ", isempty(ns) ? "(no notifiers enabled)" : join(nameof.(typeof.(ns)), ", "))
        foreach(wait, handle_result(cfg, r, ns))
        println("done; check the log for any notifier errors: ", cfg.log_path)
        return 0
    end
    cfgpath = isempty(args) ? "wellformed.toml" : args[1]
    if !isfile(cfgpath)
        println(stderr, "config file not found: $cfgpath"); return 2
    end
    cfg = load_config(cfgpath)
    if isempty(cfg.watch_dirs)
        println(stderr, "config has no watch_dirs"); return 2
    end
    try
        run_watcher(cfg)
    catch e
        e isa InterruptException || rethrow()
    end
    return 0
end

# Entry point for PackageCompiler.create_app.
Base.@ccallable function julia_main()::Cint
    try
        return Cint(main(String.(ARGS)))
    catch e
        Base.invokelatest(showerror, stderr, e, catch_backtrace())
        return Cint(1)
    end
end
