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
        :text_rotation, :text_scales, :text_color, :text_strokewidth, :text_strokecolor, :align, :justification, :word_wrap_width, :markerspace,
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
        stroke = (attr.text_strokewidth[g1], attr.text_strokecolor[g1])

        for line in text_lines(
                str, attr, glyph_range, halign, valign,
                sv_getindex(attr.justification, block_idx), sv_getindex(attr.word_wrap_width, block_idx),
                screen.bold_at
            )
            # position of the anchor of this line, relative to the text position (markerspace)
            anchor = Vec3d(rotation * to_ndim(Vec3d, line.anchor, 0)) + offset
            origin = position .+ attr.size_model * anchor
            proj_pos, _, M = CairoMakie.project_marker(
                cam, attr.markerspace, origin, scale, rotation, attr.size_model
            )
            CairoMakie.is_degenerate(M) && continue
            draw_line(w, screen, line, proj_pos, M, scale, color, font, stroke)
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
- `use_font_style`: whether to apply bold/italic from the Makie font
- `wrap_width`: if finite, the text is set in a paragraph of this width (in the
  same units as the font size) and wrapped by LaTeX, justified according to `justification`
"""
struct TextLine
    latex::String
    anchor::Point2d
    h::Float64
    v::Float64
    use_font_style::Bool
    wrap_width::Float64
    justification::Float64
    # font of the line (for bold/italic), `nothing` to use the font of the text block
    font::Any
end

TextLine(latex, anchor, h, v, use_font_style) = TextLine(latex, anchor, h, v, use_font_style, NaN, h, nothing)
TextLine(latex, anchor, h, v, use_font_style, wrap_width, justification) =
    TextLine(latex, anchor, h, v, use_font_style, wrap_width, justification, nothing)

# LaTeX is laid out by MathTeXEngine, which uses different metrics than LaTeX.
# Makie places the text origin at the aligned point of the text's bounding box,
# so we let LaTeX align its own box in the same way around the text origin.
function text_lines(str::LaTeXString, attr, glyph_range, halign::Real, valign::Real, justification, wrap_width, bold_at)
    v = isnan(valign) ? 0.0 : valign
    j = justification_fraction(justification, halign)
    if wrap_width > 0
        # Makie word wraps LaTeX strings, let LaTeX wrap them in a paragraph of the same width
        return [TextLine(latex_source(str, j, false), Point2d(0), halign, v, false, Float64(wrap_width), j)]
    end
    # MathTeXEngine breaks lines at `\\` (not at newline characters). If Makie
    # broke the text into lines, stack them in a tabular, so the text takes the
    # space Makie reserved for it.
    # (`\\` outside a tabular would also be a LaTeX error)
    multiline = count_line_breaks(attr, glyph_range) > 0 || occursin("\\\\", String(str))
    # LaTeX's fonts are usually wider or narrower than MathTeXEngine's, so the text
    # can't match Makie's extent exactly. Keep the justified edge where Makie put it
    # (e.g. the left edge of left justified text) so it aligns with surrounding text.
    return [TextLine(latex_source(str, j, multiline), justified_anchor(attr, glyph_range, j), j, v, false)]
end

"""
    count_line_breaks(attr, glyph_range)

