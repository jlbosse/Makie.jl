################################################################################
#                         LaTeX documents & compilation                        #
################################################################################

"""
    escape_latex(str)

Escape a plain (non-LaTeX) string so that it typesets literally in LaTeX.
"""
function escape_latex(str::AbstractString)
    io = IOBuffer()
    for c in str
        if c == '\\'
            print(io, "\\textbackslash{}")
        elseif c in ('#', '$', '%', '&', '_', '{', '}')
            print(io, '\\', c)
        elseif c == '^'
            print(io, "\\textasciicircum{}")
        elseif c == '~'
            print(io, "\\textasciitilde{}")
        elseif c == '−' # unicode minus, used by Makie's tick formatting
            print(io, "\\ensuremath{-}")
        elseif c == '\n' || c == '\r'
            print(io, ' ')
        else
            print(io, c)
        end
    end
    return String(take!(io))
end

"""
Macros used by the PGF output. They are defined with `\\providecommand` inside
the picture so that the `.pgf` file is self contained.

`\\pgfmakiealign{h}{content}` shifts `content` horizontally by `h` times its width,
so that e.g. `h = 0.5` centers it on the anchor. The baseline stays at the anchor.
`\\pgfmakiealignv{h}{v}{content}` additionally shifts it vertically so that the
anchor is at `v` times the height of its box (including depth), measured from the bottom.
"""
const PGF_MACROS = raw"""
\providecommand{\pgfmakiealign}[2]{\setbox0=\hbox{#2}\dimen0=#1\wd0\hbox{\kern-\dimen0\box0}}%
\providecommand{\pgfmakiealignv}[3]{\setbox0=\hbox{#3}\dimen0=#1\wd0\dimen2=\ht0\advance\dimen2 by \dp0\dimen2=#2\dimen2\advance\dimen2 by -\dp0\hbox{\kern-\dimen0\raise-\dimen2\box0}}%
"""

function header_comment(screen::Screen)
    io = IOBuffer()
    println(io, "%% Created by PGFMakie.jl")
    println(io, "%%")
    println(io, "%% Include this file in a LaTeX document with")
    println(io, "%%   \\usepackage{pgf}")
    println(io, "%%   ...")
    println(io, "%%   \\input{<filename>.pgf}")
    if !isempty(screen.images)
        println(io, "%%")
        println(io, "%% This figure includes raster images, stored in separate files next to it.")
        println(io, "%% They are referenced relative to the directory of the figure, so if the figure")
        println(io, "%% is not in the same directory as your main document, use")
        println(io, "%%   \\usepackage{import}")
        println(io, "%%   \\import{<path to figure>/}{<filename>.pgf}")
        println(io, "%% Images:")
        for (name, _) in screen.images
            println(io, "%%   ", name)
        end
    end
    preamble = screen.config.preamble
    if !isempty(preamble)
        println(io, "%%")
        println(io, "%% The following preamble was used when creating this figure:")
        for line in split(preamble, '\n')
            println(io, "%%   ", line)
        end
    end
    println(io, "%%")
    return String(take!(io))
end

"""
    write_picture(io, screen)

Write the complete `pgfpicture` (without document) for `screen`, whose writer
must already contain the drawing commands.
"""
function write_picture(io::IO, screen::Screen)
    w, h = size(screen.scene) .* screen.config.pt_per_unit
    print(io, header_comment(screen))
    println(io, "\\begingroup%")
    println(io, "\\makeatletter%")
    println(io, "\\begin{pgfpicture}%")
    print(io, PGF_MACROS)
    println(io, "\\pgfpathrectangle{\\pgfpointorigin}{\\pgfqpoint{", fmt(w), "bp}{", fmt(h), "bp}}%")
    println(io, "\\pgfusepath{use as bounding box, clip}%")
    write(io, take!(copy(screen.writer.io)))
    println(io, "\\end{pgfpicture}%")
    println(io, "\\makeatother%")
    println(io, "\\endgroup%")
    return
end

"""
    write_document(io, screen)

Write a standalone LaTeX document containing the picture of `screen`.
"""
function write_document(io::IO, screen::Screen)
    println(io, "\\documentclass[border=0pt]{standalone}")
    println(io, "\\usepackage{pgf}")
    preamble = screen.config.preamble
    isempty(preamble) || println(io, preamble)
    println(io, "\\begin{document}")
    write_picture(io, screen)
    println(io, "\\end{document}")
    return
end

"""
    write_images(screen, dir)

Write the sidecar images of `screen` into `dir`.
"""
function write_images(screen::Screen, dir::AbstractString)
    for (name, img) in screen.images
        PNGFiles.save(joinpath(dir, name), img)
    end
    return
end

struct LaTeXError <: Exception
    engine::String
    log::String
end

function Base.showerror(io::IO, e::LaTeXError)
    println(io, "LaTeXError: compiling the figure with `$(e.engine)` failed. End of the log:")
    lines = split(e.log, '\n')
    return print(io, join(lines[max(1, end - 40):end], '\n'))
end

"""
    compile_pdf(screen)::Vector{UInt8}

Render `screen` into a standalone LaTeX document and compile it to a PDF with
`screen.config.tex_engine`. Returns the bytes of the PDF.
"""
function compile_pdf(screen::Screen)
    engine = screen.config.tex_engine
    exe = Sys.which(engine)
    exe === nothing && error("Could not find the LaTeX engine `$(engine)`. Install a TeX distribution or set `PGFMakie.activate!(tex_engine = ...)`.")
    return mktempdir() do dir
        # sidecar images are referenced relative to the document
        write_images(screen, dir)
        texfile = joinpath(dir, "figure.tex")
        open(io -> write_document(io, screen), texfile, "w")
        cmd = Cmd(`$exe -interaction=nonstopmode -halt-on-error -no-shell-escape figure.tex`; dir = dir)
        out = IOBuffer()
        ok = success(pipeline(ignorestatus(cmd); stdout = out, stderr = out))
        pdffile = joinpath(dir, "figure.pdf")
        if !ok || !isfile(pdffile)
            logfile = joinpath(dir, "figure.log")
            log = isfile(logfile) ? read(logfile, String) : String(take!(out))
            throw(LaTeXError(engine, log))
        end
        return read(pdffile)
    end
end

"""
    pdf_to_png(pdf::Vector{UInt8}, dpi)::Vector{UInt8}

Rasterize the first page of a PDF with `pdftocairo`.
"""
function pdf_to_png(pdf::Vector{UInt8}, dpi::Real)
    return mktempdir() do dir
        pdffile = joinpath(dir, "figure.pdf")
        write(pdffile, pdf)
        stem = joinpath(dir, "figure")
        run(`$(Poppler_jll.pdftocairo()) -png -singlefile -transp -r $(dpi) $pdffile $stem`)
        return read(stem * ".png")
    end
end

"DPI for PNG output, such that the image has `px_per_unit` pixels per Makie unit."
png_dpi(config::ScreenConfig) = 72 * config.px_per_unit / config.pt_per_unit
