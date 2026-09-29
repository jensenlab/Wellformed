# Build a relocatable Wellformed app (bundled Julia runtime; no Julia install needed on the target).
# Run ON WINDOWS for a Windows target (PackageCompiler cannot cross-compile):
#   julia --project=build build/build_app.jl
# then copy dist/wellformed/ and a wellformed.toml to the instrument PC.
using Pkg
Pkg.activate(@__DIR__)
Pkg.add("PackageCompiler")
Pkg.develop(path=joinpath(@__DIR__, ".."))
using PackageCompiler

root = normpath(joinpath(@__DIR__, ".."))
create_app(root, joinpath(root, "dist", "wellformed");
           precompile_execution_file=joinpath(@__DIR__, "precompile.jl"),
           force=true, include_lazy_artifacts=true)
println("Built: ", joinpath(root, "dist", "wellformed", "bin"))