Count the line breaks in Makie's layout of a text block, detected as jumps of
the baseline to a new line (down by more than the font size, back to the left).
Sub- and superscripts shift glyphs by less than that.
"""
function count_line_breaks(attr, glyph_range)
    fontsize = attr.text_scales[first(glyph_range)][2]
    n = 0
    prev = local_glyph_origin(attr, first(glyph_range))
    for gi in glyph_range
        o = local_glyph_origin(attr, gi)
        if o[2] < prev[2] - 0.8 * fontsize && o[1] < prev[1]
            n += 1
        end
        prev = o
    end
    return n
end

function text_lines(str::AbstractString, attr, glyph_range, halign::Real, valign::Real, justification, wrap_width, bold_at)
    j = justification_fraction(justification, halign)
    chars = collect(str)
    if length(chars) != length(glyph_range)
        # unexpected layout, anchor on the text origin
        return [TextLine(escape_latex(str), Point2d(0), halign, NaN, true)]
    end
    # Lines are split where Makie put them: at newlines and where word wrapping
    # moved the baseline
    fontsize = attr.text_scales[first(glyph_range)][2]
    baseline(i) = local_glyph_origin(attr, glyph_range[i])[2]
    lines = TextLine[]
    function finish_line(r)
        first_char = findfirst(i -> !isspace(chars[i]), r)
        first_char === nothing && return
        last_char = findlast(i -> !isspace(chars[i]), r)
        rr = r[first_char]:r[last_char]
        push!(lines, line_from_glyphs(escape_latex(String(chars[rr])), attr, glyph_range[rr], j))
        return
    end
    line_start = 1
    for i in eachindex(chars)
        if chars[i] == '\n'
            finish_line(line_start:(i - 1))
            line_start = i + 1
        elseif i > line_start && !isspace(chars[i]) && abs(baseline(i) - baseline(line_start)) > 0.5 * fontsize
            finish_line(line_start:(i - 1))
            line_start = i
        end
    end
    finish_line(line_start:length(chars))
    return lines
end

function text_lines(str::Makie.RichText, attr, glyph_range, halign::Real, valign::Real, justification, wrap_width, bold_at)
    basesize = Float64(to_ndim(Vec2d, attr.text_scales[first(glyph_range)], 0)[2])
    j = justification_fraction(justification, halign)
    if wrap_width > 0
        v = isnan(valign) ? 0.0 : valign
        return [TextLine(rich_to_latex(str, basesize, bold_at), Point2d(0), halign, v, true, Float64(wrap_width), j)]
    end
    # Split into lines like Makie does, each line keeps the formatting of the
    # spans it's part of. Makie lays out one glyph per character, which maps the
    # lines to their glyphs. (For rich text, newlines don't get a glyph.)
    lines = rich_lines(str)
    nchars = sum(l -> length(String(l)), lines)
    newline_glyphs = if nchars == length(glyph_range)
        0
    elseif nchars + length(lines) - 1 == length(glyph_range)
        1
    else
        -1
    end
    if newline_glyphs < 0
        # unexpected layout: let LaTeX align the whole text
        v = isnan(valign) ? 0.0 : valign
        return [TextLine(rich_to_latex(str, basesize, bold_at), Point2d(0), halign, v, true)]
    end
    result = TextLine[]
    start = first(glyph_range)
    for line in lines
        n = length(String(line))
        if !all(isspace, String(line))
            push!(result, line_from_glyphs(rich_to_latex(line, basesize, bold_at), attr, start:(start + n - 1), j))
        end
        start += n + newline_glyphs
    end
    return result
end

"""
    rich_lines(r::RichText)::Vector{RichText}

Split rich text at newlines. Each line is a `RichText` with the same structure
(and attributes) as the parts of `r` it contains. Sub/superscript pairs are not
split.
"""
rich_lines(s::AbstractString) = String.(split(s, '\n'))

function rich_lines(r::Makie.RichText)
    r.type in (:subsup, :leftsubsup) && return [r]
    lines = [Any[]]
    for child in r.children
        for (i, part) in enumerate(rich_lines(child))
            i > 1 && push!(lines, Any[])
            push!(lines[end], part)
        end
    end
    return [Makie.RichText(r.type, l...; r.attributes...) for l in lines]
end

"""
    rich_to_latex(r::RichText, basesize, bold_at = 600)

