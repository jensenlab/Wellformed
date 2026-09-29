# Build a relocatable Wellformed app (bundled Julia runtime; no Julia needed on the target PC).
# PackageCompiler cannot cross-compile: run this ON WINDOWS to get a Windows app.
#
#   julia build/build_app.jl            # from the repo root
#
# The app is built from a staging copy of the project in which the local-checkout CHESSParsers
# entry in Project.toml is replaced by the GitHub one, so it works on a machine that does not
# have ../CHESS. Output: dist/wellformed/bin/Wellformed(.exe)
using Pkg
const ROOT = normpath(joinpath(@__DIR__, ".."))
const STAGE = joinpath(ROOT, "dist", "stage")
const APP = joinpath(ROOT, "dist", "wellformed")

# Build tooling lives in its own environment so it never touches the app's dependencies.
Pkg.activate(joinpath(ROOT, "dist", "buildenv"); io=devnull)
Pkg.add("PackageCompiler")
using PackageCompiler

rm(STAGE; recursive=true, force=true)
mkpath(STAGE)
cp(joinpath(ROOT, "src"), joinpath(STAGE, "src"))
cp(joinpath(ROOT, "test", "fixtures"), joinpath(STAGE, "fixtures"))
cp(joinpath(@__DIR__, "precompile.jl"), joinpath(STAGE, "precompile.jl"))

proj = read(joinpath(ROOT, "Project.toml"), String)
proj, n = let re = r"^CHESSParsers = \{path = [^\n]*\}$"m
    replace(proj, re => "CHESSParsers = {url = \"https://github.com/jensenlab/CHESS.git\", subdir = \"CHESSParsers\", rev = \"main\"}"), count(re, proj)
end
n == 1 || error("expected exactly one CHESSParsers path source in Project.toml, found $n")
write(joinpath(STAGE, "Project.toml"), proj)

println("Resolving dependencies ..."); Pkg.activate(STAGE; io=devnull); Pkg.instantiate()
println("Compiling the app (this takes several minutes) ...")
create_app(STAGE, APP;
           precompile_execution_file=joinpath(STAGE, "precompile.jl"),
           force=true, include_lazy_artifacts=true)
println("\nBuilt: ", joinpath(APP, "bin"))
