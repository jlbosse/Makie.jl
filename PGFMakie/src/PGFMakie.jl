module PGFMakie

using Makie.ComputePipeline
using Makie, LinearAlgebra
using Colors, GeometryBasics, FileIO
using LaTeXStrings: LaTeXString
using Printf: @sprintf
import CairoMakie
import PNGFiles
import Poppler_jll

using Makie: Scene, Lines, Text, Image, Heatmap, Scatter, LineSegments, Plot, MakieScreen
using Makie: to_value, sv_getindex, VecTypes, RGBAf, Linestyle, PlotList
using Makie: BezierPath, MoveTo, LineTo, CurveTo, ClosePath, EllipticalArc

# re-export Makie, including deprecated names
for name in names(Makie, all = true)
    if Base.isexported(Makie, name)
        @eval using Makie: $(name)
        @eval export $(name)
    end
end

include("writer.jl")
include("screen.jl")
include("latex.jl")
include("theme.jl")
include("display.jl")
include("render.jl")
include("lines.jl")
include("scatter.jl")
include("text.jl")
include("image.jl")
include("poly.jl")

export pgf_theme, set_pgf_theme!

function __init__()
    # FileIO doesn't know about .pgf and .tex files
    haskey(FileIO.sym2info, :PGF) || FileIO.add_format(format"PGF", (), ".pgf")
    haskey(FileIO.sym2info, :TEX) || FileIO.add_format(format"TEX", (), ".tex")
    activate!()
    return
end

Makie.format2mime(::Type{FileIO.format"PGF"}) = MIME("application/x-pgf")

end
