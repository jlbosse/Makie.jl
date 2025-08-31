# This is all stolen from MakieTex -- I should understand what is going on here!

# MakieTex/src/MakeTex.jl
# =============================================================================
"Render with Poppler pipeline (true) or Cairo pipeline (false)"
const RENDER_EXTRASAFE = Ref(false)
"The current `TeX` engine which MakieTeX uses."
const CURRENT_TEX_ENGINE = Ref{Cmd}(`lualatex`)
"Default margins for `pdfcrop`.  Private, try not to touch!"
const _PDFCROP_DEFAULT_MARGINS = Ref{Vector{UInt8}}([0,0,0,0])
"Default density when rendering images"
const RENDER_DENSITY = Ref(3)

# MakieTex/src/types.jl
# =============================================================================
"""
    abstract type AbstractDocument

An `AbstractDocument` must contain a document as a String or Vector{UInt8} of the full contents 
of whichever file it is using.  It may contain additional fields - for example, `PDFDocument`s 
contain a page number to indicate which page to display, in the case where a PDF has multiple pages.

`AbstractDocument`s must implement the following functions:
- `getdoc(doc::AbstractDocument)::Union{Vector{UInt8}, String}`
- `mimetype(doc::AbstractDocument)::Base.MIME`
- `Cached(doc::AbstractDocument)::AbstractCachedDocument`
"""
abstract type AbstractDocument end

# This will be documented elsewhere in the package.
struct TEXDocument <: AbstractDocument
    contents::String
    page::Int
end
TEXDocument(contents) = TEXDocument(contents, 0)
Cached(x::TEXDocument) = CachedTEX(x)
getdoc(doc::TEXDocument) = doc.contents
mimetype(::Type{TEXDocument}) = MIME"text/latex"()


"""
    TEXDocument(contents::AbstractString, add_defaults::Bool; requires, preamble, class, classoptions)

This constructor function creates a `struct` of type `TEXDocument` which can be passed to `teximg`.
All arguments are to be passed as strings.

If `add_defaults` is `false`, then we will *not* automatically add document structure.
Note that in this case, keyword arguments will be disregarded and `contents` must be
a complete LaTeX document.

Available keyword arguments are:
- `requires`: code which comes before `documentclass` in the preamble.  Default: `raw"\\RequirePackage{luatex85}"`.
- `class`: the document class.  Default (and what you should use): `"standalone"`.
- `classoptions`: the options you should pass to the class, i.e., `\\documentclass[\$classoptions]{\$class}`.  Default: `"preview, tightpage, 12pt"`.
- `preamble`: arbitrary code for the preamble (between `\\documentclass` and `\\begin{document}`).  Default: `raw"\\usepackage{amsmath, xcolor} \\pagestyle{empty}"`.

See also [`CachedTEX`](@ref), [`compile_latex`](@ref), etc.
"""
function TEXDocument(
            contents::AbstractString,
            add_defaults::Bool;
            requires::AbstractString = raw"\RequirePackage{luatex85}",
            class::AbstractString = "standalone",
            classoptions::AbstractString = "preview, tightpage, 12pt",
            preamble::AbstractString = raw"""
                        \usepackage{amsmath, xcolor}
                        \pagestyle{empty}
                        """,
        )
        if add_defaults
            return TEXDocument(
                """
                $(requires)

                \\documentclass[$(classoptions)]{$(class)}

                $(preamble)

                \\begin{document}

                $(contents)

                \\end{document}
                """
            )
        else
            return TEXDocument(contents)
        end
end
# Define dispatches for things known to be LaTeX in nature
TEXDocument(l::LaTeXString) = TEXDocument(l, true)

