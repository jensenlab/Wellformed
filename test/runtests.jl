using Test, Wellformed

const FIXTURES = joinpath(dirname(dirname(pathof(Wellformed))), "..", "CHESS", "CHESSParsers", "test", "fixtures") |> normpath
const GOOD = filter(f -> endswith(f, ".xlsx") || endswith(f, ".SES"), readdir(FIXTURES; join=true))

function truncated(src, frac; dir=mktempdir())
    dst = joinpath(dir, "trunc_" * basename(src))
    bytes = read(src)
    write(dst, bytes[1:max(1, floor(Int, length(bytes) * frac))])
    return dst
end

@testset "good fixtures pass" begin
    for f in GOOD
        r = check_file(f)
        @test r.status != FAIL
        r.status == FAIL && @info basename(f) r.issues
    end
end

@testset "truncated files fail" begin
    for f in filter(endswith(".xlsx"), GOOD), frac in (0.5, 0.9)
        r = check_file(truncated(f, frac))
        @test r.status == FAIL
    end
    empty = joinpath(mktempdir(), "empty.xlsx"); touch(empty)
    @test check_file(empty).status == FAIL
    @test check_file(joinpath(mktempdir(), "nope.xlsx")).status == FAIL
end

@testset "unrecognized file" begin
    p = joinpath(mktempdir(), "notes.csv"); write(p, "a,b\n1,2\n")
    @test check_file(p).status == FAIL
    @test check_file(p; unrecognized_is_failure=false).status == Wellformed.WARN
end

@testset "watcher waits for files to settle" begin
    dir = mktempdir()
    w = Watcher(Config(watch_dirs=[dir], settle_seconds=5.0))
    p = joinpath(dir, "run.xlsx")
    write(p, "abc")
    @test poll!(w, 100.0) == String[]          # first sight
    write(p, "abcdef")                         # still growing
    @test poll!(w, 104.0) == String[]
    @test poll!(w, 107.0) == String[]          # only 3s since last change
    @test poll!(w, 110.0) == [p]               # settled
    @test poll!(w, 120.0) == String[]          # not reported twice
    write(p, "abcdefghi")                      # rewritten
    @test poll!(w, 130.0) == String[]
    @test poll!(w, 136.0) == [p]
    write(joinpath(dir, "~\$lock.xlsx"), "x"); write(joinpath(dir, "a.tmp"), "x")
    @test poll!(w, 200.0) == String[] && poll!(w, 210.0) == String[]
end

struct Recorder <: Notifier
    got::Vector{Wellformed.CheckResult}
end
Wellformed.notify(r::Recorder, res, cfg) = push!(r.got, res)

@testset "end to end: only bad files alert" begin
    dir = mktempdir(); log = joinpath(mktempdir(), "wf.log")
    cfg = Config(watch_dirs=[dir], settle_seconds=0.0, poll_seconds=0.05, log_path=log)
    rec = Recorder([])
    good = first(filter(endswith(".xlsx"), GOOD))
    stop = Ref(false)
    t = @async run_watcher(cfg; notifiers=[rec], stop=stop)
    sleep(0.3)
    cp(good, joinpath(dir, "good.xlsx"))
    cp(truncated(good, 0.6), joinpath(dir, "bad.xlsx"))
    sleep(4); stop[] = true; wait(t)
    @test length(rec.got) == 1 && basename(rec.got[1].path) == "bad.xlsx"
    logtxt = read(log, String)
    @test occursin("OK", logtxt) && occursin("FAIL", logtxt)
end

@testset "real truncated export (header written, no plate data)" begin
    p = joinpath(@__DIR__, "fixtures", "real_truncated", "3094e6a_260924_144511_.xlsx")
    r = check_file(p)
    @test r.status == FAIL
    @test occursin("no data table", r.issues[1].message)
    @test occursin("Actual Temperature", r.issues[1].message)
end

@testset "real good exports still pass" begin
    for f in readdir(joinpath(@__DIR__, "fixtures"); join=true)
        endswith(f, ".xlsx") && @test check_file(f).status == OK
    end
end

