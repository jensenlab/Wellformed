# Exercised during the app build so the first real check is fast.
using Wellformed
fx = joinpath(@__DIR__, "fixtures")
isdir(fx) && for f in readdir(fx; join=true)
    isfile(f) && check_file(f)
end
Wellformed.main(["--help"])
