################################################################################
#                               Image & Heatmap                                #
################################################################################

# Above this number of cells, heatmaps which can't be drawn as a single image
# (irregular grids, rotations, ...) are rasterized rather than drawn cell by cell
const MAX_VECTOR_CELLS = 10_000

function draw_atomic(scene::Scene, screen::Screen, plot::Union{Heatmap, Image})
    attr = plot.attributes
    CairoMakie.image_grid!(Makie.plotfunc(plot), attr)
    Makie.compute_colors!(attr)
    inputs = [
        :grid_x, :grid_y, :image, :interpolate, :space, :projectionview,
        :model_f32c, :clip_planes, :resolution, :computed_color,
    ]
    CairoMakie.extract_attributes!(attr, inputs, :pgf_image_attributes)
    a = attr[:pgf_image_attributes][]

    xs, ys = a.grid_x, a.grid_y
    model = a.model_f32c
    pv = a.projectionview
    colors = a.computed_color
    ni, nj = size(colors)

    is_regular_grid = xs isa AbstractRange && ys isa AbstractRange
    is_simple = Makie.is_translation_scale_matrix(model) && Makie.is_translation_scale_matrix(pv) &&
        isempty(a.clip_planes) && has_default_uv_transform(plot)

    if is_regular_grid && is_simple
        # The whole image maps to an axis aligned rectangle, so we can draw it
        # as one image with one pixel per cell
        p0 = CairoMakie.cairo_project_to_screen_impl(pv, a.resolution, model, Point2(first(xs), first(ys)))
        p1 = CairoMakie.cairo_project_to_screen_impl(pv, a.resolution, model, Point2(last(xs), last(ys)))
        # rows of the png go down in y, columns go right in x
        img = permutedims(colors, (2, 1))
        # data y increasing maps to screen y decreasing (y-down) if p1 is above p0
        p1[2] < p0[2] && (img = reverse(img; dims = 1))
        p1[1] < p0[1] && (img = reverse(img; dims = 2))
        x, y = min(p0[1], p1[1]), min(p0[2], p1[2])
        iw, ih = abs(p1[1] - p0[1]), abs(p1[2] - p0[2])
        (iw > 0 && ih > 0) || return
        emit_image(screen, map(c -> RGBA{Colors.N0f8}(clamp01(RGBAf(c))), img), x, y, iw, ih; interpolate = a.interpolate)
    elseif ni * nj <= MAX_VECTOR_CELLS && !a.interpolate && has_default_uv_transform(plot)
        draw_rect_heatmap(screen.writer, a, xs, ys, colors)
    else
        draw_rasterized(scene, screen, plot, screen.config.px_per_unit)
    end
    return
end

clamp01(c::RGBAf) = RGBAf(clamp(red(c), 0, 1), clamp(green(c), 0, 1), clamp(blue(c), 0, 1), clamp(alpha(c), 0, 1))

# Images flip their texture coordinates vertically by default
const DEFAULT_IMAGE_UV_TRANSFORM = Mat{2, 3, Float32}(1, 0, 0, -1, 0, 1)

"""
    has_default_uv_transform(plot)

Whether the image data is drawn as-is. Other `uv_transform`s (rotations, flips,
zooms) are left to CairoMakie's rasterization.
"""
function has_default_uv_transform(plot)
    plot isa Heatmap && return true
    T = plot.uv_transform[]
    return T === nothing || (T isa Mat{2, 3} && T ≈ DEFAULT_IMAGE_UV_TRANSFORM)
end

function draw_rect_heatmap(w::PGFWriter, a, xs, ys, colors)
    model = a.model_f32c
    planes = Makie.is_data_space(a.space) ? Makie.to_model_space(model, a.clip_planes) : Plane3f[]
    transformed = [Point2f(x, y) for x in xs, y in ys]
    for i in eachindex(transformed)
        if Makie.is_clipped(planes, transformed[i])
            transformed[i] = Point2f(NaN)
        end
    end
    xys = CairoMakie.cairo_project_to_screen_impl(a.projectionview, a.resolution, model, transformed)
    ni, nj = size(colors)
    last_color = nothing
    @inbounds for i in 1:ni, j in 1:nj
        p1, p2, p3, p4 = xys[i, j], xys[i + 1, j], xys[i + 1, j + 1], xys[i, j + 1]
        (isnan(p1) || isnan(p2) || isnan(p3) || isnan(p4)) && continue
        c = RGBAf(colors[i, j])
        alpha(c) == 0 && continue
        if alpha(c) == 1
            # pad cells slightly to avoid anti-aliasing seams (see CairoMakie)
            v1 = normalize(p2 - p1)
            v2 = normalize(p4 - p1)
            p2 += Float32(i != ni) * v1
            p3 += Float32(i != ni) * v1 + Float32(j != nj) * v2
            p4 += Float32(j != nj) * v2
        end
        # neighboring cells of the same color are merged into one path
        if c != last_color
            last_color === nothing || usepath(w, :fill)
            set_fill(w, c)
            last_color = c
        end
        polyline(w, (p1, p2, p3, p4); close = true)
    end
    last_color === nothing || usepath(w, :fill)
    return
end