Translate Makie rich text into LaTeX. Super- and subscripts are typeset in text
mode (like Makie does), `color`, `font` and `fontsize` attributes are applied to
their span. `basesize` is the font size of the surrounding text, used to scale
explicit font sizes relative to it. Fonts with a weight of at least `bold_at`
are bold (see [`font_style_commands`](@ref)).
"""
rich_to_latex(s::AbstractString, basesize, bold_at = 600) = escape_latex(s)

function rich_to_latex(r::Makie.RichText, basesize, bold_at = 600)
    is_script = r.type in (:sup, :sub)
    # the size LaTeX uses at the start of this span (scripts are shrunk by LaTeX, like in Makie)
    current = is_script ? 0.66 * basesize : Float64(basesize)
    size = haskey(r.attributes, :fontsize) ?
        Float64(to_ndim(Vec2d, Makie._get_fontsize(r.attributes, Vec2f(current)), 0)[2]) : current
    content = if r.type === :subsup || r.type === :leftsubsup
        length(r.children) == 2 || error("subsup needs exactly two children (subscript and superscript)")
        cmd = r.type === :subsup ? "\\pgfmakiesubsup" : "\\pgfmakieleftsubsup"
        sub = rich_to_latex(r.children[1], 0.66 * size, bold_at)
        sup = rich_to_latex(r.children[2], 0.66 * size, bold_at)
        string(cmd, "{", sub, "}{", sup, "}")
    else
        join(rich_to_latex.(r.children, size, bold_at))
    end
    content = string(rich_attribute_commands(r.attributes, size / current, bold_at), content)
    if r.type === :sup
        return string("\\textsuperscript{", content, "}")
    elseif r.type === :sub
        return string("\\textsubscript{", content, "}")
    else
        return string("{", content, "}")
    end
end

function rich_attribute_commands(attributes, size_ratio, bold_at)
    cmds = ""
    if haskey(attributes, :color)
        c = RGBAf(to_color(attributes[:color]))
        cmds *= string("\\color[rgb]{", color_components(c), "}")
    end
    if haskey(attributes, :font)
        # the space terminates the control word
        cmds *= font_style_commands(attributes[:font], bold_at; reset = true) * " "
    end
    if haskey(attributes, :fontsize) && isfinite(size_ratio) && size_ratio > 0
        cmds *= string("\\pgfmakiefontscale{", fmt(size_ratio), "}")
    end
    return cmds
end

text_lines(str, attr, glyph_range, halign::Real, valign::Real, justification, wrap_width, bold_at) =
    text_lines(string(str), attr, glyph_range, halign, valign, justification, wrap_width, bold_at)

"""
    justified_anchor(attr, glyph_range, j)

The point on the vertical line through the text origin that is at fraction `j`
of the horizontal extent of Makie's layout of the block (in unrotated text
coordinates, relative to the text origin). Anchoring LaTeX text there with
horizontal alignment `j` keeps e.g. the left edge of left justified text in place.
"""
function justified_anchor(attr, glyph_range, j)
    xmin, xmax = glyph_x_extent(attr, glyph_range)
    isfinite(xmin) || return Point2d(0)
    return Point2d(xmin + j * (xmax - xmin), 0)
end

"Horizontal extent of the glyphs (origin to advance) in unrotated text coordinates."
function glyph_x_extent(attr, glyph_idxs)
    xmin = Inf
    xmax = -Inf
    for gi in glyph_idxs
        o = local_glyph_origin(attr, gi)
        adv = attr.glyph_extents[gi].hadvance * attr.text_scales[gi][1]
        xmin = min(xmin, o[1])
        xmax = max(xmax, o[1] + adv)
    end
    return xmin, xmax
end

"Glyph origin with the text rotation undone, i.e. with a horizontal baseline."
function local_glyph_origin(attr, gi)
    return Point2d((inv(attr.text_rotation[gi]) * Vec3d(attr.glyph_origins[gi]))[Vec(1, 2)])
end

function line_from_glyphs(latex, attr, glyph_idxs, j)
    local_origin(gi) = local_glyph_origin(attr, gi)
    first_origin = local_origin(first(glyph_idxs))
    xmin, xmax = glyph_x_extent(attr, glyph_idxs)
    anchor = Point2d(xmin + j * (xmax - xmin), first_origin[2])
    return TextLine(latex, anchor, j, NaN, true, NaN, j, attr.font_per_char[first(glyph_idxs)])
end

"Makes inline math in LaTeX strings display style, like MathTeXEngine. Local to the text."
const MATH_STYLE = "\\everymath{\\displaystyle}"

"""
    latex_source(str::LaTeXString)

