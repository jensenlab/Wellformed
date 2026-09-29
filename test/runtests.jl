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
