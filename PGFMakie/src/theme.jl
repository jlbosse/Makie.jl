"""
    pgf_theme(; fontsize = 10, tickfontsize = 8, linewidth = 0.8, thinwidth = 0.4, markersize = 4,
              textwidth = 469.75, width_fraction = 1.0, aspect = Base.MathConstants.golden,
              pt_per_unit = <PGFMakie theme default>)

Return a `Theme` that sets font sizes, line widths, tick sizes and the figure size
to values that fit into a LaTeX document. All arguments are given in TeX points
(`pt`) and are converted to Makie units with `pt_per_unit`.

* `fontsize`: size of the document's body text, used for labels, titles and legends.
* `tickfontsize`: size of tick labels and legend labels.
* `linewidth`: width of plot lines.
* `thinwidth`: width of spines, ticks, grids and colorbar decorations.
* `markersize`: diameter of scatter markers.
* `textwidth`: width of the text block, e.g. `\\the\\textwidth` of your document.
* `width_fraction`: fraction of `textwidth` the figure should span.
* `aspect`: width / height of the figure, the golden ratio by default.

The theme only contains geometry. Fonts, colors, palettes and styling are left to
other themes, so it combines with e.g. `AlgebraOfGraphics.set_aog_theme!()` via
[`set_pgf_theme!`](@ref).
"""
function pgf_theme(;
        fontsize = 10, tickfontsize = 8, linewidth = 0.8, thinwidth = 0.4, markersize = 4,
        textwidth = 469.75, width_fraction = 1.0, aspect = Base.MathConstants.golden,
        pt_per_unit = Makie.to_value(Makie.theme(:PGFMakie).pt_per_unit)
    )
    u(x) = Float32(x / pt_per_unit)
    width = u(textwidth * width_fraction)

    return Theme(
        size = (width, width / aspect),
        fontsize = u(fontsize),
        linewidth = u(linewidth),
        markersize = u(markersize),
        figure_padding = u(2),
        Axis = (
            titlesize = u(fontsize),
            xlabelsize = u(fontsize),
            ylabelsize = u(fontsize),
            xticklabelsize = u(tickfontsize),
            yticklabelsize = u(tickfontsize),
            spinewidth = u(thinwidth),
            xtickwidth = u(thinwidth),
            ytickwidth = u(thinwidth),
            xminortickwidth = u(thinwidth),
            yminortickwidth = u(thinwidth),
            xgridwidth = u(thinwidth),
            ygridwidth = u(thinwidth),
            xminorgridwidth = u(thinwidth),
            yminorgridwidth = u(thinwidth),
            xticksize = u(3),
            yticksize = u(3),
            xminorticksize = u(1.5),
            yminorticksize = u(1.5),
        ),
        Legend = (
            titlesize = u(fontsize),
            labelsize = u(tickfontsize),
            framewidth = u(thinwidth),
        ),
        Colorbar = (
            labelsize = u(fontsize),
            ticklabelsize = u(tickfontsize),
            spinewidth = u(thinwidth),
            tickwidth = u(thinwidth),
            minortickwidth = u(thinwidth),
            ticksize = u(3),
            minorticksize = u(1.5),
        ),
    )
end

"""
    set_pgf_theme!(; kwargs...)

Update the current theme with LaTeX compatible font sizes, line widths and figure
size, see [`pgf_theme`](@ref) for the keyword arguments.

This uses `Makie.update_theme!`, so only these keys change and everything else in
the current theme is kept. To combine it with another theme, call it afterwards:

```julia
using AlgebraOfGraphics
set_aog_theme!()
set_pgf_theme!(fontsize = 11, textwidth = 345)
```

Calling `set_theme!` or `set_aog_theme!` later resets these values again. For a
scoped change use `with_theme(f, pgf_theme(; kwargs...))`.
"""
function set_pgf_theme!(; kwargs...)
    Makie.update_theme!(pgf_theme(; kwargs...))
    return
end