LaTeXStrings used in Makie are usually math wrapped in `\$...\$`, which works as-is.
Unicode math characters are replaced by LaTeX commands (see [`to_latex`](@ref)).
"""
function latex_source(str::LaTeXString, justification::Real = 0.5, multiline::Bool = false)
    # Like in MathTeXEngine (and LaTeX), newline characters are just spaces
    src = to_latex(strip(replace(String(str), r"\s*\n\s*" => " ")); escape = false)
    # MathTeXEngine typesets math in display style (limits above/below operators,
    # full size fractions), LaTeX uses the smaller text style for inline math
    src = MATH_STYLE * src
    multiline || return src
    # `\\` separates the lines, which works as-is in a tabular. The lines are
    # justified like the text is aligned.
    col = justification < 0.25 ? "l" : justification > 0.75 ? "r" : "c"
    return string("\\begin{tabular}{@{}", col, "@{}}", src, "\\end{tabular}")
end

function draw_line(w::PGFWriter, screen::Screen, line::TextLine, pos, M::Mat2f, scale, color::RGBAf, font, stroke = (0, RGBAf(0, 0, 0, 0)))
    config = screen.config
    # M maps text coordinates (in units of the font size) to scene pixels (y-down):
    # xvec is the projected width of an em, yvec the projected (downward) height
    xvec, yvec = M[:, 1], M[:, 2]
    fx, fy = norm(xvec), norm(yvec)
    # uniformly scaled and rotated text can use `\pgftext`'s rotation, everything
    # else (stretched text, text projected in 3D) needs the full transformation
    conformal = isapprox(fx, fy; rtol = 1.0e-3) && abs(dot(xvec, yvec)) <= 1.0e-3 * fx * fy
    # stretched text is typeset at its height and stretched horizontally
    fontsize = conformal ? fx : fy
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
    style = line.use_font_style ? font_style_commands(something(line.font, font), screen.bold_at) : ""
    strokewidth, strokecolor = stroke
    has_stroke = has_visible_stroke(strokewidth, strokecolor)
    strokecmd = has_stroke ? begin_text_stroke(w, alpha(color) > 0, strokewidth, strokecolor) : ""
    content = string("\\color{pgfmakietext}", strokecmd, fontcmd, style, " ", line.latex)
    if isfinite(line.wrap_width)
        # wrap_width is in units of the font size, convert to the page
        width = line.wrap_width * fontsize / scale[1] * w.scale
        jcmd = line.justification < 0.25 ? "\\raggedright" : line.justification > 0.75 ? "\\raggedleft" : "\\centering"
        content = string("\\parbox{", fmt(width), "bp}{", jcmd, " ", content, "}")
    end
    aligned = if isnan(line.v)
        string("\\pgfmakiealign{", fmt(line.h), "}{", content, "}")
    else
        string("\\pgfmakiealignv{", fmt(line.h), "}{", fmt(line.v), "}{", content, "}")
    end
    if conformal
        rot = abs(angle) < 1.0e-3 ? "" : string(",rotate=", fmt(angle))
        emitln(w, "\\pgftext[left,base,at=", qpoint(w, pos), rot, "]{", aligned, "}")
    else
        # transform the typeset text itself: text coordinates (bp at `fontsize`) to PGF coordinates
        a, b = xvec[1] / fontsize, -xvec[2] / fontsize
        c, d = -yvec[1] / fontsize, yvec[2] / fontsize
        # `\\pgflowlevelsynccm` applies the complete current transformation
        # (including the scene's shift) to the text
        emitln(w, "\\begin{pgfscope}")
        emitln(w, "\\pgftransformcm{", fmt(a), "}{", fmt(b), "}{", fmt(c), "}{", fmt(d), "}{", qpoint(w, pos), "}")
        emitln(w, "\\pgflowlevelsynccm")
        emitln(w, "\\pgftext[left,base]{", aligned, "}")
        emitln(w, "\\end{pgfscope}")
    end
    has_stroke && end_text_stroke(w)
    # opacity is reset by the end of the plot's scope; reset the writer cache
    w.fill_color = nothing
    w.stroke_color = nothing
    return
end

"""
    font_style_commands(font, bold_at = 600; reset = false)

