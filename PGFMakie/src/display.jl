################################################################################
#                           Backend interface to Makie                         #
################################################################################

const PGF_MIME = MIME"application/x-pgf"
const TEX_MIME = MIME"application/x-tex"

const SUPPORTED_MIMES = Set(["application/x-pgf", "application/x-tex", "application/pdf", "image/png"])

Makie.backend_showable(::Type{Screen}, ::MIME{SYM}) where {SYM} = string(SYM) in SUPPORTED_MIMES

"""
    render!(screen)

Draw the scene of `screen` into its writer, collecting sidecar images.
"""
function render!(screen::Screen)
    empty!(screen)
    Makie.push_screen!(screen.scene, screen)
    pgf_draw(screen, screen.scene)
    return screen
end

function Makie.backend_show(screen::Screen, io::IO, ::PGF_MIME, scene::Scene, figure = nothing)
    render!(screen)
    save_sidecar_images(screen)
    write_picture(io, screen)
    return screen
end

function Makie.backend_show(screen::Screen, io::IO, ::TEX_MIME, scene::Scene, figure = nothing)
    render!(screen)
    save_sidecar_images(screen)
    write_document(io, screen)
    return screen
end

function Makie.backend_show(screen::Screen, io::IO, ::MIME"application/pdf", scene::Scene, figure = nothing)
    render!(screen)
    write(io, compile_pdf(screen))
    return screen
end

function Makie.backend_show(screen::Screen, io::IO, ::MIME"image/png", scene::Scene, figure = nothing)
    render!(screen)
    write(io, pdf_to_png(compile_pdf(screen), png_dpi(screen.config)))
    return screen
end

function save_sidecar_images(screen::Screen)
    isempty(screen.images) && return
    if screen.image_stem === nothing
        error(
            "This figure contains raster images (images, heatmaps or rasterized plots), which are " *
                "stored in separate PNG files next to the PGF output. This requires saving to a file, " *
                "e.g. `save(\"figure.pgf\", fig)`, rather than writing to a stream."
        )
    end
    return write_images(screen, dirname(screen.image_stem))
end

function Makie.colorbuffer(screen::Screen; figure = nothing)
    render!(screen)
    png = pdf_to_png(compile_pdf(screen), png_dpi(screen.config))
    img = PNGFiles.load(IOBuffer(png))
    return convert(Matrix{RGBA{Colors.N0f8}}, img)
end

function Base.display(screen::Screen, scene::Scene; figure = nothing, kw...)
    render!(screen)
    path = joinpath(mktempdir(), "display.pdf")
    write(path, compile_pdf(screen))
    screen.config.visible && CairoMakie.openurl("file:///" * path)
    return screen
end
