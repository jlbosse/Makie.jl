################################################################################
#                               Drawing pipeline                               #
################################################################################

"""
    is_pgf_atomic_plot(plot)

Whether the plot is drawn directly by PGFMakie, rather than by recursing into
its child plots. Like CairoMakie, we draw some recipes directly (e.g. `Poly`)
to get cleaner vector output.
"""
is_pgf_atomic_plot(plot::Plot) = Makie.is_atomic_plot(plot) || isempty(plot.plots)
is_pgf_atomic_plot_or_rasterized(plot::Plot) = is_pgf_atomic_plot(plot) || Int(plot.rasterize[]::Integer) > 0

# The main entry point into the drawing pipeline
function pgf_draw(screen::Screen, scene::Scene)
    w = screen.writer
    draw_background(screen, scene)

    allplots = Makie.collect_atomic_plots(scene; is_atomic_plot = is_pgf_atomic_plot_or_rasterized)
    sort!(allplots; by = Makie.zvalue2d)

    last_scene = nothing
    for p in allplots
        CairoMakie.check_parent_plots(p) do plot
            to_value(get(plot, :visible, true))
        end || continue
        # LaTeXStrings are typeset by LaTeX as a whole, including fraction bars
        # etc. which Makie draws as a child linesegments plot
        is_tex_decoration(p) && continue
        pparent = Makie.parent_scene(p)::Scene
        pparent.visible[]::Bool || continue
        if pparent !== last_scene
            last_scene === nothing || end_scope(w)
            prepare_for_scene(screen, pparent)
            last_scene = pparent
        end
        rasterize = Int(p.rasterize[]::Integer)
        if rasterize != 0
            draw_plot_as_image(pparent, screen, p, rasterize)
        else
            draw_plot(pparent, screen, p)
        end
    end
    last_scene === nothing || end_scope(w)
    return
end

function is_tex_decoration(p::Plot)
    p isa LineSegments || return false
    parent = p.parent
    parent isa Text || return false
    return any(x -> x isa LaTeXString, parent.input_text[])
end

"""
    prepare_for_scene(screen, scene)

Opens a scope for drawing plots of `scene`: shifts the origin to the scene's
viewport and clips to it. Plots then draw in the scene's local pixel space.
"""
function prepare_for_scene(screen::Screen, scene::Scene)
    w = screen.writer
    area = viewport(scene)[]
    x0, y0 = origin(area)
    sw, sh = widths(area)
    begin_scope(w)
    emitln(w, "\\pgftransformshift{\\pgfqpoint{", fmt(x0 * w.scale), "bp}{", fmt(y0 * w.scale), "bp}}")
    w.height = sh
    clip_rect(w, 0, 0, sw, sh)
    return
end

function draw_background(screen::Screen, scene::Scene)
    w = screen.writer
    root_h = widths(viewport(Makie.root(scene))[])[2]
    w.height = root_h
    return draw_background(screen, scene, root_h)
end

function draw_background(screen::Screen, scene::Scene, root_h)
    w = screen.writer
    if scene.clear[] && scene.visible[]
        bg = to_color(scene.backgroundcolor[])
        if alpha(bg) > 0
            r = viewport(scene)[]
            x, y = origin(r)
            sw, sh = widths(r)
            begin_scope(w)
            set_fill(w, bg)
            # y-down coordinates of the root scene
            rectangle(w, x, root_h - y - sh, sw, sh)
            usepath(w, :fill)
            end_scope(w)
        end
    end
    foreach(child -> draw_background(screen, child, root_h), scene.children)
    return
end

function draw_plot(scene::Scene, screen::Screen, primitive::Plot)
    to_value(get(primitive, :visible, true)) || return
    if is_pgf_atomic_plot(primitive)
        w = screen.writer
        begin_scope(w)
        try
            draw_atomic(scene, screen, primitive)
        finally
            end_scope(w)
        end
    end
    if !isempty(primitive.plots) && (!is_pgf_atomic_plot(primitive) || draws_children(primitive))
        zvals = Makie.zvalue2d.(primitive.plots)
        for idx in sortperm(zvals)
            child = primitive.plots[idx]
            is_tex_decoration(child) && continue
            draw_plot(scene, screen, child)
        end
    end
    return
end

