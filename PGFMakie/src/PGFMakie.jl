module PGFMakie

using Makie
using LaTeXStrings
using DocStringExtensions
using Cairo
using Colors
using Poppler_jll
using Ghostscript_jll
using PermutedArrays

using Makie: Plot, Scene, MakieScreen

include("texdocument.jl")
include("screen.jl")

end
