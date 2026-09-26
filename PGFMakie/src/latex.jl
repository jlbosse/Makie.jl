################################################################################
#                         LaTeX documents & compilation                        #
################################################################################

################################################################################
#                                   Unicode                                    #
################################################################################

# Unicode characters which are translated to standard LaTeX math commands, so
# that they work with any engine (including pdflatex) and any document
# preamble. Other non-ASCII characters are passed through unchanged, which
# works for characters covered by the document's font (e.g. accented letters).
const UNICODE_MATH_COMMANDS = Dict{Char, String}(
    # Greek lowercase
    'α' => "\\alpha", 'β' => "\\beta", 'γ' => "\\gamma", 'δ' => "\\delta",
    'ε' => "\\varepsilon", 'ϵ' => "\\epsilon", 'ζ' => "\\zeta", 'η' => "\\eta",
    'θ' => "\\theta", 'ϑ' => "\\vartheta", 'ι' => "\\iota", 'κ' => "\\kappa",
    'λ' => "\\lambda", 'μ' => "\\mu", 'µ' => "\\mu", 'ν' => "\\nu", 'ξ' => "\\xi",
    'ο' => "o", 'π' => "\\pi", 'ϖ' => "\\varpi", 'ρ' => "\\rho", 'ϱ' => "\\varrho",
    'σ' => "\\sigma", 'ς' => "\\varsigma", 'τ' => "\\tau", 'υ' => "\\upsilon",
    'φ' => "\\varphi", 'ϕ' => "\\phi", 'χ' => "\\chi", 'ψ' => "\\psi", 'ω' => "\\omega",
    # Greek uppercase (those looking like Latin letters are upright Latin letters)
    'Α' => "\\mathrm{A}", 'Β' => "\\mathrm{B}", 'Γ' => "\\Gamma", 'Δ' => "\\Delta",
    'Ε' => "\\mathrm{E}", 'Ζ' => "\\mathrm{Z}", 'Η' => "\\mathrm{H}", 'Θ' => "\\Theta",
    'Ι' => "\\mathrm{I}", 'Κ' => "\\mathrm{K}", 'Λ' => "\\Lambda", 'Μ' => "\\mathrm{M}",
    'Ν' => "\\mathrm{N}", 'Ξ' => "\\Xi", 'Ο' => "\\mathrm{O}", 'Π' => "\\Pi",
    'Ρ' => "\\mathrm{P}", 'Σ' => "\\Sigma", 'Τ' => "\\mathrm{T}", 'Υ' => "\\Upsilon",
    'Φ' => "\\Phi", 'Χ' => "\\mathrm{X}", 'Ψ' => "\\Psi", 'Ω' => "\\Omega",
    # operators and relations
    '−' => "-", '±' => "\\pm", '∓' => "\\mp", '×' => "\\times", '÷' => "\\div",
    '·' => "\\cdot", '⋅' => "\\cdot", '∘' => "\\circ", '∗' => "\\ast", '∞' => "\\infty",
    '≤' => "\\leq", '≥' => "\\geq", '≠' => "\\neq", '≈' => "\\approx", '≡' => "\\equiv",
    '∼' => "\\sim", '≃' => "\\simeq", '≅' => "\\cong", '∝' => "\\propto",
    '≪' => "\\ll", '≫' => "\\gg", '⊥' => "\\perp", '∥' => "\\parallel",
    '→' => "\\to", '←' => "\\leftarrow", '↔' => "\\leftrightarrow", '↦' => "\\mapsto",
    '⇒' => "\\Rightarrow", '⇐' => "\\Leftarrow", '⇔' => "\\Leftrightarrow",
    '↑' => "\\uparrow", '↓' => "\\downarrow",
    '∈' => "\\in", '∉' => "\\notin", '∋' => "\\ni", '⊂' => "\\subset", '⊃' => "\\supset",
    '⊆' => "\\subseteq", '⊇' => "\\supseteq", '∪' => "\\cup", '∩' => "\\cap",
    '∅' => "\\emptyset", '∀' => "\\forall", '∃' => "\\exists", '¬' => "\\neg",
    '∧' => "\\wedge", '∨' => "\\vee", '⊕' => "\\oplus", '⊗' => "\\otimes",
    '∑' => "\\sum", '∏' => "\\prod", '∫' => "\\int", '∮' => "\\oint", '∂' => "\\partial",
    '∇' => "\\nabla", '√' => "\\surd", '⟨' => "\\langle", '⟩' => "\\rangle",
    'ℏ' => "\\hbar", 'ℓ' => "\\ell", '†' => "\\dagger", '‡' => "\\ddagger",
    '…' => "\\ldots", '⋯' => "\\cdots", '‖' => "\\Vert", '∣' => "\\mid",
)

