################################################################################
#                                  PGF writer                                  #
################################################################################

# All PGF syntax is emitted through the functions in this file. Plot drawing
# code works in the local pixel space of the current (parent) scene, using the
# same y-down convention as CairoMakie, so that CairoMakie's projection helpers
# can be reused as-is. The writer converts these to PGF's y-up coordinates in
# units of `bp` (1/72 inch), scaled by `pt_per_unit`.

"""
    PGFWriter

Accumulates PGF code in an `IOBuffer`. Coordinates passed to the writer are in
Makie pixel units of the current scene, with y pointing down. `scale` is the
number of `bp` per Makie unit and `height` is the height of the current scene,
used to flip the y axis.
"""
mutable struct PGFWriter
    io::IOBuffer
    scale::Float64
    height::Float64
    # cache of the last set colors/opacities to avoid redundant commands within a scope
    fill_color::Union{Nothing, RGBAf}
    stroke_color::Union{Nothing, RGBAf}
end

PGFWriter(scale::Real) = PGFWriter(IOBuffer(), Float64(scale), 0.0, nothing, nothing)

# TeX can't handle dimensions larger than 16383.99998pt, so we clamp everything
# to a slightly smaller range. Anything this far out is invisible anyway.
const MAX_DIMENSION = 16000.0

"""
    fmt(x)

Format a number for TeX: fixed point notation, never scientific, never NaN/Inf,
clamped to the range TeX can represent. Trailing zeros are stripped.
"""
function fmt(x::Real)
    x = Float64(x)
    isnan(x) && return "0"
    x = clamp(x, -MAX_DIMENSION, MAX_DIMENSION)
    s = @sprintf("%.4f", x)
    # strip trailing zeros (keeps the output compact)
    if occursin('.', s)
        s = rstrip(s, '0')
        s = rstrip(s, '.')
    end
    s == "-0" && return "0"
    return s
end

"Format a length given in Makie units as a TeX dimension in bp."
dim(w::PGFWriter, x::Real) = string(fmt(x * w.scale), "bp")

"Format a point in y-down scene pixel space as a `\\pgfqpoint`."
function qpoint(w::PGFWriter, x::Real, y::Real)
    return string("\\pgfqpoint{", fmt(x * w.scale), "bp}{", fmt((w.height - y) * w.scale), "bp}")
end
qpoint(w::PGFWriter, p::VecTypes) = qpoint(w, p[1], p[2])

"Format a point in y-up scene pixel space (Makie's own convention) as a `\\pgfqpoint`."
function qpoint_up(w::PGFWriter, x::Real, y::Real)
    return string("\\pgfqpoint{", fmt(x * w.scale), "bp}{", fmt(y * w.scale), "bp}")
end

emit(w::PGFWriter, strs...) = (print(w.io, strs...); nothing)
emitln(w::PGFWriter, strs...) = (println(w.io, strs..., "%"); nothing)

# Paths

moveto(w::PGFWriter, p) = emitln(w, "\\pgfpathmoveto{", qpoint(w, p), "}")
lineto(w::PGFWriter, p) = emitln(w, "\\pgfpathlineto{", qpoint(w, p), "}")
function curveto(w::PGFWriter, c1, c2, p)
    return emitln(w, "\\pgfpathcurveto{", qpoint(w, c1), "}{", qpoint(w, c2), "}{", qpoint(w, p), "}")
end
closepath(w::PGFWriter) = emitln(w, "\\pgfpathclose")

"Rectangle given by its corner `(x, y)` and extent `(rw, rh)` in y-down pixel space."
function rectangle(w::PGFWriter, x, y, rw, rh)
    # PGF rectangles are specified as corner + extent in y-up space
    return emitln(w, "\\pgfpathrectangle{", qpoint(w, x, y + rh), "}{\\pgfqpoint{", fmt(rw * w.scale), "bp}{", fmt(rh * w.scale), "bp}}")
end

"Ellipse with center `c` and the two (y-down) axis vectors `a1`, `a2`."
function ellipse(w::PGFWriter, c, a1, a2)
    s = w.scale
    return emitln(
        w, "\\pgfpathellipse{", qpoint(w, c), "}{\\pgfqpoint{", fmt(a1[1] * s), "bp}{", fmt(-a1[2] * s),
        "bp}}{\\pgfqpoint{", fmt(a2[1] * s), "bp}{", fmt(-a2[2] * s), "bp}}"
    )
end

"""
    polyline(w, points; close = false)

Emit a path through `points` (y-down pixel space). NaN points split the path
into separate sub-paths.
"""
function polyline(w::PGFWriter, points; close = false)
    started = false
    for p in points
        if isnan(p)
            started && close && closepath(w)
            started = false
        elseif !started
            moveto(w, p)
            started = true
        else
            lineto(w, p)
        end
    end
    started && close && closepath(w)
    return
end

"""
    usepath(w, actions...)

Emit `\\pgfusepath{...}`, e.g. `usepath(w, :fill, :stroke)`.
"""
usepath(w::PGFWriter, actions::Symbol...) = emitln(w, "\\pgfusepath{", join(string.(actions), ","), "}")

# Scopes

function begin_scope(w::PGFWriter)
    emitln(w, "\\begin{pgfscope}")
    w.fill_color = nothing
    w.stroke_color = nothing
    return
end

function end_scope(w::PGFWriter)
    emitln(w, "\\end{pgfscope}")
    # colors are restored by the scope, so we can't know what's active anymore
    w.fill_color = nothing
    w.stroke_color = nothing
    return
