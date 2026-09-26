################################################################################
#                                   Scatter                                    #
################################################################################

function draw_atomic(scene::Scene, screen::Screen, plot::Scatter)
    attr = plot.attributes
    isempty(attr.positions[]) && return
    # Same setup as CairoMakie, so the computed nodes can be shared
    Makie.add_computation!(attr, scene, Val(:meshscatter_f32c_scale))
    CairoMakie.cairo_unclipped_indices!(attr)
    Makie.compute_colors!(attr)
    Makie.register_positions_projected!(
        scene.compute, attr, Point3d;
        input_name = :positions_transformed_f32c, output_name = :positions_in_markerspace,
        input_space = :space, output_space = :markerspace, apply_clip_planes = false
    )
    map!(CairoMakie.cairo_scatter_marker, attr, :marker, :cairo_marker)
    CairoMakie.size_model!(attr)
    if !haskey(attr, :eye_to_clip)
        add_input!(attr, :eye_to_clip, scene.compute.projection)
        add_input!(attr, :cam_view, scene.compute.view)
    end
    inputs = [
        :positions_in_markerspace, :projectionview, :eye_to_clip, :cam_view,
        :markersize, :strokewidth, :cairo_marker, :marker_offset,
        :converted_rotation, :billboard, :transform_marker, :size_model, :markerspace,
        :space, :clip_planes, :unclipped_indices, :font,
        :strokecolor, :computed_color, :resolution,
    ]
    CairoMakie.extract_attributes!(attr, inputs, :pgf_scatter_attributes)
    attributes = attr[:pgf_scatter_attributes][]

    # image markers can't be drawn as vector graphics
    marker = attributes.cairo_marker
    if marker isa AbstractMatrix || (marker isa AbstractVector && any(m -> m isa AbstractMatrix, marker))
        return draw_rasterized(scene, screen, plot, screen.config.px_per_unit)
    end
    draw_atomic_scatter(screen, attributes)
    return
end

function draw_atomic_scatter(screen::Screen, attr::NamedTuple)
    w = screen.writer
    size_model = attr.size_model
    markerspace = attr.markerspace
    billboard = attr.billboard
    cam = (
        resolution = attr.resolution,
        projectionview = attr.projectionview,
        eye_to_clip = attr.eye_to_clip,
        view = attr.cam_view,
    )
    args = (
        attr.unclipped_indices,
        attr.positions_in_markerspace,
        attr.computed_color,
        attr.markersize,
        attr.strokecolor,
        attr.strokewidth,
        attr.cairo_marker,
        attr.marker_offset,
        attr.converted_rotation,
    )

    # Consecutive markers without a (visible) stroke and with the same opaque
    # color are combined into one path, which keeps the output small.
    batch_color = Ref{Any}(nothing)
    function flush_batch!()
        if batch_color[] !== nothing
            usepath(w, :fill)
            batch_color[] = nothing
        end
        return
    end

    Makie.broadcast_foreach_index(args...) do position, col, markersize, strokecolor, strokewidth, marker, marker_offset, rot
        isnan(position) && return
        isnan(rot) && return
        (isnan(markersize) || CairoMakie.is_approx_zero(markersize)) && return
        rotation = CairoMakie.remove_billboard(rot)
        origin = position .+ size_model * to_ndim(Vec3d, marker_offset, 0)
        proj_pos, _, jl_mat = CairoMakie.project_marker(
            cam, markerspace, origin, markersize, rotation, size_model, billboard
        )
        CairoMakie.is_degenerate(jl_mat) && return

        col = RGBAf(col)
        strokecolor = RGBAf(to_color(strokecolor))
        has_stroke = strokewidth > 0 && alpha(strokecolor) > 0
        has_fill = alpha(col) > 0
        (has_fill || has_stroke) || return

        if marker isa Char
            flush_batch!()
            draw_char_marker(w, marker, attr.font, proj_pos, jl_mat, col)
            return
        end

        batchable = !has_stroke && alpha(col) == 1
        if batchable && batch_color[] == col
            # continue the current path
        else
            flush_batch!()
            set_fill(w, col)
            if has_stroke
                set_linewidth(w, strokewidth)
                set_stroke(w, strokecolor)
                set_dash(w, nothing)
                set_joinstyle(w, 0)
            end
        end
        marker_path(w, marker, proj_pos, jl_mat)
        if batchable
            batch_color[] = col
        elseif has_stroke
            has_fill ? usepath(w, :fill, :stroke) : usepath(w, :stroke)
        else
            usepath(w, :fill)
        end
    end
    flush_batch!()
    return
end

# `pos` is the projected (y-down) marker center, `M` maps the marker's local
# coordinates (normalized to markersize, y-down) to scene pixel space.

function marker_path(w::PGFWriter, ::Type{<:Circle}, pos, M::Mat2f)
    return ellipse(w, pos, 0.5 .* M[:, 1], 0.5 .* M[:, 2])
end

function marker_path(w::PGFWriter, ::Union{Makie.FastPixel, <:Type{<:Rect}}, pos, M::Mat2f)
    corners = (Vec2f(-0.5, -0.5), Vec2f(0.5, -0.5), Vec2f(0.5, 0.5), Vec2f(-0.5, 0.5))
    moveto(w, pos + M * corners[1])
    for c in corners[2:end]
        lineto(w, pos + M * c)
    end
    closepath(w)
    return
end

function marker_path(w::PGFWriter, path::BezierPath, pos, M::Mat2f)
    # BezierPath markers have y pointing up, while the local marker coordinates are y-down
    tf(p) = Point2d(pos) + Mat2d(M) * Vec2d(p[1], -p[2])
    return bezier_path(w, path, tf)
end

"""
    bezier_path(w, path, tf)

Emit the commands of a `BezierPath`, transforming each point with `tf` into
(y-down) scene pixel space.
"""
function bezier_path(w::PGFWriter, path::BezierPath, tf)
    for c in path.commands
        if c isa MoveTo
            moveto(w, tf(c.p))
        elseif c isa LineTo
            lineto(w, tf(c.p))
        elseif c isa CurveTo
            curveto(w, tf(c.c1), tf(c.c2), tf(c.p))
        elseif c isa ClosePath
            closepath(w)
        elseif c isa EllipticalArc
            for c2 in Makie.elliptical_arc_to_beziers(c).commands
                if c2 isa LineTo
                    lineto(w, tf(c2.p))
                elseif c2 isa CurveTo
                    curveto(w, tf(c2.c1), tf(c2.c2), tf(c2.p))
                end
            end
        end
    end
    return
end

function marker_path(w::PGFWriter, marker, pos, M::Mat2f)
    @warn "Marker of type $(typeof(marker)) is not supported by PGFMakie, drawing a circle instead." maxlog = 1
    return marker_path(w, Circle, pos, M)
end

"""
Draws a character marker as LaTeX text, centered on the marker position.
The font size is the length of the (projected) x axis of the marker.
"""
function draw_char_marker(w::PGFWriter, marker::Char, font, pos, M::Mat2f, color::RGBAf)
    xvec = M[:, 1]
    fontsize = norm(xvec)
    angle = rad2deg(atan(-xvec[2], xvec[1]))
    set_fill(w, color)
    define_color(w, "pgfmakietext", color)
    str = escape_latex(string(marker))
    fs = fmt(fontsize * w.scale)
    return emitln(
        w, "\\pgftext[at=", qpoint(w, pos), ",rotate=", fmt(angle), "]{\\color{pgfmakietext}",
        "\\fontsize{", fs, "bp}{", fs, "bp}\\selectfont ", str, "}"
    )
end