r"""
    texdoc(contents::AbstractString; kwargs...)

A shorthand for `TEXDocument(contents, add_defaults=true; kwargs...)`.

Available keyword arguments are:

- `requires`: code which comes before `documentclass` in the preamble.  Default: `raw"\\RequirePackage{luatex85}"`.
- `class`: the document class.  Default (and what you should use): `"standalone"`.
- `classoptions`: the options you should pass to the class, i.e., `\\documentclass[\$classoptions]{\$class}`.  Default: `"preview, tightpage, 12pt"`.
- `preamble`: arbitrary code for the preamble (between `\\documentclass` and `\\begin{document}`).  Default: `raw"\\usepackage{amsmath, xcolor} \\pagestyle{empty}"`.

"""
texdoc(contents; kwargs...) = TEXDocument(contents, true; kwargs...)


"""
    abstract type AbstractCachedDocument

Cached documents are "loaded" versions of AbstractDocuments, and store a pointer/reference to the 
loaded version of the document (a Poppler handle for PDFs, or Rsvg handle for SVGs).  

They also contain a Cairo surface to which the document has been rendered, as well as a cache of a 
rasterized PNG and its scale for performance reasons.  See the documentation of [`rasterize`](@ref)
for more.

`AbstractCachedDocument`s must implement the [`AbstractDocument`](@ref) API, as well as the following:
- `rasterize(doc::AbstractCachedDocument, [scale::Real = 1])::Matrix{ARGB32}`
- `draw_to_cairo_surface(doc::AbstractCachedDocument, surf::CairoSurface)`
- `update_handle!(doc::AbstractCachedDocument)::<some_handle_type>`
"""
abstract type AbstractCachedDocument <: AbstractDocument end


struct CachedTEX <: AbstractCachedDocument
    "The original `TEXDocument` which is compiled."
    doc::TEXDocument
    "The resulting compiled PDF"
    pdf::Vector{UInt8}
    "A pointer to the Poppler handle of the PDF.  May be randomly GC'ed by Poppler."
    ptr::Ref{Ptr{Cvoid}} # Poppler handle
    "A surface to which Poppler has drawn the PDF.  Permanent and cached."
    surf::CairoSurface
    "The dimensions of the PDF page, for ease of access."
    dims::Tuple{Float64, Float64}
end

getdoc(doc::CachedTEX) = getdoc(doc.doc)
mimetype(::Type{CachedTEX}) = MIME"text/latex"()

"""
    CachedTEX(doc::TEXDocument; kwargs...)

Compile a `TEXDocument`, compile it and return the cached TeX object.

A `CachedTEX` struct stores the document and its compiled form, as well as some
pointers to in-program versions of it.  It also stores the page dimensions.

In `kwargs`, one can pass anything which goes to the internal function `compile_latex`.
These are primarily:
- `engine = \`lualatex\`/\`xelatex\`/...`: the LaTeX engine to use when rendering
- `options=\`-file-line-error\``: the options to pass to `latexmk`.

The constructor stores the following fields:
    $(FIELDS)

!!! note
    This is a `mutable struct` because the pointer to the Poppler handle can change.
    TODO: make this an immutable struct with a Ref to the handle??  OR maybe even the surface itself...

!!! note
    It is also possible to manually construct a `CachedTEX` with `nothing` in the `doc` field, 
    if you just want to insert a pre-rendered PDF into your figure.
"""
CachedTEX(doc::TEXDocument; kwargs...) = cached_doc(CachedTEX, latex2pdf, doc; kwargs...)

function CachedTEX(str::String; kwargs...)
    return CachedTEX(implant_text(str); kwargs...)
end

function CachedTEX(x::LaTeXString; kwargs...)
    x = convert(String, x)
    return if first(x) == "\$" && last(x) == "\$"
        CachedTEX(implant_math(x[2:end-1]); kwargs...)
    else
        CachedTEX(implant_text(x); kwargs...)
    end
end

# do not rerun the pipeline on CachedTEX
CachedTEX(ct::CachedTEX) = ct
Base.show(io::IO, ct::CachedTEX) = _show(io, ct, "CachedTEX", "TEXDocument")