const UNICODE_SUPERSCRIPTS = Dict{Char, String}(
    '⁰' => "0", '¹' => "1", '²' => "2", '³' => "3", '⁴' => "4", '⁵' => "5", '⁶' => "6",
    '⁷' => "7", '⁸' => "8", '⁹' => "9", '⁺' => "+", '⁻' => "-", '⁼' => "=", '⁽' => "(",
    '⁾' => ")", 'ⁿ' => "n", 'ⁱ' => "i",
    'ᵃ' => "a", 'ᵇ' => "b", 'ᶜ' => "c", 'ᵈ' => "d", 'ᵉ' => "e", 'ᶠ' => "f", 'ᵍ' => "g",
    'ʰ' => "h", 'ʲ' => "j", 'ᵏ' => "k", 'ˡ' => "l", 'ᵐ' => "m", 'ᵒ' => "o", 'ᵖ' => "p",
    'ʳ' => "r", 'ˢ' => "s", 'ᵗ' => "t", 'ᵘ' => "u", 'ᵛ' => "v", 'ʷ' => "w", 'ˣ' => "x",
    'ʸ' => "y", 'ᶻ' => "z", 'ᴬ' => "A", 'ᴮ' => "B", 'ᴰ' => "D", 'ᴱ' => "E", 'ᴳ' => "G",
    'ᴴ' => "H", 'ᴵ' => "I", 'ᴶ' => "J", 'ᴷ' => "K", 'ᴸ' => "L", 'ᴹ' => "M", 'ᴺ' => "N",
    'ᴼ' => "O", 'ᴾ' => "P", 'ᴿ' => "R", 'ᵀ' => "T", 'ᵁ' => "U", 'ⱽ' => "V", 'ᵂ' => "W",
    'ᵅ' => "\\alpha", 'ᵝ' => "\\beta", 'ᵞ' => "\\gamma", 'ᵟ' => "\\delta", 'ᶿ' => "\\theta", '°' => "\\circ", '′' => "\\prime", '″' => "\\prime\\prime",
)

const UNICODE_SUBSCRIPTS = Dict{Char, String}(
    '₀' => "0", '₁' => "1", '₂' => "2", '₃' => "3", '₄' => "4", '₅' => "5", '₆' => "6",
    '₇' => "7", '₈' => "8", '₉' => "9", '₊' => "+", '₋' => "-", '₌' => "=", '₍' => "(",
    '₎' => ")", 'ₐ' => "a", 'ₑ' => "e", 'ₒ' => "o", 'ₓ' => "x", 'ᵢ' => "i", 'ⱼ' => "j",
    'ₖ' => "k", 'ₗ' => "l", 'ₘ' => "m", 'ₙ' => "n", 'ₚ' => "p", 'ₛ' => "s", 'ₜ' => "t",
    'ₕ' => "h", 'ᵣ' => "r", 'ᵤ' => "u", 'ᵥ' => "v", 'ᵦ' => "\\beta", 'ᵧ' => "\\gamma",
    'ᵨ' => "\\rho", 'ᵩ' => "\\phi", 'ᵪ' => "\\chi",
)

"""
    is_math_symbol(c)

Whether `c` is in one of the Unicode blocks of mathematical symbols (arrows,
operators, geometric shapes, ...), which text fonts usually don't cover.
"""
function is_math_symbol(c::Char)
    u = UInt32(c)
    return 0x2100 <= u <= 0x214F || # letterlike symbols
        0x2190 <= u <= 0x23FF ||    # arrows, mathematical operators, miscellaneous technical
        0x25A0 <= u <= 0x27FF ||    # geometric shapes, miscellaneous symbols, dingbats, math symbols, arrows
        0x2900 <= u <= 0x2BFF ||    # supplemental arrows and operators, miscellaneous symbols and arrows
        0x0001D400 <= u <= 0x0001D7FF     # mathematical alphanumeric symbols
end

