using PGFMakie
using PGFMakie: fmt, escape_latex
using LaTeXStrings
using Test

const HAS_LATEX = Sys.which("lualatex") !== nothing

function test_figures()
    figs = Pair{String, Any}[]

    f = Figure()
    ax = Axis(f[1, 1], title = "Lines", xlabel = L"x", ylabel = L"\sin(x)")
    xs = range(0, 2pi, length = 100)
    lines!(ax, xs, sin.(xs), label = "sin")
    lines!(ax, xs, cos.(xs), linestyle = :dash, label = "cos")
    scatter!(ax, xs[1:10:end], sin.(xs[1:10:end]), marker = :utriangle, strokewidth = 1)
    axislegend(ax)
    push!(figs, "lines" => f)

    f = Figure()
    barplot(f[1, 1], 1:5, [3, 1, 4, 1, 5], color = 1:5)
    hist(f[1, 2], randn(1000))
    push!(figs, "bars" => f)

    f = Figure()
    ax, hm = heatmap(f[1, 1], rand(10, 10))
    Colorbar(f[1, 2], hm)
    image(f[2, 1], rand(RGBf, 5, 5))
    band(f[2, 2], 1:10, zeros(10), rand(10) .+ 1)
    push!(figs, "heatmap" => f)

    f = Figure()
    ax = Axis(f[1, 1])
    scatter!(ax, rand(100), rand(100), color = rand(100), marker = :star5)
    text!(ax, 0.5, 0.5, text = "a_b 50% & \$5 #1", align = (:center, :center), rotation = pi / 4)
    text!(ax, 0.1, 0.9, text = "multi\nline")
    lines!(ax, rand(10), rand(10), color = 1:10, linewidth = 3)
    push!(figs, "misc" => f)

    f = Figure()
    surface(f[1, 1], rand(10, 10))
    lines(f[1, 2], rand(10), rasterize = true)
    push!(figs, "fallback" => f)

    push!(figs, "empty" => Figure())
    return figs
end

@testset "PGFMakie.jl" begin
    @testset "number formatting" begin
        @test fmt(1.0) == "1"
        @test fmt(-0.0) == "0"
        @test fmt(1.23456789) == "1.2346"
        @test fmt(1.0e-10) == "0"
        @test fmt(1.0e10) == "16000"
        @test fmt(-Inf) == "-16000"
        @test fmt(NaN) == "0"
        @test !occursin('e', fmt(123456.0))
    end

    @testset "escaping" begin
        @test escape_latex("a_b") == "a\\_b"
        @test escape_latex("50%") == "50\\%"
        @test escape_latex("−1") == "\\ensuremath{-}1"
        @test escape_latex("\\") == "\\textbackslash{}"
    end

    mktempdir() do dir
        for (name, fig) in test_figures()
            @testset "$name" begin
                pgf = joinpath(dir, "$name.pgf")
                save(pgf, fig)
                src = read(pgf, String)
                @test occursin("\\begin{pgfpicture}", src)
                @test !occursin("NaN", src)
                @test !occursin(r"\d[eE][+-]?\d", src)
                # all sidecar images exist
                for m in eachmatch(r"\\pgfimage\[[^\]]*\]\{([^}]*)\}", src)
                    @test isfile(joinpath(dir, m.captures[1]))
                end

                tex = joinpath(dir, "$name.tex")
                save(tex, fig)
                @test occursin("\\documentclass", read(tex, String))

                if HAS_LATEX
                    pdf = joinpath(dir, "$name.pdf")
                    save(pdf, fig)
                    @test startswith(read(pdf, String), "%PDF")
                    png = joinpath(dir, "$name.png")
                    save(png, fig)
                    img = PGFMakie.PNGFiles.load(png)
                    @test size(img) == (900, 1200) # default figure size (600, 450) with px_per_unit = 2
                end
            end
        end
    end

    @testset "stream output" begin
        io = IOBuffer()
        show(io, MIME"application/x-pgf"(), lines(1:10))
        @test occursin("\\pgfpathlineto", String(take!(io)))
        # raster content needs a file
        @test_throws ErrorException show(IOBuffer(), MIME"application/x-pgf"(), heatmap(rand(3, 3)))
    end
end
