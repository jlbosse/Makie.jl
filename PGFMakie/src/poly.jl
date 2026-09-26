################################################################################
#                         Poly, Band, Tricontourf, Mesh                        #
################################################################################

# Like CairoMakie, we draw these recipes directly rather than decomposing them
# into meshes and lines, which gives much cleaner vector output.
is_pgf_atomic_plot(::Poly) = true
is_pgf_atomic_plot(::Band{<:Tuple{<:AbstractVector{<:Point2}, <:AbstractVector{<:Point2}}}) = true
is_pgf_atomic_plot(::Tricontourf) = true
draws_children(::Union{Poly, Band, Tricontourf}) = false

deref(x) = x
deref(x::Base.RefValue) = x[]

"""
    pgf_fill_color(color, plot)

Resolve a (possibly colormapped) fill color. Returns `nothing` for colors that
can't be represented as a flat PGF fill (patterns).
"""
pgf_fill_color(::Makie.AbstractPattern, plot) = nothing
pgf_fill_color(colors::Union{AbstractVector, Number}, plot) = CairoMakie.to_cairo_color(colors, plot)
pgf_fill_color(color, plot) = CairoMakie.to_cairo_color(color, plot)

has_pattern(x) = x isa Makie.AbstractPattern || (x isa AbstractVector && any(c -> c isa Makie.AbstractPattern, x))

struct StrokeStyle
    linestyle::Any
    miter_limit::Float64
    joinstyle::Int
    linecap::Int
end

function StrokeStyle(poly)
    return StrokeStyle(
        Makie.convert_attribute(poly.linestyle[], Makie.key"linestyle"()),
        CairoMakie.to_cairo_miter_limit(poly.miter_limit[]),
        Int(Makie.convert_attribute(poly.joinstyle[], Makie.key"joinstyle"())),
        Int(Makie.convert_attribute(poly.linecap[], Makie.key"linecap"())),
    )
end

"""
Fill and/or stroke the current path.
"""
function fill_stroke(w::PGFWriter, fillcolor, strokecolor, strokewidth, style::StrokeStyle)
    fillcolor = fillcolor === nothing ? nothing : RGBAf(to_color(fillcolor))
    strokecolor = RGBAf(to_color(strokecolor))
    do_fill = fillcolor !== nothing && alpha(fillcolor) > 0
    do_stroke = strokewidth > 0 && alpha(strokecolor) > 0
    do_fill && set_fill(w, fillcolor)
    if do_stroke
        set_stroke(w, strokecolor)
        set_linewidth(w, strokewidth)
        set_dash(w, CairoMakie.to_cairo_linestyle(style.linestyle, strokewidth))
        set_miterlimit(w, style.miter_limit)
        set_joinstyle(w, style.joinstyle)
        set_linecap(w, style.linecap)
    end
    if do_fill && do_stroke
        usepath(w, :fill, :stroke)
    elseif do_fill
        usepath(w, :fill)
    elseif do_stroke
        usepath(w, :stroke)
    else
        # discard the path
        usepath(w)
    end
    return
end

function draw_atomic(scene::Scene, screen::Screen, poly::Poly)
    if has_pattern(poly.color[])
        # hatching etc. is rasterized
        return draw_rasterized(scene, screen, poly, screen.config.px_per_unit)
    end
    args = deref(poly.args[])
    if Base.hasmethod(draw_poly, Tuple{Scene, Screen, typeof(poly), typeof.(args)...})
        return draw_poly(scene, screen, poly, args...)
    end
    converted = deref(poly.converted[])
    if Base.hasmethod(draw_poly, Tuple{Scene, Screen, typeof(poly), typeof.(converted)...})
        return draw_poly(scene, screen, poly, converted...)
    end
    return draw_poly_as_mesh(scene, screen, poly)
end

function draw_poly_as_mesh(scene, screen, poly)
    for p in poly.plots
        draw_plot(scene, screen, p)
    end
    return
end

function poly_colors(poly)
    color = pgf_fill_color(poly.color[], poly)
    strokecolor = CairoMakie.to_cairo_color(poly.strokecolor[], poly.plots[2])
    return color, strokecolor
end

draw_poly(scene::Scene, screen::Screen, poly, points::Vector{<:Point2}) = draw_poly(scene, screen, poly, [points])
draw_poly(scene::Scene, screen::Screen, poly, circle::Circle) = draw_poly(scene, screen, poly, decompose(Point2f, circle))

