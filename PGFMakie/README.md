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
    preamble = "",            # extra preamble for .tex/.pdf/.png output
    set_fontsize = true,      # use Makie's font sizes; false = inherit document font size
    raster_fallback = true,   # rasterize unsupported plots with CairoMakie
)
```

Makie lays out figures (e.g. the space reserved for tick labels) using its own
fonts, so text typeset by LaTeX can be slightly wider or narrower than Makie
expected. Each line of text is anchored at the aligned point of Makie's layout,
so alignment is preserved.

When using a preamble which changes fonts (e.g. `\usepackage{lmodern}` or
`fontspec`), pass the same preamble to your document.
