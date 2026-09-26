using PGFMakie
using PGFMakie: fmt, escape_latex, to_latex
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
    text!(ax, 0.1, 0.2, text = "α ≤ β², Größe 30°")
    text!(ax, 0.6, 0.2, text = L"\int_0^∞ e^{-αx²} \mathrm{d}x ≈ π")
    lines!(ax, rand(10), rand(10), color = 1:10, linewidth = 3)
    push!(figs, "misc" => f)

    f = Figure()
    ax = Axis(f[1, 1], yscale = log10, title = rich("rich ", superscript("text", color = :red), subscript("sub")))
    lines!(ax, 1:10, 10 .^ (1:10))
    push!(figs, "logscale" => f)

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

    @testset "unicode" begin
        @test escape_latex("α = 5 µm") == "\\ensuremath{\\alpha} = 5 \\ensuremath{\\mu}m"
        # runs of super/subscripts are combined into one script
        @test escape_latex("m²³") == "m\\ensuremath{^{2 3 }}"
        @test escape_latex("x₁") == "x\\ensuremath{_{1 }}"
        @test escape_latex("30°") == "30\\ensuremath{^{\\circ }}"
        # symbols without a LaTeX command are typeset in math mode (math fonts cover them)
        @test escape_latex("◇") == "\\ensuremath{◇}"
        # other unicode is passed through
        @test escape_latex("Größe") == "Größe"
        # LaTeX strings aren't escaped, but unicode is still converted
        @test to_latex("\$\\sin(θ)^2\$"; escape = false) == "\$\\sin(\\ensuremath{\\theta})^2\$"
        @test to_latex("tᵖ⁺¹"; escape = false) == "t\\ensuremath{^{p + 1 }}"
        # newlines are spaces (like in MathTeXEngine), `\\` breaks lines if Makie broke them
        src = L"""
        $a$ and \\
        $b$
        """
        @test PGFMakie.latex_source(src, 0.0) == PGFMakie.MATH_STYLE * "\$a\$ and \\\\ \$b\$"
        @test PGFMakie.latex_source(src, 0.0, true) == "\\begin{tabular}{@{}l@{}}" * PGFMakie.MATH_STYLE * "\$a\$ and \\\\ \$b\$\\end{tabular}"
        @test PGFMakie.latex_source(src, 0.5, true) == "\\begin{tabular}{@{}c@{}}" * PGFMakie.MATH_STYLE * "\$a\$ and \\\\ \$b\$\\end{tabular}"
        config = PGFMakie.ScreenConfig(2.0, 0.75, "lualatex", Makie.automatic, true, Makie.automatic, true, true, false)
        @test PGFMakie.resolved_preamble(config) == "\\usepackage{unicode-math}"
        config = PGFMakie.ScreenConfig(2.0, 0.75, "pdflatex", Makie.automatic, true, Makie.automatic, true, true, false)
        @test PGFMakie.resolved_preamble(config) == ""
    end

    @testset "font styles" begin
        @test PGFMakie.font_weight("Light") == 300
        @test PGFMakie.font_weight("Medium") == 500
        @test PGFMakie.font_weight("SemiBold Italic") == 600
        @test PGFMakie.font_weight("Extra-Light") == 200
        @test PGFMakie.font_weight(:bold_italic) == 700
        @test PGFMakie.font_weight(Makie.to_font("TeX Gyre Heros Makie Bold")) == 700
        # bold is relative to a threshold
        @test PGFMakie.font_style_commands("Medium", 401) == "\\bfseries"
        @test PGFMakie.font_style_commands("Medium", 501) == ""
        @test PGFMakie.font_style_commands("SemiBold Italic", 600) == "\\bfseries\\itshape"
        @test PGFMakie.font_style_commands(:regular, 401; reset = true) == "\\mdseries\\upshape"

        # the base weight is the most common one, ties go to the lighter weight
        @test PGFMakie.most_common_weight([300, 300, 300, 500]) == 300 # AoG: Light ticks, Medium titles
        @test PGFMakie.most_common_weight([500, 500, 900]) == 500 # Medium text, Heavy titles
        @test PGFMakie.most_common_weight([400, 700]) == 400
        @test PGFMakie.most_common_weight(Int[]) == 400

        # in a figure, the title is bold but the tick labels aren't, unless the threshold is set explicitly
        mktempdir() do dir
            function bold_lines(; kw...)
                f = Figure()
                Axis(f[1, 1], title = "The title")
                path = joinpath(dir, "fonts.pgf")
                save(path, f; kw...)
                lines = split(read(path, String), '\n')
                title = only(l for l in lines if occursin("The title", l))
                ticks = first(l for l in lines if occursin(r"\\selectfont\S* [0-9]", l))
                return occursin("bfseries", title), occursin("bfseries", ticks)
            end
            @test bold_lines() == (true, false)
            @test bold_lines(bold_weight = 300) == (true, true)
            @test bold_lines(bold_weight = 800) == (false, false)
            # a bold title is bold even if it's the only text in the figure
            f = Figure()
            ax = Axis(f[1, 1], title = "The title")
            hidedecorations!(ax)
            path = joinpath(dir, "title_only.pgf")
            save(path, f)
            @test occursin("bfseries", only(l for l in split(read(path, String), '\n') if occursin("The title", l)))
        end
    end

    @testset "rich text" begin
        r2l(x) = PGFMakie.rich_to_latex(x, 14.0)
        # log scale tick labels
        @test r2l(rich("10", superscript("3"))) == "{10\\textsuperscript{3}}"
        @test r2l(rich("x", subscript("i"))) == "{x\\textsubscript{i}}"
        @test r2l(rich("a", subsup("1", "2"))) == "{a{\\pgfmakiesubsup{1}{2}}}"
        @test r2l(rich("1_%", color = :red)) == "{\\color[rgb]{1,0,0}1\\_\\%}"
        @test r2l(rich("b", font = :bold)) == "{\\bfseries\\upshape b}"
        @test r2l(rich("big", fontsize = 28)) == "{\\pgfmakiefontscale{2}big}"
        @test r2l(rich("10", superscript("−3"))) == "{10\\textsuperscript{\\ensuremath{-}3}}"
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

    @testset "sidecar image names" begin
        # spaces and special characters in the file name must not end up in \pgfimage
        mktempdir() do dir
            path = joinpath(dir, "my figure (v2).pgf")
            save(path, heatmap(rand(3, 3)))
            src = read(path, String)
            m = match(r"\\pgfimage\[[^\]]*\]\{([^}]*)\}", src)
            @test m.captures[1] == "my_figure__v2_-img1.png"
            @test isfile(joinpath(dir, m.captures[1]))
            if HAS_LATEX
                pdf = joinpath(dir, "my figure (v2).pdf")
                save(pdf, heatmap(rand(3, 3)))
                @test isfile(pdf)
            end
        end
    end

    @testset "inline display" begin
        fig = Figure(size = (300, 200))
        lines(fig[1, 1], 1:3)
        # notebooks (e.g. VS Code) prefer html, which shows the png at the logical figure size
        @test showable(MIME"text/html"(), fig)
        @test showable(MIME"image/png"(), fig)
        @test !showable(MIME"application/pdf"(), fig)
        if HAS_LATEX
            io = IOBuffer()
            show(io, MIME"text/html"(), fig)
            html = String(take!(io))
            @test startswith(html, "<img width=300 height=200")
            @test occursin("data:image/png;base64", html)
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