function _show(io, ct, x, y)
    if isnothing(ct.doc)
        println(io, x, "(no document, $(ct.ptr), $(ct.dims))")
    elseif length(ct.doc.contents) > 1000
        println(io, x, "(", y, "(...), $(ct.ptr), $(ct.dims))")
    else
        println(io, x, "($(ct.doc), $(ct.ptr), $(ct.dims))")
    end
end

function implant_math(str)
    return TEXDocument(
        """\\(\\displaystyle $str\\)""", true;
        requires = "\\RequirePackage{luatex85}",
        preamble = """
        \\usepackage{amsmath, amsfonts, xcolor}
        \\pagestyle{empty}
        \\nopagecolor
        """,
        class = "standalone",
        classoptions = "preview, tightpage, 12pt",
    )
end

function implant_text(str)
    return TEXDocument(
        String(str), true;
        requires = "\\RequirePackage{luatex85}",
        preamble = """
        \\usepackage{amsmath, amsfonts, xcolor}
        \\pagestyle{empty}
        \\nopagecolor
        """,
        class = "standalone",
        classoptions = "preview, tightpage, 12pt"
    )
end

"""
    update_handle!(doc::AbstractCachedDocument)

Update the internal handle/pointer to the loaded document in a `CachedDocument`, and returns it.

This function is used to refresh the handle/pointer to the loaded document in case it has been
garbage collected or invalidated. It should return the updated handle/pointer.

For example, in `CachedPDF`, this function would reload the PDF document using the `doc.doc` field
and update the `ptr` field with the new Poppler handle, **if it is found to be invalid**.

Note that this function needs to be implemented for each concrete subtype of `AbstractCachedDocument`,
as the handle/pointer type and the method to load/update it will be different for different document
types (e.g., PDF, SVG, etc.).
"""
function update_handle! end

function update_handle!(ct::CachedTEX)
    ct.ptr[] = load_pdf(ct.pdf)
    return ct.ptr[]
end

function cached_doc(T, f, doc; kwargs...)
    pdf = Vector{UInt8}(f(convert(String, doc); kwargs...))
    ptr = load_pdf(pdf)
    surf = page2recordsurf(ptr, doc.page)
    dims = (pdf_get_page_size(ptr, doc.page))

    ct = T(
        doc,
        pdf,
        Ref(ptr),
        surf,
        dims# .+ (1, 1),
    )

    return ct
end

mimetype(::T) where T <: AbstractDocument = mimetype(T)

Base.convert(::Type{String}, doc::AbstractDocument) = Base.convert(String, getdoc(doc))
Base.convert(::Type{UInt8}, doc::AbstractDocument) = Vector{UInt8}(Base.convert(String, doc))

Base.convert(::Type{Matrix{T}}, doc::AbstractDocument) where T <: Colors.Color = T.(Base.convert(Matrix{ARGB32}, doc))
Base.convert(::Type{Matrix{ARGB32}}, doc::AbstractDocument) = Base.convert(Matrix{ARGB32}, Cached(doc))
Base.convert(::Type{Matrix{ARGB32}}, cached::AbstractCachedDocument) = rasterize(doc)

Base.size(cached::AbstractCachedDocument) = cached.dims

# MakieTex/src/tex.jl
# =============================================================================
function rasterize(ct::CachedTEX, scale::Int64 = 1)
    raster = page2img(ct, ct.doc.page; scale=scale, render_density=5)
    return raster
    # return PermutedDimsArray(raster, (2, 1))
end

