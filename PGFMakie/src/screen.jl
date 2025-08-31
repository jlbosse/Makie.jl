const LAST_INLINE = Ref{Union{Makie.Automatic,Bool}}(Makie.automatic)

# https://github.com/MakieOrg/MakieTeX.jl/blob/master/src/types.jl

"""
    PGFMakie.activate!()

Sets PGFMakie as the currently active backend
"""
function activate!(; inline=LAST_INLINE[], screen_config...)
    Makie.inline!(inline)
    LAST_INLINE[] = inline
    Makie.set_screen_config!(PGFMakie, screen_config)

    Makie.set_active_backend!(PGFMakie)
    return
end

#= based on CairoMakie screen
# TODO:
# - Add RenderType type parameter to Screen
=#
struct ScreenConfig1 end

const ScreenConfig = ScreenConfig1

mutable struct Screen <: Makie.MakieScreen
    scene::Scene
    texdoc::TEXDocument
    config::ScreenConfig
end

function Screen(scene::Scene; kw...)
    config = ScreenConfig()
    return Screen(scene, config)
end

function Screen(scene::Scene, config::ScreenConfig; kw...)
    texdoc = TEXDocument(L"hello world $\cos(x)$")
    return Screen(scene, texdoc, config)
end

function Base.size(screen::Screen)
end

function Base.empty!(screen::Screen)
end

# TODO: let this do something sensible
function Makie.px_per_unit(screen::Screen)::Float64
    return 72
end

# TODO: Pretty sure this shouldn't be a constant
function Base.isopen(screen::Screen)
    return false
end

# TODO: Pretty sure this should depend on config and scene
function Makie.apply_screen_config!(screen::Screen, config::ScreenConfig, scene::Scene, args...)
    return Makie.apply_screen_config!(screen, config, scene, nothing, MIME"image/png")
end

# TODO: Pretty sure this should depend on config and scene and the MIME type
function Makie.apply_screen_config!(
        screen::Screen,
        config::ScreenConfig,
        scene::Scene,
        io::Union{Nothing,IO}, m::MIME{SYM}
    ) where {SYM}
    return screen
end

function Base.show(io, ::MIME"text/plain", screen::Screen)
    println(io, "PGFMakie.Screen:")
    println(io, screen.texdoc.contents)
end

function Base.show(io, ::MIME"image/png", screen::Screen)
    FileIO.save(Stream(format"PNG", io), rasterize(Cached(screen.texdoc)))
end

# TODO: Update supported types
function Makie.backend_showable(::Type{Screen}, ::MIME{SYM}) where {SYM}
    return string(SYM) in ["image/png", "text/plain"]
end

# TODO: Make this depend on MIME type
function Makie.backend_show(screen::Screen)
    return screen
end

function Makie.backend_show(screen::Screen, io::IO, ::MIME"image/png", scene::Scene)
    img = colorbuffer(screen)
    px_per_unit = Makie.px_per_unit(screen)::Float64
    dpi = px_per_unit * 96 # attach dpi metadata corresponding to 1 unit == 1 CSS pixel
    FileIO.save(FileIO.Stream{FileIO.format"PNG"}(Makie.raw_io(io)), img; dpi)
    return
end

function Makie.colorbuffer(screen::Screen)
    pgf_draw(screen, screen.scene)
    # TODO: Do I need to take this detour via cached?
    cached = Cached(screen.texdoc)
    return rasterize(cached)
end