end

function scope(f, w::PGFWriter)
    begin_scope(w)
    try
        f()
    finally
        end_scope(w)
    end
    return
end

# Styles

set_linewidth(w::PGFWriter, lw::Real) = emitln(w, "\\pgfsetlinewidth{", dim(w, lw), "}")

"""
    set_dash(w, pattern)

`pattern` is a vector of alternating on/off lengths in Makie units, or `nothing`
for solid lines.
"""
function set_dash(w::PGFWriter, pattern)
    if pattern === nothing || isempty(pattern) || all(iszero, pattern)
        return emitln(w, "\\pgfsetdash{}{0pt}")
    end
    parts = join(("{" * dim(w, max(0.0, p)) * "}" for p in pattern))
    return emitln(w, "\\pgfsetdash{", parts, "}{0pt}")
end

function set_linecap(w::PGFWriter, linecap)
    cap = linecap isa Symbol ? Makie.convert_attribute(linecap, Makie.key"linecap"()) : linecap
    if cap == 1
        return emitln(w, "\\pgfsetrectcap")
    elseif cap == 2
        return emitln(w, "\\pgfsetroundcap")
    else
        return emitln(w, "\\pgfsetbuttcap")
    end
end

function set_joinstyle(w::PGFWriter, joinstyle)
    join = joinstyle isa Symbol ? Makie.convert_attribute(joinstyle, Makie.key"joinstyle"()) : joinstyle
    if join == 2
        return emitln(w, "\\pgfsetroundjoin")
    elseif join == 3
        return emitln(w, "\\pgfsetbeveljoin")
    else
        return emitln(w, "\\pgfsetmiterjoin")
    end
end

"`limit` is the miter length / line width ratio (as for Cairo, PDF and PGF)."
set_miterlimit(w::PGFWriter, limit::Real) = emitln(w, "\\pgfsetmiterlimit{", fmt(max(1.0, limit)), "}")

set_eorule(w::PGFWriter) = emitln(w, "\\pgfseteorule")
set_nonzerorule(w::PGFWriter) = emitln(w, "\\pgfsetnonzerorule")

function color_components(c::Colorant)
    c = RGBAf(c)
    return string(fmt(clamp(red(c), 0, 1)), ",", fmt(clamp(green(c), 0, 1)), ",", fmt(clamp(blue(c), 0, 1)))
end

"Define a named xcolor color from `c` (alpha is ignored)."
define_color(w::PGFWriter, name::String, c::Colorant) = emitln(w, "\\definecolor{", name, "}{rgb}{", color_components(c), "}")

function set_fill(w::PGFWriter, c::Colorant)
    c = RGBAf(c)
    c == w.fill_color && return
    if w.fill_color === nothing || color(c) != color(w.fill_color)
        define_color(w, "pgfmakiefill", c)
        emitln(w, "\\pgfsetfillcolor{pgfmakiefill}")
    end
    if w.fill_color === nothing || alpha(c) != alpha(w.fill_color)
        emitln(w, "\\pgfsetfillopacity{", fmt(clamp(alpha(c), 0, 1)), "}")
    end
    w.fill_color = c
    return
end

function set_stroke(w::PGFWriter, c::Colorant)
    c = RGBAf(c)
    c == w.stroke_color && return
    if w.stroke_color === nothing || color(c) != color(w.stroke_color)
        define_color(w, "pgfmakiestroke", c)
        emitln(w, "\\pgfsetstrokecolor{pgfmakiestroke}")
    end
    if w.stroke_color === nothing || alpha(c) != alpha(w.stroke_color)
        emitln(w, "\\pgfsetstrokeopacity{", fmt(clamp(alpha(c), 0, 1)), "}")
    end
    w.stroke_color = c
    return
end

"Clip to the rectangle `(x, y, rw, rh)` given in y-down pixel space."
function clip_rect(w::PGFWriter, x, y, rw, rh)
    rectangle(w, x, y, rw, rh)
    return usepath(w, :clip)
end

# Outlined text. PDF strokes glyphs when the text rendering mode (`Tr`) is 1
# (stroke) or 2 (fill and stroke). `\pgfsys@invoke` writes the operator with
# whichever driver is active.

"""
    begin_text_stroke(w, fill_visible, strokewidth, strokecolor)

Set up stroked text for the next `\\pgftext`. Returns LaTeX code which must be
placed inside the text after any `\\color` (which sets the stroke color too).
Must be followed by [`end_text_stroke`](@ref).
"""
function begin_text_stroke(w::PGFWriter, fill_visible::Bool, strokewidth::Real, strokecolor::Colorant)
    strokecolor = RGBAf(strokecolor)
    set_linewidth(w, strokewidth)
    define_color(w, "pgfmakietextstroke", strokecolor)
    emitln(w, "\\pgfsetstrokeopacity{", fmt(clamp(alpha(strokecolor), 0, 1)), "}")
    emitln(w, "\\pgfsys@invoke{", fill_visible ? 2 : 1, " Tr}")
    w.stroke_color = nothing
    return "\\pgfsetstrokecolor{pgfmakietextstroke}"
end

end_text_stroke(w::PGFWriter) = emitln(w, "\\pgfsys@invoke{0 Tr}")

"Whether a text/marker stroke with this width and color is visible."
has_visible_stroke(strokewidth, strokecolor) = strokewidth > 0 && alpha(RGBAf(to_color(strokecolor))) > 0
