# PGFMakie Development Guide

PGFMakie is a Makie backend that writes figures as PGF code (like matplotlib's `backend_pgf`). All text is emitted as LaTeX. See the repository root `AGENTS.md` for general Makie development (scratch env, formatting, changelog).

## Architecture

| File | Role |
|---|---|
| `src/writer.jl` | `PGFWriter`: the **only** place that emits PGF syntax (paths, scopes, styles, colors, number formatting). |
| `src/screen.jl` | `ScreenConfig`, `Screen`, `activate!`, `apply_screen_config!`. |
| `src/display.jl` | `backend_show` for `.pgf`/`.tex`/`.pdf`/`.png`, `colorbuffer`, `display`. |
| `src/latex.jl` | LaTeX escaping, picture/document wrappers, helper TeX macros, compiling with the TeX engine, and PDF→PNG via `Poppler_jll.pdftocairo`. |
| `src/render.jl` | Render loop (`pgf_draw`), per-scene scopes and clipping, background, `draw_plot` recursion, CairoMakie raster fallback, sidecar images. |
| `src/lines.jl`, `scatter.jl`, `text.jl`, `image.jl`, `poly.jl` | `draw_atomic` per plot type. |

The render loop mirrors `CairoMakie/src/plot-primitives.jl`.

## Key conventions

- **Coordinates.** Plot code works in the parent scene's local pixel space, **y-down**, exactly like CairoMakie, so that CairoMakie's projection and clipping helpers can be reused as they are.
  - Pass y-down points to `moveto`/`lineto`/`qpoint`. The writer flips them using `w.height` (the current scene height, set in `prepare_for_scene`) and scales by `pt_per_unit` into `bp`.
  - `qpoint_up` is for points that are already y-up.
- **Numbers.** Always go through `fmt`: fixed point, clamped to ±16000 (TeX's dimension limit is about 16383pt), and NaN becomes 0. Never interpolate raw Julia numbers into PGF, since `1e-5` or `NaN` breaks TeX.
- **Scopes.** Each scene gets one `pgfscope` (shift and clip). Each atomic plot gets its own `pgfscope`, opened in `draw_plot`. The writer caches the current fill and stroke colors to avoid redundant commands; `end_scope` resets the cache. Any code that sets opacity or color outside `set_fill`/`set_stroke` must reset `w.fill_color`/`w.stroke_color` itself (see `draw_line` in `text.jl`).
- **Reusing CairoMakie.** PGFMakie depends on CairoMakie and calls its internals directly, e.g. `CairoMakie.add_projected_line_points!`, `project_marker`, `clip_poly`, `project_polygon`, `image_grid!`, `size_model!` and `to_cairo_linestyle`. The monorepo pins versions, so this is fine.
- **Compute graph node names.** Plot attributes are a compute graph that is shared with CairoMakie. The raster fallback draws the same plot object with CairoMakie, so both backends register nodes on it.
  - Nodes registered under the same name as CairoMakie's must use **identical inputs**, or ComputePipeline errors with "Outputs already have a parent compute edge with different inputs".
  - Give PGFMakie-specific nodes a `:pgf_` prefix, e.g. `:pgf_attributes` or `:pgf_unclipped_blocks`. Text uses per-block clipping, while CairoMakie's `:unclipped_indices` for text is per glyph.
- **Atomic plots.** `is_pgf_atomic_plot` keeps `Poly`, `Band` and `Tricontourf` whole, and `draws_children(...) = false` stops `draw_plot` from also drawing their child plots. When adding an override for another recipe, define both methods.
- **Raster fallback.** The generic `draw_atomic(scene, screen, ::Plot)` calls `draw_rasterized`. It renders the plot with a `CairoMakie.Screen` the size of the scene, crops the result to its opaque content and registers a sidecar PNG through `emit_image`. Anything without a PGF method gets rasterized automatically.
- **Sidecar images.**
  - They are named `<stem>-img<N>.png`, where the stem comes from the `IOStream` name that Makie's `save` passes (`image_stem_from_io`). They are written next to the output file.
  - Streams without a file path (e.g. an `IOBuffer`) error if the figure contains raster content.
  - PDF and PNG output write them into the compile temp dir.

## Text

- Each line of text becomes `\pgftext[left,base,at=..., rotate=...]{\pgfmakiealign{h}{...}}`. The macros are defined in `PGF_MACROS` in `latex.jl`.
- **Plain strings.** The line is anchored on Makie's computed baseline, at the aligned point `j` of the line's extent (computed from `glyph_origins` and `hadvance`). LaTeX then shifts the text horizontally by `j × width`. This relies on a 1:1 match between the characters of the string and the glyphs; if they don't match, the text is anchored on the origin instead.
- **`LaTeXString`.** Emitted verbatim and anchored at the text origin, using Makie's `align` for both axes (`\pgfmakiealignv`), because MathTeXEngine's ink boxes don't match real LaTeX metrics. Font style commands are skipped, because MathTeXEngine's fonts report italic.
- **MathTeXEngine decorations.** The `LineSegments` children of a `Text` plot with `LaTeXString` input (fraction bars etc.) are skipped by `is_tex_decoration`, because LaTeX draws them itself.
- **Rotation and font size.** Both come from the Jacobian returned by `CairoMakie.project_marker`, so text in any markerspace gets the right size and angle.

## Testing

Work in the repo-level `.scratch` environment (see the root `AGENTS.md`), with ComputePipeline, Makie, CairoMakie and PGFMakie dev'ed. Then:

```julia
using PGFMakie, LaTeXStrings
include("PGFMakie/test/runtests.jl")   # ~2-3 min: compiles every figure with lualatex
```

- The tests save each figure as `.pgf`, `.tex`, `.pdf` and `.png`, and check for:
  - no `NaN` and no scientific notation in the output
  - sidecar images that exist
  - the expected PNG size
- The LaTeX-compiling tests are skipped if `lualatex` isn't installed.
- **Visual check.** Compare `save("x.png", fig)` with `save("x_cairo.png", fig; backend = CairoMakie)`. Geometry and colors should match; fonts will differ. Build separate but identical figures for the two saves, so that neither backend reuses graph nodes the other already registered.
- **LaTeX documents.** Also check that the output works when `\input` into a real document, e.g. `\documentclass{article}\usepackage{pgf}` and then `\input{x.pgf}`, compiled with `pdflatex`.
- **Debugging LaTeX errors.** A failed compile raises `LaTeXError` with the tail of the log. To reproduce by hand, save as `.tex` and run the engine on it.

## Gotchas

- The first `save` in a fresh session takes over a minute to compile.
- `FileIO` has no `.pgf` or `.tex` formats. `__init__` registers them, guarded with `haskey(FileIO.sym2info, ...)`.
- Screen config defaults live in `Makie/src/theming.jl` under `PGFMakie = Attributes(...)`. The fields must match `ScreenConfig` exactly, in the same order, because `merge_screen_config` fills them positionally. Adding a config field means editing both.
- `julia tooling/formatter/format.jl` formats the whole repo and may touch unrelated files. Revert anything outside your change.

## Known limitations / TODO

- Makie lays text out with its own fonts, so LaTeX text can be wider or narrower than the space reserved for it. Upstream PR #5717 (pluggable `layout_text`, on the breaking branch) is the hook for measuring text with LaTeX.
- `RichText` is emitted as plain text; sub/superscripts and per-span colors are dropped.
- Lines with per-vertex colors use one flat color per segment. Gradient bands and hatch patterns are rasterized.
- Scatter markers are one path each, except opaque unstroked markers of the same color, which are batched. `\pgfsys@defobject` markers would make large scatters faster.