LaTeX commands for bold/italic fonts. `font` can be a font object, a font name or
a symbol like `:bold`. Fonts with a weight (see [`font_weight`](@ref)) of at least
`bold_at` are set in bold, since LaTeX fonts usually only have a regular and a
bold weight. With `reset = true`, regular weight and upright shape are set
explicitly (for rich text spans inside bold text).
"""
function font_style_commands(font, bold_at::Integer = 600; reset::Bool = false)
    style = font_style_string(font)
    bold = font_weight(style) >= bold_at
    italic = occursin("italic", style) || occursin("oblique", style)
    cmds = ""
    if bold
        cmds *= "\\bfseries"
    elseif reset
        cmds *= "\\mdseries"
    end
    if italic
        cmds *= "\\itshape"
    elseif reset
        cmds *= "\\upshape"
    end
    return cmds
end

"""
    font_weight(style)

The numeric weight (100 = thin, 400 = regular, 700 = bold, 900 = black) of a
font style name like `"SemiBold Italic"`, or of a font or font symbol.
"""
function font_weight(style::AbstractString)
    style = lowercase(replace(style, r"[\s_-]" => ""))
    return occursin("thin", style) || occursin("hairline", style) ? 100 :
        occursin("extralight", style) || occursin("ultralight", style) ? 200 :
        occursin("light", style) ? 300 :
        occursin("semibold", style) || occursin("demibold", style) ? 600 :
        occursin("extrabold", style) || occursin("ultrabold", style) ? 800 :
        occursin("black", style) || occursin("heavy", style) ? 900 :
        occursin("bold", style) ? 700 :
        occursin("medium", style) ? 500 : 400
end
font_weight(font) = font_weight(font_style_string(font))

"""
    base_font_weight(scene)

The most common font weight of the (non-LaTeX) text in `scene` and its children,
counting each string once. Text heavier than this is set in bold, so that the
contrast of the figure's fonts is kept: e.g. with AlgebraOfGraphics' theme the
base weight is Light (tick labels), and titles in Medium become bold, while in a
figure using Medium and Heavy only the Heavy text becomes bold. Ties go to the
lighter weight. Returns 400 (regular) if there is no text.
"""
base_font_weight(scene::Scene) = most_common_weight(figure_font_weights(scene))

"The font weights of the (non-LaTeX) text blocks in `scene` and its children."
function figure_font_weights(scene::Scene)
    weights = Int[]
    for p in Makie.collect_atomic_plots(scene; is_atomic_plot = is_pgf_atomic_plot)
        p isa Text || continue
        CairoMakie.check_parent_plots(plot -> to_value(get(plot, :visible, true)), p) || continue
        texts = p.attributes[:input_text][]
        blocks = p.attributes[:text_blocks][]
        fonts = p.attributes[:font_per_char][]
        for (i, block) in enumerate(blocks)
            (isempty(block) || texts[i] isa LaTeXString) && continue
            push!(weights, font_weight(fonts[first(block)]))
        end
    end
    return weights
end

"The most common weight in `weights`, preferring the lighter one on ties (400 if empty)."
function most_common_weight(weights)
    isempty(weights) && return 400
    counts = Dict{Int, Int}()
    for w in weights
        counts[w] = get(counts, w, 0) + 1
    end
    maxcount = maximum(values(counts))
    return minimum(w for (w, c) in counts if c == maxcount)
end

"""
    bold_threshold(screen)

The minimal font weight which is set in bold: `screen.config.bold_weight`, or
anything heavier than the base weight of the figure if that is `automatic`. If
all text in the figure has the same weight, SemiBold (600) and heavier is bold.
"""
function bold_threshold(screen::Screen)
    bw = screen.config.bold_weight
    bw isa Integer && return Int(bw)
    weights = figure_font_weights(screen.scene)
    # Without contrast between weights (e.g. a figure whose only text is a bold
    # title) there's nothing to preserve, use the usual absolute threshold
    length(unique(weights)) <= 1 && return 600
    return most_common_weight(weights) + 1
end

font_style_string(font::Symbol) = lowercase(string(font))
font_style_string(font::AbstractString) = lowercase(font)
function font_style_string(font)
    try
        return lowercase(font.style_name)
    catch
        return ""
    end
end
