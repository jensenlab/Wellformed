module Wellformed

using CHESSParsers, DataFrames, Dates, TOML, XLSX

include("config.jl")
include("check.jl")
include("watcher.jl")
include("notify/notify.jl")
include("run.jl")

export Config, load_config, check_file, CheckResult, Issue, Status, OK, WARN, FAIL,
       Watcher, poll!, run_watcher, Notifier, notify, main, julia_main

end # module Wellformed