@testset "config save/load round trip" begin
    d = mktempdir(); p = joinpath(d, "sub", "config.toml")
    cfg = Config(watch_dirs=[d], basecamp_enabled=true, basecamp_url="https://example.com/x",
                 log_path=joinpath(d, "w.log"), settle_seconds=7.0, machine_name="PC1")
    save_config(cfg, p)
    back = load_config(p)
    @test back.watch_dirs == [d] && back.basecamp_enabled && back.basecamp_url == "https://example.com/x"
    @test back.settle_seconds == 7.0 && back.machine_name == "PC1"
    Sys.iswindows() || @test (filemode(p) & 0o077) == 0      # holds a credential
    # relative log_path resolves next to the config file, not the cwd
    write(p, "watch_dirs = ['$d']\nlog_path = 'x.log'\n")
    @test load_config(p).log_path == joinpath(dirname(abspath(p)), "x.log")
end

const BC_URL = "https://3.basecamp.com/1234567/integrations/AbCdEf123/buckets/111/chats/222/line"

scripted(; folder, texts, yes=false) = begin
    said = String[]; asked = String[]; q = collect(texts)
    ui = Wellformed.UI(folder=(p, d) -> folder, text=(p, d) -> (push!(asked, p); isempty(q) ? nothing : popfirst!(q)),
                       yesno=p -> yes, say=m -> push!(said, m))
    ui, said, asked
end

@testset "setup flow" begin
    d = mktempdir(); watch = mkdir(joinpath(d, "exports")); p = joinpath(d, "cfg", "config.toml")
    ui, said, _ = scripted(folder=watch, texts=[BC_URL])
    cfg = run_setup(p; ui=ui, test_alert=false, offer_startup=false)
    @test cfg.watch_dirs == [watch] && cfg.basecamp_enabled
    @test load_config(p).basecamp_url == BC_URL
    @test load_config(p).log_path == joinpath(d, "cfg", "wellformed.log")

    # invalid URL is re-asked; then accepted blank => popup only
    ui, said, asked = scripted(folder=watch, texts=["not a url", ""])
    cfg = run_setup(joinpath(d, "b.toml"); ui=ui, test_alert=false, offer_startup=false)
    @test length(asked) == 2 && !cfg.basecamp_enabled

    # cancelled or bad folder saves nothing
    ui, said, _ = scripted(folder=nothing, texts=[])
    @test run_setup(joinpath(d, "c.toml"); ui=ui, test_alert=false) === nothing && !isfile(joinpath(d, "c.toml"))
    ui, said, _ = scripted(folder=joinpath(d, "nope"), texts=[])
    @test run_setup(joinpath(d, "d.toml"); ui=ui, test_alert=false) === nothing

    # re-running keeps existing values as defaults and can change the folder
    other = mkdir(joinpath(d, "other"))
    ui, _, _ = scripted(folder=other, texts=[BC_URL])
    @test run_setup(p; ui=ui, test_alert=false, offer_startup=false).watch_dirs == [other]
end

@testset "basecamp errors never leak the URL" begin
    secret = "SECRETKEY123"
    n = Wellformed.BasecampNotifier("https://127.0.0.1:9/4/integrations/$secret/buckets/1/chats/2/line")
    r = Wellformed.CheckResult("x.xlsx", FAIL, [Wellformed.Issue(FAIL, "bad")], "", 0.0)
    err = try Wellformed.notify(n, r, Config()); nothing catch e; sprint(showerror, e) end
    @test err !== nothing && !occursin(secret, err)
    @test Wellformed._lines_url(BC_URL) == BC_URL * "s"
    @test Wellformed._lines_url(BC_URL * "s/") == BC_URL * "s"
end

@testset "login startup (macOS LaunchAgent)" begin
    if Sys.isapple()
        d = mktempdir()
        path = install_startup(exe="/Applications/Wellformed & Co/wellformed", plist_dir=d)
        txt = read(path, String)
        @test occursin("RunAtLoad", txt) && occursin("Wellformed &amp; Co", txt)
        @test success(`plutil -lint $path`)
        @test uninstall_startup(plist_dir=d) && !isfile(path) && !uninstall_startup(plist_dir=d)
    end
    @test_throws ErrorException Wellformed._app_exe()      # running under julia, not a built app
end