# The main compilation method - compiles arbitrary LaTeX documents
"""
    compile_latex(document::AbstractString; tex_engine = CURRENT_TEX_ENGINE[], options = `-file-line-error`)

Compile the given document as a String and return the resulting PDF (also as a String).
"""
function compile_latex(
    document::AbstractString;
    tex_engine = CURRENT_TEX_ENGINE[],
    options = `-file-line-error`
)

    use_tex_engine=tex_engine

    # Unfortunately for us, Latexmk (which is required for any complex LaTeX doc)
    # does not like to compile straight to stdout, OR take in input from stdin;
    # it needs a file. We make a temporary directory for it to output to,
    # and create a file in there.
    return mktempdir() do dir
        cd(dir) do

            # First, create the tex file and write the document to it.
            touch("temp.tex")
            path = "temp.pdf"
            file = open("temp.tex", "w")
            print(file, document)
            close(file)

            # Now, we run the latexmk command in a pipeline so that we can redirect stdout and stderr to internal containers.
            # First we establish these pipelines:
            out = Pipe()
            err = Pipe()

            try
                latex_cmd = `latexmk $options --shell-escape -cd -$use_tex_engine -interaction=nonstopmode temp.tex`
                latex = run(pipeline(ignorestatus(latex_cmd), stdout=out, stderr=err))
                suc = success(latex)
                close(out.in)
                close(err.in)
                if !isfile(path)
                    println("Latex did not write $(path)!  Using the $(tex_engine) engine.")
                    println("Files in temp directory are:\n" * join(readdir(), ','))
                    printstyled("Stdout\n", bold=true, color = :blue)
                    println(read(out, String))
                    printstyled("Stderr\n", bold=true, color = :red)
                    println(read(err, String))
                    error()
                end
            finally
                return crop_pdf(path)
            end
        end
    end
end


# JLB: changed this because it seemed to make more sense than what happens in MakieTex
compile_latex(document::TEXDocument; kwargs...) = compile_latex(String(getdoc(document)); kwargs...)

latex2pdf(args...; kwargs...) = compile_latex(args...; kwargs...)


# MakieTex/src/pdf.jl
# =============================================================================
"""
    page2img(ct::CachedTEX, page::Int; scale = 1, render_density = 1)

Renders the `page` of the given `CachedTEX` or `CachedTypst` object to an image, with the given `scale` and `render_density`.

This function reads the PDF using Poppler and renders it to a Cairo surface, which is then read as an image.
"""
function page2img(ct::CachedTEX, page::Int; scale = 1, render_density = 1)
    document = update_handle!(ct)
    page2img(document, page, size(ct); scale, render_density)
end

function page2img(document::Ptr{Cvoid}, page::Int, tex_dims::Tuple; scale = 1, render_density = 1)
    page = ccall(
        (:poppler_document_get_page, Poppler_jll.libpoppler_glib),
        Ptr{Cvoid},
        (Ptr{Cvoid}, Cint),
        document, page # page 0 is first page
    )

    w = ceil(Int, tex_dims[1] * render_density)
    h = ceil(Int, tex_dims[2] * render_density)

    img = fill(Colors.ARGB32(1,1,1,0), w, h)

    surf = CairoImageSurface(img)

    ccall((:cairo_surface_set_device_scale, Cairo.libcairo), Cvoid, (Ptr{Nothing}, Cdouble, Cdouble),
        surf.ptr, render_density, render_density)

    ctx  = Cairo.CairoContext(surf)

    Cairo.set_antialias(ctx, Cairo.ANTIALIAS_BEST)

    Cairo.save(ctx)
    # Render the page to the surface using Poppler
    ccall(
        (:poppler_page_render, Poppler_jll.libpoppler_glib),
        Cvoid,
        (Ptr{Cvoid}, Ptr{Cvoid}),
        page, ctx.ptr
    )

    Cairo.restore(ctx)

    Cairo.finish(surf)

    return (permutedims(img))

end

firstpage2img(ct; kwargs...) = page2img(ct, 0; kwargs...)

"""
    load_pdf(pdf::String)::Ptr{Cvoid}
    load_pdf(pdf::Vector{UInt8})::Ptr{Cvoid}

Loads a PDF file into a Poppler document handle.

Input may be either a String or a `Vector{UInt8}`, each representing the PDF file in memory.  

!!! warn
    The String input does **NOT** represent a filename!
"""
load_pdf(pdf::String) = load_pdf(Vector{UInt8}(pdf))

