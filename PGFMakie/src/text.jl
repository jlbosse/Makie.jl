################################################################################
#                                     Text                                     #
################################################################################

# Text is emitted as LaTeX via `\pgftext`, so that it is typeset with the fonts
# of the surrounding document. Makie's own layout (computed with Makie's fonts)
# is used to place each line of text: we anchor the LaTeX text on the baseline
# of the line Makie laid out, at the horizontally aligned point, and let LaTeX
# align the text horizontally around it. This keeps alignment correct even
# though the LaTeX fonts have different metrics.

function draw_atomic(scene::Scene, screen::Screen, plot::Text)
    attr = plot.attributes
    Makie.register_positions_projected!(
        scene.compute, attr, Point3d;
        input_name = :positions_transformed_f32c, output_name = :positions_in_markerspace,
        input_space = :space, output_space = :markerspace, apply_clip_planes = false
    )
    Makie.add_computation!(attr, scene, Val(:meshscatter_f32c_scale))
    CairoMakie.size_model!(attr)
    if !haskey(attr, :eye_to_clip)
        add_input!(attr, :eye_to_clip, scene.compute.projection)
        add_input!(attr, :cam_view, scene.compute.view)
    end
    # one index per text block (CairoMakie uses one per glyph under the name :unclipped_indices)
    Makie.register_computation!(
        attr, [:positions_transformed_f32c, :model_f32c, :space, :clip_planes], [:pgf_unclipped_blocks]
    ) do (transformed, model, space, clip_planes), changed, outputs
        return (Makie.unclipped_indices(Makie.to_model_space(model, clip_planes), transformed, space),)
    end
    inputs = [
        :input_text, :text_blocks, :font_per_char, :glyph_origins, :glyph_extents, :offset,
        :text_rotation, :text_scales, :text_color, :align, :justification, :markerspace,
        :positions_in_markerspace, :projectionview, :eye_to_clip, :cam_view, :resolution,
        :size_model, :pgf_unclipped_blocks,
    ]
    CairoMakie.extract_attributes!(attr, inputs, :pgf_text_attributes)
    draw_text(screen, attr[:pgf_text_attributes][])
    return
end

function draw_text(screen::Screen, attr::NamedTuple)
    w = screen.writer
    cam = (
        resolution = attr.resolution,
        projectionview = attr.projectionview,
        eye_to_clip = attr.eye_to_clip,
        view = attr.cam_view,
    )
    unclipped = attr.pgf_unclipped_blocks
    for (block_idx, glyph_range) in enumerate(attr.text_blocks)
        block_idx in unclipped || continue
        str = attr.input_text[block_idx]
        isempty(glyph_range) && continue
        position = attr.positions_in_markerspace[block_idx]
        isnan(position) && continue
        offset = to_ndim(Vec3d, sv_getindex(attr.offset, block_idx), 0)
        halign, valign = text_alignment(sv_getindex(attr.align, block_idx))
        g1 = first(glyph_range)
        rotation = attr.text_rotation[g1]
        scale = attr.text_scales[g1]
        color = RGBAf(attr.text_color[g1])
        alpha(color) > 0 || continue
        font = attr.font_per_char[g1]

        for line in text_lines(str, attr, glyph_range, halign, valign, sv_getindex(attr.justification, block_idx))
            # position of the anchor of this line, relative to the text position (markerspace)
            anchor = Vec3d(rotation * to_ndim(Vec3d, line.anchor, 0)) + offset
            origin = position .+ attr.size_model * anchor
            proj_pos, _, M = CairoMakie.project_marker(
                cam, attr.markerspace, origin, scale, rotation, attr.size_model
            )
            CairoMakie.is_degenerate(M) && continue
            draw_line(w, screen.config, line, proj_pos, M, color, font)
        end
    end
    return
end

"""
    text_alignment(align)

Convert Makie's (already converted) alignment into horizontal and vertical
fractions (0 = left/bottom, 1 = right/top).
"""
function text_alignment(align)
    h, v = align
    h = h isa Symbol ? (h === :left ? 0.0 : h === :right ? 1.0 : 0.5) : Float64(h)
    v = v isa Symbol ? (v === :bottom ? 0.0 : v === :top ? 1.0 : v === :baseline ? NaN : 0.5) : Float64(v)
    return h, v
end

justification_fraction(j::Symbol, halign) = j === :left ? 0.0 : j === :right ? 1.0 : 0.5
justification_fraction(j::Real, halign) = Float64(j)
justification_fraction(::Makie.Automatic, halign) = halign

"""
A line of text to be typeset by LaTeX.

- `latex`: the LaTeX source of the line
- `anchor`: the point (in unrotated text coordinates, relative to the text origin)
  at which the LaTeX text is anchored
- `h`: horizontal alignment of the LaTeX box around the anchor
- `v`: vertical alignment of the LaTeX box, or `NaN` to anchor on the baseline
"""
struct TextLine
    latex::String
    anchor::Point2d
    h::Float64
    v::Float64
    # whether to apply bold/italic from the Makie font
    use_font_style::Bool
