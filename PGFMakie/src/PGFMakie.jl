module PGFMakie

using Cairo
using Colors
using DocStringExtensions
using FileIO
using Ghostscript_jll
using LaTeXStrings
using Makie
using Makie: MakieScreen, Plot, Scene
using PermutedArrays
using Poppler_jll

include("texdocument.jl")
include("screen.jl")
include("display.jl")
include("plot_primitives.jl")

end
