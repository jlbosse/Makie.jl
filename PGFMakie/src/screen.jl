const LAST_INLINE = Ref{Union{Makie.Automatic, Bool}}(Makie.automatic)

# https://github.com/MakieOrg/MakieTeX.jl/blob/master/src/types.jl

"""
    PGFMakie.activate!()

Sets PGFMakie as the currently active backend
"""
function activate!(; inline = LAST_INLINE[], screen_config...)
    Makie.inline!(inline)
    LAST_INLINE[] = inline
    Makie.set_screen_config!(PGFMakie, screen_config)

    Makie.set_active_backend!(PGFMakie)
    return
end

mutable struct Screen1 <: Makie.MakieScreen
    scene::Scene
    data::String
    texdoc::TEXDocument
end

Screen = Screen1

function Base.size(screen::Screen)
end

function Base.empty!(screen::Screen)
end

function Makie.colorbuffer(screen::Screen)
    cached = Cached(screen.texdoc)
    return rasterize(cached)
end

