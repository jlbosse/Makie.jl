# PGFMakie

A [Makie](https://github.com/MakieOrg/Makie.jl) backend that writes figures as
[PGF](https://ctan.org/pkg/pgf) code, similar to matplotlib's `pgf` backend.
All text (tick labels, axis labels, titles, `LaTeXString`s, ...) is emitted as
real LaTeX, so it is typeset with the fonts of your document.

```julia
using PGFMakie, LaTeXStrings

f = Figure(size = (400, 300))
ax = Axis(f[1, 1], xlabel = L"x", ylabel = L"\sin(x)")
lines!(ax, 0..10, sin)
save("figure.pgf", f)
```

In your LaTeX document:

```latex
\usepackage{pgf}
...
\begin{figure}
  \centering
  \input{figure.pgf}
\end{figure}
```

## Output formats

| Extension | Output |
|-----------|--------|
| `.pgf`    | a `pgfpicture`, to be `\input` into a LaTeX document |
| `.tex`    | a standalone LaTeX document containing the picture |
| `.pdf`    | the standalone document, compiled with LaTeX |
| `.png`    | the compiled PDF, rasterized with `pdftocairo` |

PDF and PNG output (and inline display, e.g. in notebooks) need a LaTeX
installation; `lualatex` is used by default.

## Raster content

Images and heatmaps are written as PNG files next to the `.pgf` file
(`figure-img1.png`, ...) and included via `\pgfimage`. They are referenced
relative to the document, so if the figure lives in a different directory than
your main `.tex` file, use the `import` package:

```latex
\usepackage{import}
...
\import{figures/}{figure.pgf}
```

Plots which can't be expressed as PGF (3D meshes and surfaces, volumes, hatch
patterns, per-vertex colored meshes, ...) are rasterized with CairoMakie. You can
also rasterize any plot explicitly with `rasterize = true` (or an integer scale
factor), which is useful for plots with very many elements, since TeX is slow
and has limited memory.

## Configuration

```julia
PGFMakie.activate!(
    pt_per_unit = 0.75,       # size of a Makie unit in bp (matches CairoMakie PDFs)
    px_per_unit = 2.0,        # resolution of rasterized content and PNG output
    tex_engine = "lualatex",  # engine for PDF/PNG output
    preamble = automatic,     # extra preamble for .tex/.pdf/.png output; automatic loads
                              # unicode-math with lualatex/xelatex
    set_fontsize = true,      # use Makie's font sizes; false = inherit document font size
    bold_weight = automatic,  # font weight from which text is bold (e.g. 500 = Medium);
                              # automatic: anything heavier than the figure's most common weight
    raster_fallback = true,   # rasterize unsupported plots with CairoMakie
)
```

Makie lays out figures (e.g. the space reserved for tick labels) using its own
fonts, so text typeset by LaTeX can be slightly wider or narrower than Makie
expected. Each line of text is anchored at the aligned point of Makie's layout,
so alignment is preserved.

Common Unicode math characters in strings (Greek letters, `≤`, `±`, `²`, `ₚ`, ...)
are translated to LaTeX commands, so they work in any document. Rich text
(e.g. `rich("10", superscript("3"))`, as used for log-scale tick labels) is
translated to LaTeX as well.

Text is typeset in your document's font, which usually only has a regular
and a bold weight. Makie's font weights are mapped to these relative to the
figure: text heavier than the most common weight becomes bold. For example,
with AlgebraOfGraphics' theme (Light tick labels, Medium titles) the titles are
bold. Set `bold_weight` to use a fixed threshold instead.

When using a preamble which changes fonts (e.g. `\usepackage{lmodern}` or
`fontspec`), pass the same preamble to your document.