function load_pdf(pdf::Vector{UInt8})::Ptr{Cvoid} # Poppler document handle

    # Use Poppler to load the document.
    document = ccall(
        (:poppler_document_new_from_data, Poppler_jll.libpoppler_glib),
        Ptr{Cvoid},
        (Ptr{Cchar}, Csize_t, Cstring, Ptr{Cvoid}),
        pdf, Csize_t(length(pdf)), C_NULL, C_NULL
    )

    if document == C_NULL
        # JLB: Changed path to pdf here
        error("The document at $pdf could not be loaded by Poppler!")
    end

    num_pages = pdf_num_pages(document)

    if num_pages != 1
        @warn "There were $num_pages pages in the document!  Selecting first page."
    end

    # Try to load the first page from the document, to test whether it is valid
    page = ccall(
        (:poppler_document_get_page, Poppler_jll.libpoppler_glib),
        Ptr{Cvoid},
        (Ptr{Cvoid}, Cint),
        document, 0 # page 0 is first page
    )

    if page == C_NULL
        error("Poppler was unable to read page 1 at index 0!  Please check your PDF.")
    end

    return document

end

function page2recordsurf(document::Ptr{Cvoid}, page::Int; scale = 1, render_density = 1)
    w, h = pdf_get_page_size(document, page)
    page = ccall(
        (:poppler_document_get_page, Poppler_jll.libpoppler_glib),
        Ptr{Cvoid},
        (Ptr{Cvoid}, Cint),
        document, page # page 0 is first page
    )

    surf = Cairo.CairoRecordingSurface()

    ctx  = Cairo.CairoContext(surf)

    Cairo.set_antialias(ctx, Cairo.ANTIALIAS_BEST)

    # Render the page to the surface
    ccall(
        (:poppler_page_render, Poppler_jll.libpoppler_glib),
        Cvoid,
        (Ptr{Cvoid}, Ptr{Cvoid}),
        page, ctx.ptr
    )

    Cairo.flush(surf)

    return surf
end

firstpage2recordsurf(ct; kwargs...) = page2recordsurf(ct, 0; kwargs...)

function recordsurf2img(ct::CachedTEX, render_density = 1)

    # We can find the final dimensions (in pixel units) of the Rsvg image.
    # Then, it's possible to store the image in a native Julia array,
    # which simplifies the process of rendering.
    # Cairo does not draw "empty" pixels, so we need to fill here
    w = ceil(Int, ct.dims[1] * render_density)
    h = ceil(Int, ct.dims[2] * render_density)

    img = fill(Colors.ARGB32(0,0,0,0), w, h)

    # Cairo allows you to use a Matrix of ARGB32, which simplifies rendering.
    cs = Cairo.CairoImageSurface(img)
    ccall((:cairo_surface_set_device_scale, Cairo.libcairo), Cvoid, (Ptr{Nothing}, Cdouble, Cdouble),
    cs.ptr, render_density, render_density)
    c = Cairo.CairoContext(cs)

    # Render the parsed SVG to a Cairo context
    render_surface(c, ct.surf)

    # The image is rendered transposed, so we need to flip it.
    return rotr90(permutedims(img))
end

# MakieTex/src/pdf_utils.jl
# =============================================================================
"""
    pdf_num_pages(filename::String)::Int

Returns the number of pages in a PDF file located at `filename`, using the Poppler executable.
"""
function pdf_num_pages(filename::String)
    metadata = Poppler_jll.pdfinfo() do exe
        read(`$exe $filename`, String)
    end

    infos = split(metadata, '\n')

    ind = findfirst(x -> contains(x, "Pages"), infos)

    pageinfo = infos[ind]

    return parse(Int, split(pageinfo, ' ')[end])
end

"""
    pdf_num_pages(document::Ptr{Cvoid})::Int

`document` must be a Poppler document handle.  Returns the number of pages in the document.
"""
function pdf_num_pages(document::Ptr{Cvoid})
    ccall(
        (:poppler_document_get_n_pages, Poppler_jll.libpoppler_glib),
        Cint,
        (Ptr{Cvoid},),
        document
    )
