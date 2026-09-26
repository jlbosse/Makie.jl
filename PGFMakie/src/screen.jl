################################################################################
#                                 Screen setup                                 #
################################################################################

"""
* `px_per_unit::Float64 = 2.0`: resolution (pixels per Makie unit) used for rasterized
  content (images, heatmaps, fallbacks, `rasterize = true`) and for PNG output.
* `pt_per_unit::Float64 = 0.75`: size of one Makie unit in PostScript points (bp).
  The default matches CairoMakie's PDF output, i.e. a `Figure(size = (600, 450))`
  becomes a 450bp × 337.5bp picture.
* `tex_engine::String = "lualatex"`: LaTeX engine used to compile PDF and PNG output.
* `preamble::String = ""`: additional preamble inserted into the documents generated
  for `.tex`, `.pdf` and `.png` output. It is also shown as a comment in `.pgf` files.
* `set_fontsize::Bool = true`: if true, text is set in Makie's font size using `\\fontsize`.
  Otherwise the font size of the surrounding LaTeX document is used.
* `raster_fallback::Bool = true`: plots which can't be represented as PGF (3D meshes,
  surfaces, volumes, ...) are rasterized with CairoMakie. If false, they are skipped with a warning.
* `visible::Bool = true`: if true, `display` opens the compiled PDF in a viewer.
* `start_renderloop::Bool = false`: unused, only for compatibility with other backends.
"""
struct ScreenConfig
    px_per_unit::Float64
    pt_per_unit::Float64
    tex_engine::String
    preamble::String
    set_fontsize::Bool
    raster_fallback::Bool
    visible::Bool
    start_renderloop::Bool
end

const LAST_INLINE = Ref{Union{Makie.Automatic, Bool}}(Makie.automatic)

"""
    PGFMakie.activate!(; inline = automatic, screen_config...)

Sets PGFMakie as the currently active backend and also allows to quickly set the `screen_config`.
Note, that the `screen_config` can also be set permanently via `Makie.set_theme!(PGFMakie=(screen_config...,))`.

# Arguments one can pass via `screen_config`:

$(Base.doc(ScreenConfig))
"""
function activate!(; inline = LAST_INLINE[], screen_config...)
    Makie.inline!(inline)
    LAST_INLINE[] = inline
    Makie.set_screen_config!(PGFMakie, screen_config)
    Makie.set_active_backend!(PGFMakie)
    return
end

"""
Output target of a [`Screen`](@ref).
"""
@enum OutputType PGF TEX PDF PNG

function to_output_type(mime::MIME{SYM}) where {SYM}
    s = string(SYM)
    s == "application/x-pgf" && return PGF
    s == "application/x-tex" && return TEX
    s == "application/pdf" && return PDF
    s == "image/png" && return PNG
    error("PGFMakie can't produce output for MIME $(s)")
end

"""
    Screen(scene; screen_config...)

A PGFMakie screen. Drawing happens when the screen is shown/saved, all state is
regenerated each time.

# Arguments one can pass via `screen_config`:

$(Base.doc(ScreenConfig))
"""
mutable struct Screen <: Makie.MakieScreen
    scene::Scene
    config::ScreenConfig
    output::OutputType
    # path stem (without extension) used for sidecar images, e.g. `/path/to/fig`
    # for `/path/to/fig.pgf`. `nothing` if unknown (e.g. writing to an IOBuffer)
    image_stem::Union{Nothing, String}
    writer::PGFWriter
    # images to be written next to the output, as (filename, image) pairs.
    # The filename is relative to the directory of the output
    images::Vector{Pair{String, Matrix{RGBA{Colors.N0f8}}}}
end

function Screen(scene::Scene, config::ScreenConfig, output::OutputType = PNG, image_stem = nothing)
    writer = PGFWriter(config.pt_per_unit)
    return Screen(scene, config, output, image_stem, writer, Pair{String, Matrix{RGBA{Colors.N0f8}}}[])
end

function Screen(scene::Scene; screen_config...)
    config = Makie.merge_screen_config(ScreenConfig, Dict{Symbol, Any}(screen_config))
    return Screen(scene, config)
end

function Screen(scene::Scene, config::ScreenConfig, io::IO, mime::MIME)
    return Screen(scene, config, to_output_type(mime), image_stem_from_io(io))
end

Screen(scene::Scene, config::ScreenConfig, ::Makie.ImageStorageFormat) = Screen(scene, config, PNG)

"""
    image_stem_from_io(io)

When saving to a file, Makie passes an `IOStream` whose name is `"<file path>"`.
We use it to place sidecar images next to the output file.
"""
function image_stem_from_io(io::IO)
    io isa IOStream || return nothing
    m = match(r"^<file (.*)>$", io.name)
    m === nothing && return nothing
    return first(splitext(m.captures[1]))
end

function Makie.apply_screen_config!(screen::Screen, config::ScreenConfig, scene::Scene, io::IO, mime::MIME)
    return Screen(scene, config, io, mime)
end

function Makie.apply_screen_config!(screen::Screen, config::ScreenConfig, scene::Scene, args...)
    return Screen(scene, config)
end

Makie.px_per_unit(screen::Screen)::Float64 = screen.config.px_per_unit

Base.size(screen::Screen) = round.(Int, size(screen.scene) .* screen.config.px_per_unit)
Base.isopen(::Screen) = true
Base.close(::Screen) = nothing
function Base.empty!(screen::Screen)
    screen.writer = PGFWriter(screen.config.pt_per_unit)
    empty!(screen.images)
    return
end
# Everything is regenerated when the screen is shown, so there is nothing to do here
Base.insert!(::Screen, ::Scene, ::Makie.AbstractPlot) = nothing
Base.delete!(::Screen, ::Scene, ::Makie.AbstractPlot) = nothing
Base.resize!(::Screen, w, h) = nothing

function Base.show(io::IO, ::MIME"text/plain", screen::Screen)
    return print(io, "PGFMakie.Screen(", screen.output, ")")
end