end

# LaTeX is laid out by MathTeXEngine, which uses different metrics than LaTeX.
# Makie places the text origin at the aligned point of the text's bounding box,
# so we let LaTeX align its own box in the same way around the text origin.
function text_lines(str::LaTeXString, attr, glyph_range, halign::Real, valign::Real, justification)
    v = isnan(valign) ? 0.0 : valign
    return [TextLine(latex_source(str), Point2d(0), halign, v, false)]
end

function text_lines(str::AbstractString, attr, glyph_range, halign::Real, valign::Real, justification)
    j = justification_fraction(justification, halign)
    chars = collect(str)
    lines = TextLine[]
    if length(chars) != length(glyph_range)
        # unexpected layout (e.g. word wrapping changed things), anchor on the text origin
        return [TextLine(escape_latex(str), Point2d(0), halign, NaN, true)]
    end
    line_start = 1
    for i in 1:(length(chars) + 1)
        if i > length(chars) || chars[i] == '\n'
            r = line_start:(i - 1)
            if !isempty(r) && !all(isspace, chars[r])
                push!(lines, line_from_glyphs(String(chars[r]), attr, glyph_range[r], j))
            end
            line_start = i + 1
        end
    end
    return lines
end

function text_lines(str::Makie.RichText, attr, glyph_range, halign::Real, valign::Real, justification)
    # TODO: translate rich text formatting to LaTeX
    v = isnan(valign) ? 0.0 : valign
    return [TextLine(escape_latex(rich_plain_text(str)), Point2d(0), halign, v, true)]
end

text_lines(str, attr, glyph_range, halign::Real, valign::Real, justification) =
    text_lines(string(str), attr, glyph_range, halign, valign, justification)

rich_plain_text(s::AbstractString) = s
rich_plain_text(r::Makie.RichText) = join(rich_plain_text.(r.children))

function line_from_glyphs(str, attr, glyph_idxs, j)
    # glyph origins are rotated, undo the rotation to get a straight baseline
    rotation = attr.text_rotation[first(glyph_idxs)]
    inv_rot = inv(rotation)
    local_origin(gi) = Point2d((inv_rot * Vec3d(attr.glyph_origins[gi]))[Vec(1, 2)])
    first_origin = local_origin(first(glyph_idxs))
    xmin = Inf
    xmax = -Inf
    for gi in glyph_idxs
        o = local_origin(gi)
        ext = attr.glyph_extents[gi]
        scale = attr.text_scales[gi][1]
        xmin = min(xmin, o[1])
        xmax = max(xmax, o[1] + ext.hadvance * scale)
    end
    anchor = Point2d(xmin + j * (xmax - xmin), first_origin[2])
    return TextLine(escape_latex(str), anchor, j, NaN, true)
end

"""
    latex_source(str::LaTeXString)

LaTeXStrings used in Makie are usually math wrapped in `\$...\$`, which works as-is.
"""
latex_source(str::LaTeXString) = String(str)

function draw_line(w::PGFWriter, config::ScreenConfig, line::TextLine, pos, M::Mat2f, color::RGBAf, font)
    xvec = M[:, 1]
    fontsize = norm(xvec)
    # M is in y-down space, PGF angles are counter clockwise in y-up space
    angle = rad2deg(atan(-xvec[2], xvec[1]))
    define_color(w, "pgfmakietext", color)
    alpha(color) < 1 && emitln(w, "\\pgfsetfillopacity{", fmt(alpha(color)), "}\\pgfsetstrokeopacity{", fmt(alpha(color)), "}")
    fontcmd = if config.set_fontsize
        fs = fontsize * w.scale
        string("\\fontsize{", fmt(fs), "bp}{", fmt(1.2 * fs), "bp}\\selectfont")
    else
        ""
    end
    style = line.use_font_style ? font_style_commands(font) : ""
    content = string("\\color{pgfmakietext}", fontcmd, style, " ", line.latex)
    aligned = if isnan(line.v)
        string("\\pgfmakiealign{", fmt(line.h), "}{", content, "}")
    else
        string("\\pgfmakiealignv{", fmt(line.h), "}{", fmt(line.v), "}{", content, "}")
    end
    rot = abs(angle) < 1.0e-3 ? "" : string(",rotate=", fmt(angle))
    emitln(w, "\\pgftext[left,base,at=", qpoint(w, pos), rot, "]{", aligned, "}")
    # opacity is reset by the end of the plot's scope; reset the writer cache
    w.fill_color = nothing
    w.stroke_color = nothing
    return
end

function font_style_commands(font)
    style = try
        lowercase(font.style_name)
    catch
        ""
    end
    cmds = ""
    occursin("bold", style) && (cmds *= "\\bfseries")
    (occursin("italic", style) || occursin("oblique", style)) && (cmds *= "\\itshape")
    return cmds
end