"""
    to_latex(str; escape = true)

Convert `str` to LaTeX source. With `escape = true`, LaTeX special characters are
escaped so that `str` typesets literally (for plain strings). Unicode math
characters (Greek letters, operators, super- and subscripts, ...) are replaced
by standard LaTeX commands wrapped in `\\ensuremath`, so they work in text and
math mode with any TeX engine.
"""
function to_latex(str::AbstractString; escape::Bool = true)
    io = IOBuffer()
    chars = collect(str)
    i = 1
    while i <= length(chars)
        c = chars[i]
        if escape && c == '\\'
            print(io, "\\textbackslash{}")
        elseif escape && c in ('#', '$', '%', '&', '_', '{', '}')
            print(io, '\\', c)
        elseif escape && c == '^'
            print(io, "\\textasciicircum{}")
        elseif escape && c == '~'
            print(io, "\\textasciitilde{}")
        elseif escape && (c == '\n' || c == '\r')
            print(io, ' ')
        elseif haskey(UNICODE_SUPERSCRIPTS, c) || haskey(UNICODE_SUBSCRIPTS, c)
            # combine runs like `²³` into one script, `x^{2}^{3}` is an error
            table, op = haskey(UNICODE_SUPERSCRIPTS, c) ? (UNICODE_SUPERSCRIPTS, '^') : (UNICODE_SUBSCRIPTS, '_')
            print(io, "\\ensuremath{", op, "{")
            while i <= length(chars) && haskey(table, chars[i])
                print(io, table[chars[i]], ' ')
                i += 1
            end
            print(io, "}}")
            continue
        elseif haskey(UNICODE_MATH_COMMANDS, c)
            print(io, "\\ensuremath{", UNICODE_MATH_COMMANDS[c], "}")
        elseif is_math_symbol(c)
            # other symbols are usually missing from text fonts, but covered by
            # math fonts (e.g. with unicode-math)
            print(io, "\\ensuremath{", c, "}")
        else
            print(io, c)
        end
        i += 1
    end
    return String(take!(io))
end

"""
    escape_latex(str)

Escape a plain (non-LaTeX) string so that it typesets literally in LaTeX.
"""
escape_latex(str::AbstractString) = to_latex(str; escape = true)

"""
Macros used by the PGF output. They are defined with `\\providecommand` inside
the picture so that the `.pgf` file is self contained.

`\\pgfmakiealign{h}{content}` shifts `content` horizontally by `h` times its width,
so that e.g. `h = 0.5` centers it on the anchor. The baseline stays at the anchor.
`\\pgfmakiealignv{h}{v}{content}` additionally shifts it vertically so that the
anchor is at `v` times the height of its box (including depth), measured from the bottom.
`\\pgfmakiesubsup{sub}{sup}` / `\\pgfmakieleftsubsup{sub}{sup}` stack a subscript and a
superscript (left/right aligned), and `\\pgfmakiefontscale{f}` scales the current font size by `f`.
"""
const PGF_MACROS = raw"""
\providecommand{\pgfmakiealign}[2]{\setbox0=\hbox{#2}\dimen0=#1\wd0\hbox{\kern-\dimen0\box0}}%
\providecommand{\pgfmakiealignv}[3]{\setbox0=\hbox{#3}\dimen0=#1\wd0\dimen2=\ht0\advance\dimen2 by \dp0\dimen2=#2\dimen2\advance\dimen2 by -\dp0\hbox{\kern-\dimen0\raise-\dimen2\box0}}%
\providecommand{\pgfmakiesubsup}[2]{\setbox0=\hbox{\textsubscript{#1}}\setbox2=\hbox{\textsuperscript{#2}}\ifdim\wd0>\wd2\dimen0=\wd0\else\dimen0=\wd2\fi\rlap{\box0}\rlap{\box2}\kern\dimen0}%
\providecommand{\pgfmakieleftsubsup}[2]{\setbox0=\hbox{\textsubscript{#1}}\setbox2=\hbox{\textsuperscript{#2}}\ifdim\wd0>\wd2\dimen0=\wd0\else\dimen0=\wd2\fi\kern\dimen0\llap{\box0}\llap{\box2}}%
\providecommand{\pgfmakiefontscale}[1]{\dimen0=\f@size pt\dimen0=#1\dimen0\fontsize{\strip@pt\dimen0}{\strip@pt\dimen0}\selectfont}%
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
    preamble = resolved_preamble(screen.config)
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
    preamble = resolved_preamble(screen.config)
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

"""
    supports_unicode(engine)

Whether the TeX engine supports OpenType fonts and `unicode-math` (LuaTeX, XeTeX).
"""
function supports_unicode(engine::AbstractString)
    name = lowercase(basename(engine))
    return occursin("lua", name) || occursin("xe", name)
end

"""
    resolved_preamble(config)

The preamble used for `.tex`, `.pdf` and `.png` output. With the default
`preamble = automatic`, `unicode-math` is loaded for engines which support it
(LuaLaTeX, XeLaTeX), so that Unicode math characters work in LaTeXStrings.
"""
function resolved_preamble(config::ScreenConfig)
    config.preamble isa AbstractString && return config.preamble
    return supports_unicode(config.tex_engine) ? "\\usepackage{unicode-math}" : ""
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