function draw_poly(scene::Scene, screen::Screen, poly, points_list::Vector{<:Vector{<:Point2}})
    color, strokecolor = poly_colors(poly)
    # per vertex colors need a mesh
    if color isa AbstractVector && length(color) != length(points_list)
        return draw_poly_as_mesh(scene, screen, poly)
    end
    w = screen.writer
    style = StrokeStyle(poly)
    model = poly.model[]
    space = poly.space[]
    planes = poly.clip_planes[]
    tf = Makie.transform_func(poly)
    broadcast_foreach(points_list, color, strokecolor, poly.strokewidth[]) do points, c, sc, sw
        isempty(points) && return
        points = Makie.apply_transform(tf, points)
        points = CairoMakie.clip_poly(planes, points, space, model)
        points = CairoMakie._project_position(scene, space, points, model, true)
        isempty(points) && return
        polyline(w, points; close = true)
        fill_stroke(w, c, sc, sw, style)
    end
    return
end

draw_poly(scene::Scene, screen::Screen, poly, rect::Rect2) = draw_poly(scene, screen, poly, [rect])
draw_poly(scene::Scene, screen::Screen, poly, bezierpath::BezierPath) = draw_poly(scene, screen, poly, [bezierpath])

function draw_poly(scene::Scene, screen::Screen, poly, shapes::Vector{<:Union{Rect2, BezierPath}})
    model = poly.model[]::Mat4d
    space = poly.space[]::Symbol
    planes = poly.clip_planes[]::Vector{Plane3f}
    projected_shapes = map(shapes) do shape
        clipped = CairoMakie.clip_shape(planes, shape, space, model)
        return CairoMakie.project_shape(poly, space, clipped, model)
    end
    color, strokecolor = poly_colors(poly)
    w = screen.writer
    style = StrokeStyle(poly)
    broadcast_foreach(projected_shapes, color, strokecolor, poly.strokewidth[]) do shape, c, sc, sw
        shape_path(w, shape)
        fill_stroke(w, c, sc, sw, style)
    end
    return
end

function shape_path(w::PGFWriter, r::Rect2)
    x, y = origin(r)
    rw, rh = widths(r)
    polyline(w, [Point2d(x, y), Point2d(x + rw, y), Point2d(x + rw, y + rh), Point2d(x, y + rh)]; close = true)
    return
end

function shape_path(w::PGFWriter, b::BezierPath)
    isempty(b.commands) && return
    bezier_path(w, b, identity)
    # match W/GLMakie
    last(b.commands) isa ClosePath || closepath(w)
    return
end

function polygon_path(w::PGFWriter, polygon::Polygon)
    ext = decompose(Point2f, polygon.exterior)
    isempty(ext) && return
    polyline(w, ext; close = true)
    for interior in polygon.interiors
        polyline(w, decompose(Point2f, interior); close = true)
    end
    return
end

draw_poly(scene::Scene, screen::Screen, poly, polygon::Polygon) = draw_poly(scene, screen, poly, [polygon])
draw_poly(scene::Scene, screen::Screen, poly, multipolygon::MultiPolygon) = draw_poly(scene, screen, poly, multipolygon.polygons)

function draw_poly(scene::Scene, screen::Screen, poly, polygons::AbstractArray{<:Polygon})
    model = poly.model[]
    space = poly.space[]
    projected = map(p -> CairoMakie.project_polygon(poly, space, p, poly.clip_planes[], model), polygons)
    color, strokecolor = poly_colors(poly)
    w = screen.writer
    style = StrokeStyle(poly)
    set_eorule(w)
    broadcast_foreach(projected, color, strokecolor, poly.strokewidth[]) do po, c, sc, sw
        polygon_path(w, po)
        fill_stroke(w, c, sc, sw, style)
    end
    return
end

function draw_poly(scene::Scene, screen::Screen, poly, polygons::AbstractArray{<:MultiPolygon})
    model = poly.model[]
    space = poly.space[]
    projected = map(p -> CairoMakie.project_multipolygon(poly, space, p, poly.clip_planes[], model), polygons)
    color, strokecolor = poly_colors(poly)
    w = screen.writer
    style = StrokeStyle(poly)
    set_eorule(w)
    broadcast_foreach(projected, color, strokecolor, poly.strokewidth[]) do mpo, c, sc, sw
        for po in mpo.polygons
            polygon_path(w, po)
        end
        fill_stroke(w, c, sc, sw, style)
    end
    return