"""
    draws_children(plot)

Whether the child plots of an atomic plot should be drawn after the plot itself
(e.g. the linesegments of `Text`). Recipes which PGFMakie draws directly, like
`Poly`, handle their children themselves.
"""
draws_children(::Plot) = true

draw_atomic(::Scene, ::Screen, ::PlotList) = nothing

# Anything we don't know how to draw as PGF gets rasterized with CairoMakie
function draw_atomic(scene::Scene, screen::Screen, plot::Plot)
    if screen.config.raster_fallback
        draw_rasterized(scene, screen, plot, screen.config.px_per_unit)
    else
        @warn "$(typeof(plot).name.name) is not supported by PGFMakie and `raster_fallback = false`, skipping it."
    end
    return
end

"""
    draw_plot_as_image(scene, screen, plot, scale)

Implements `rasterize = scale`: draws the plot with CairoMakie into an image
which is embedded into the PGF output.
"""
function draw_plot_as_image(scene::Scene, screen::Screen, plot::Plot, scale::Integer)
    to_value(get(plot, :visible, true)) || return
    w = screen.writer
    begin_scope(w)
    try
        # `rasterize = true` converts to 1, which would be quite blurry. Use at
        # least the configured resolution
        draw_rasterized(scene, screen, plot, max(scale, screen.config.px_per_unit))
    finally
        end_scope(w)
    end
    return
end

"""
    draw_rasterized(scene, screen, plot, px_per_unit)

Draw `plot` with CairoMakie into a transparent image the size of `scene`, crop
it to its content and emit it as a sidecar image.
"""
function draw_rasterized(scene::Scene, screen::Screen, plot::Plot, px_per_unit::Real)
    cscreen = CairoMakie.Screen(scene; px_per_unit = px_per_unit)
    CairoMakie.draw_plot(scene, cscreen, plot)
    CairoMakie.Cairo.flush(cscreen.surface)
    # surface data is (width, height), row-major y-down
    data = cscreen.surface.data
    img = permutedims(data, (2, 1))
    # crop to non-transparent content
    rows = findall(r -> any(c -> Colors.alpha(c) > 0, r), eachrow(img))
    cols = findall(c -> any(x -> Colors.alpha(x) > 0, c), eachcol(img))
    (isempty(rows) || isempty(cols)) && return
    r1, r2 = first(rows), last(rows)
    c1, c2 = first(cols), last(cols)
    cropped = img[r1:r2, c1:c2]
    rgba = map(argb32_to_rgba, cropped)
    # position in scene pixel space (y-down)
    s = 1 / px_per_unit
    x, y = (c1 - 1) * s, (r1 - 1) * s
    iw, ih = size(rgba, 2) * s, size(rgba, 1) * s
    emit_image(screen, rgba, x, y, iw, ih; interpolate = true)
    return
end

# Cairo stores premultiplied ARGB
function argb32_to_rgba(c::Colors.ARGB32)
    a = Colors.alpha(c)
    a == 0 && return RGBA{Colors.N0f8}(0, 0, 0, 0)
    af = Float64(a)
    return RGBA{Colors.N0f8}(
        clamp(Float64(Colors.red(c)) / af, 0, 1),
        clamp(Float64(Colors.green(c)) / af, 0, 1),
        clamp(Float64(Colors.blue(c)) / af, 0, 1),
        a,
    )
end

"""
    emit_image(screen, img, x, y, width, height; interpolate)

Register `img` (rows = y-down) as a sidecar PNG and draw it with its top left
corner at `(x, y)` (scene pixel space, y-down) with the given size.
"""
function emit_image(screen::Screen, img::AbstractMatrix, x, y, iw, ih; interpolate::Bool = true)
    w = screen.writer
    stem = screen.image_stem === nothing ? "figure" : basename(screen.image_stem)
    # file names are used in LaTeX, where spaces and special characters break \pgfimage
    stem = replace(stem, r"[^A-Za-z0-9_-]" => "_")
    name = string(stem, "-img", length(screen.images) + 1, ".png")
    push!(screen.images, name => convert(Matrix{RGBA{Colors.N0f8}}, img))
    emitln(
        w, "\\pgftext[left,bottom,at=", qpoint(w, x, y + ih), "]{\\pgfimage[interpolate=",
        interpolate, ",width=", dim(w, iw), ",height=", dim(w, ih), "]{", name, "}}"
    )
    return
end
