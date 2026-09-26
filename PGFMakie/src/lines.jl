################################################################################
#                            Lines and LineSegments                            #
################################################################################

function draw_atomic(::Scene, screen::Screen, plot::PT) where {PT <: Union{Lines, LineSegments}}
    attr = plot.attributes
    add_constant!(attr, :is_lines_plot, plot isa Lines)
    if plot isa LineSegments
        add_constant!(attr, :joinstyle, nothing)
        add_constant!(attr, :miter_limit, nothing)
    end
    Makie.compute_colors!(attr)
    # Projects to clip space, clips lines against clip planes and the viewport
    # and outputs points in (y-down) scene pixel space
    CairoMakie.add_projected_line_points!(attr)
    CairoMakie.extract_attributes!(
        attr, [
            :clipped_points, :clipped_linewidths, :clipped_colors,
            :linestyle, :linecap, :joinstyle, :miter_limit, :is_lines_plot,
        ], :pgf_attributes
    )
    draw_lineplot(screen.writer, attr.pgf_attributes[])
    return
end

function draw_lineplot(w::PGFWriter, attributes)
    positions = attributes.clipped_points
    isempty(positions) && return

    linewidth = attributes.clipped_linewidths
    color = attributes.clipped_colors
    linestyle = attributes.linestyle
    is_lines_plot = attributes.is_lines_plot

    set_linecap(w, attributes.linecap)
    miter_angle = is_lines_plot ? attributes.miter_limit : 2pi / 3
    set_miterlimit(w, CairoMakie.to_cairo_miter_limit(miter_angle))
    set_joinstyle(w, is_lines_plot ? attributes.joinstyle : 0)

    if color isa AbstractArray || linewidth isa AbstractArray
        dash = isnothing(linestyle) ? nothing : diff(Float64.(to_linestyle_value(linestyle)))
        draw_multi(w, is_lines_plot, positions, color, linewidth, dash)
    else
        (iszero(linewidth) || alpha(color) == 0) && return
        set_dash(w, CairoMakie.to_cairo_linestyle(linestyle, linewidth))
        set_linewidth(w, linewidth)
        set_stroke(w, color)
        if is_lines_plot
            draw_single_lines(w, positions)
        else
            draw_single_segments(w, positions)
        end
    end
    return
end

to_linestyle_value(ls::Linestyle) = ls.value
to_linestyle_value(ls::AbstractVector) = ls

function draw_single_lines(w::PGFWriter, positions)
    n = length(positions)
    start = positions[begin]
    any_path = false
    @inbounds for i in 1:n
        p = positions[i]
        isnan(p) && continue
        if i == 1 || isnan(positions[i - 1])
            moveto(w, p)
            start = p
        else
            lineto(w, p)
            any_path = true
            if (i == n || isnan(positions[i + 1])) && p ≈ start
                closepath(w)
            end
        end
    end
    any_path && usepath(w, :stroke)
    return
end

function draw_single_segments(w::PGFWriter, positions)
    any_path = false
    @inbounds for i in 1:2:(length(positions) - 1)
        p1 = positions[i]
        p2 = positions[i + 1]
        (isnan(p1) || isnan(p2)) && continue
        moveto(w, p1)
        lineto(w, p2)
        any_path = true
    end
    any_path && usepath(w, :stroke)
    return
end

"""
Lines with varying colors or linewidths are drawn segment by segment, with the
average color of the two endpoints. Consecutive segments with the same style are
merged into one path.
"""
function draw_multi(w::PGFWriter, is_lines_plot, positions, colors, linewidths, dash)
    step = is_lines_plot ? 1 : 2
    last_style = nothing
    last_end = nothing
    pending = false
    for i in 1:step:(length(positions) - 1)
        p1 = positions[i]
        p2 = positions[i + 1]
        (isnan(p1) || isnan(p2)) && continue
        c = mix_colors(sv_getindex(colors, i), sv_getindex(colors, i + 1))
        lw = 0.5 * (sv_getindex(linewidths, i) + sv_getindex(linewidths, i + 1))
        if iszero(lw) || alpha(c) == 0
            pending && usepath(w, :stroke)
            pending = false
            last_style = nothing
            continue
        end
        style = (c, lw)
        if style != last_style
            pending && usepath(w, :stroke)
            set_linewidth(w, lw)
            set_dash(w, isnothing(dash) ? nothing : dash .* lw)
            set_stroke(w, c)
            last_style = style
            moveto(w, p1)
        elseif !(is_lines_plot && pending && last_end ≈ p1)
            moveto(w, p1)
        end
        lineto(w, p2)
        last_end = p2
        pending = true
    end
    pending && usepath(w, :stroke)
    return
end

function mix_colors(c1, c2)
    c1 == c2 && return RGBAf(c1)
    a, b = RGBAf(c1), RGBAf(c2)
    return RGBAf(
        0.5 * (red(a) + red(b)), 0.5 * (green(a) + green(b)),
        0.5 * (blue(a) + blue(b)), 0.5 * (alpha(a) + alpha(b))
    )
end