end

"""
    get_pdf_bbox(path)

Get the bounding box of a PDF file using Ghostscript.
Returns a tuple representing the (xmin, ymin, xmax, ymax) of the bounding box.
"""
function get_pdf_bbox(path::String)
    !isfile(path) && error("File $(path) does not exist!")
    out = Pipe()
    err = Pipe()
    succ = success(pipeline(`$(Ghostscript_jll.gs()) -q -dBATCH -dNOPAUSE -sDEVICE=bbox $path`, stdout=out, stderr=err))

    close(out.in)
    close(err.in)
    result = read(err, String)
    if !succ
        println("Ghostscript failed to get the bounding box of $(path)!")
        println("Files in temp directory are:\n" * join(readdir(), ','))
        printstyled("Stdout\n", bold=true, color = :blue)
        println(result)
        printstyled("Stderr\n", bold=true, color = :red)
        println(read(err, String))
        error()
    end
    bbox_match = match(r"%%BoundingBox: ([-0-9.]+) ([-0-9.]+) ([-0-9.]+) ([-0-9.]+)", result)
    return parse.(Int, (
        bbox_match.captures[1],
        bbox_match.captures[2],
        bbox_match.captures[3],
        bbox_match.captures[4]
    ))
end

"""
    crop_pdf(path; margin = (0, 0, 0, 0))

Crop a PDF file using Ghostscript.  This alters the crop box but does not
actually remove elements.
"""
function crop_pdf(path::String; margin = _PDFCROP_DEFAULT_MARGINS[])
    # if pdf_num_pages("temp.pdf") > 1
    #     @warn("The PDF has more than 1 page!  Choosing the first page.")
    # end

    # Generate the cropping margins
    bbox = get_pdf_bbox(path)
    crop_box = (
        bbox[1] - margin[1],
        bbox[2] - margin[2],
        bbox[3] + margin[3],
        bbox[4] + margin[4]
    )
    crop_cmd = join(crop_box, " ")


    out = Pipe()
    err = Pipe()
    try
        redirect_stderr(err) do
            redirect_stdout(out) do
                Ghostscript_jll.gs() do gs_exe
                    run(`$gs_exe -o temp_cropped.pdf -sDEVICE=pdfwrite -c "[/CropBox [$crop_cmd]" -c "/PAGES pdfmark" -f $path`)
                end
            end
        end
    catch e
    finally
        close(out.in)
        close(err.in)
        if !isfile("temp_cropped.pdf")
            println("`gs` failed to crop the PDF!")
            println("Files in temp directory are:\n" * join(readdir(), ','))
            printstyled("Stdout\n", bold=true, color = :blue)
            println(read(out, String))
            printstyled("Stderr\n", bold=true, color = :red)
            println(read(err, String))
            error()
        end
    end

    return isfile("temp_cropped.pdf") ? read("temp_cropped.pdf", String) : read(path, String)
end

"""
    pdf_get_page_size(document::Ptr{Cvoid}, page_number::Int)::Tuple{Float64, Float64}

`document` must be a Poppler document handle.  Returns a tuple of `width, height`.
"""
function pdf_get_page_size(document::Ptr{Cvoid}, page_number::Int)

    page = ccall(
        (:poppler_document_get_page, Poppler_jll.libpoppler_glib),
        Ptr{Cvoid},
        (Ptr{Cvoid}, Cint),
        document, page_number # page 0 is first page
    )

    if page == C_NULL
        error("Poppler was unable to read the page with index $(page_number)!  Please check your PDF.")
    end

    width = Ref{Cdouble}(0.0)
    height = Ref{Cdouble}(0.0)

    ccall((:poppler_page_get_size, Poppler_jll.libpoppler_glib), Cvoid, (Ptr{Cvoid}, Ptr{Cdouble}, Ptr{Cdouble}), page, width, height)

    return (width[], height[])
end
