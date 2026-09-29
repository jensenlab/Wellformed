_oneline(s) = replace(String(s), r"\s+" => " ")

"Append one line per check: time, machine, status, file, seconds, summary/issues."
function log_result(cfg::Config, r::CheckResult)
    detail = isempty(r.issues) ? r.summary : join(("[$(i.severity)] $(i.message)" for i in r.issues), " | ")
    line = join((Dates.format(now(), "yyyy-mm-dd HH:MM:SS"), cfg.machine_name, string(r.status),
                 r.path, string(round(r.seconds; digits=2)), _oneline(detail)), '\t')
    try
        mkpath(dirname(abspath(cfg.log_path)))
        open(io -> println(io, line), cfg.log_path, "a")
    catch e
        @warn "could not write log" exception = e
    end
    return nothing
end

log_message(cfg::Config, msg) = log_result(cfg, CheckResult("", WARN, [Issue(WARN, msg)], "", 0.0))