end

################################################################################
#                                     Band                                     #
################################################################################

function draw_atomic(scene::Scene, screen::Screen, band::Band{<:Tuple{<:AbstractVector{<:Point2}, <:AbstractVector{<:Point2}}})
    if band.color[] isa AbstractArray || has_pattern(band.color[])
        # gradients are drawn by the mesh child plot (which gets rasterized)
        for p in band.plots
            draw_plot(scene, screen, p)
        end
        return
    end
    w = screen.writer
    color = RGBAf(CairoMakie.to_cairo_color(band.color[], band))
    model = band.model[]
    space = band.space[]
    xdir = band.direction[] === :x
    upperpoints = xdir ? band[1][] : reverse.(band[1][])
    lowerpoints = xdir ? band[2][] : reverse.(band[2][])
    set_fill(w, color)
    any_path = false
    for rng in CairoMakie.band_segment_ranges(lowerpoints, upperpoints)
        points_segment = vcat(@view(lowerpoints[rng]), reverse(@view(upperpoints[rng])))
        points = CairoMakie.clip_poly(band.clip_planes[], points_segment, space, model)
        isempty(points) && continue
        points = CairoMakie.project_position.(Ref(band), space, points, Ref(model))
        polyline(w, points; close = true)
        any_path = true
    end
    any_path && usepath(w, :fill)
    # outlines etc.
    for p in band.plots
        p isa Mesh && continue
        draw_plot(scene, screen, p)
    end
    return
end

################################################################################
#                                 Tricontourf                                  #
################################################################################

function draw_atomic(scene::Scene, screen::Screen, tric::Tricontourf)
    pol = only(tric.plots)::Poly
    has_pattern(pol.color[]) && return draw_rasterized(scene, screen, tric, screen.config.px_per_unit)
    colornumbers = pol.color[]
    colors = CairoMakie.to_cairo_color(colornumbers, pol)
    polygons = pol[1][]
    model = pol.model[]
    space = pol.space[]
    projected = CairoMakie.project_polygon.(Ref(tric), space, polygons, Ref(tric.clip_planes[]), Ref(model))
    w = screen.writer
    set_eorule(w)
    # merge adjacent polygons of the same color into one path to avoid seams
    for (i, (po, colnum, col)) in enumerate(zip(projected, colornumbers, colors))
        polygon_path(w, po)
        if i == length(colornumbers) || colnum != colornumbers[i + 1]
            set_fill(w, col)
            usepath(w, :fill)
        end
    end
    return
end

################################################################################
#                                     Mesh                                     #
################################################################################

function draw_atomic(scene::Scene, screen::Screen, plot::Makie.Mesh)
    attr = plot.attributes
    is_2d = Makie.cameracontrols(scene) isa Union{Camera2D, Makie.PixelCamera, Makie.EmptyCamera}
    Makie.compute_colors!(attr)
    color = Makie.compute_colors(attr)
    # only single colored 2D meshes can be drawn as a flat PGF fill, everything
    # else (shading, per vertex colors, textures) is rasterized
    if !is_2d || !(color isa Colorant)
        return draw_rasterized(scene, screen, plot, screen.config.px_per_unit)
    end
    vs = CairoMakie.cairo_project_to_screen(attr)
    fs = attr.faces[]
    w = screen.writer
    set_nonzerorule(w)
    any_path = false
    for f in fs
        t1, t2, t3 = vs[f]
        (isnan(t1) || isnan(t2) || isnan(t3)) && continue
        # consistent orientation, so that the nonzero rule gives the union
        turn = (t2[1] - t1[1]) * (t3[2] - t1[2]) - (t2[2] - t1[2]) * (t3[1] - t1[1])
        p1, p2, p3 = turn >= 0 ? (t1, t2, t3) : (t1, t3, t2)
        moveto(w, p1)
        lineto(w, p2)
        lineto(w, p3)
        closepath(w)
        any_path = true
    end
    if any_path
        set_fill(w, color)
        usepath(w, :fill)
    end
    return
end
