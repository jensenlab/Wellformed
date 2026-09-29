# Exercised during the app build so the first real check is fast.
using Wellformed
fx = normpath(joinpath(@__DIR__, "..", "test", "fixtures"))
isdir(fx) && for f in readdir(fx; join=true)
    check_file(f)
end
