# PGFMakie Development Guide

PGFMakie is a Makie backend that writes figures as PGF code (like matplotlib's `backend_pgf`). All text is emitted as LaTeX. See the repository root `AGENTS.md` for general Makie development (scratch env, formatting, changelog).

## Architecture

| File | Role |
|---|---|
| `src/writer.jl` | `PGFWriter`: the **only** place that emits PGF syntax (paths, scopes, styles, colors, number formatting). |
| `src/screen.jl` | `ScreenConfig`, `Screen`, `activate!`, `apply_screen_config!`. |
| `src/display.jl` | `backend_show` for `.pgf`/`.tex`/`.pdf`/`.png`, `colorbuffer`, `display`. |
| `src/latex.jl` | LaTeX escaping, picture/document wrappers, helper TeX macros, compiling with the TeX engine, and PDF→PNG via `Poppler_jll.pdftocairo`. |
| `src/theme.jl` | `pgf_theme` / `set_pgf_theme!`: LaTeX-sized fonts, line widths, marker size and figure size (geometry only). |
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
- **`LaTeXString`.** Emitted verbatim. Vertically it is aligned by Makie's `align` around the text origin (`\pgfmakiealignv`), because MathTeXEngine's ink boxes don't match real LaTeX metrics. Horizontally it is anchored at the *justified* edge of Makie's glyph extent (`justified_anchor`). LaTeX text is usually wider or narrower than Makie's layout, and this keeps e.g. a left-justified `Label` (such as AlgebraOfGraphics' figure subtitle, which `Label` centers in a box of Makie's measured width) flush with the text above it. Rich text uses the same rule. Font style commands are skipped, because MathTeXEngine's fonts report italic.
- **MathTeXEngine decorations.** The `LineSegments` children of a `Text` plot with `LaTeXString` input (fraction bars etc.) are skipped by `is_tex_decoration`, because LaTeX draws them itself.
- **Rotation and font size.** Both come from the Jacobian returned by `CairoMakie.project_marker`, so text in any markerspace gets the right size and angle. Uniformly scaled, rotated text uses `\pgftext[rotate=…]`. Anything else (a `Vec2` fontsize, text projected in 3D) is typeset at its height and transformed with the full 2×2 matrix: `\pgftransformcm` in a scope followed by `\pgflowlevelsynccm`, because plain `\pgftext` ignores the coordinate transformation. (Not `\pgflowlevel`/`pgflowlevelscope`: those replace the current transformation instead of composing with it, which misplaces text in scenes away from the figure origin.)
- **Stroked text** (`text(...; strokewidth)`, `Char` markers with a stroke) uses the PDF text rendering mode, via `\pgfsys@invoke{2 Tr}` (`begin_text_stroke`/`end_text_stroke` in `writer.jl`). `\color` sets the stroke color too, so the stroke color has to be set again inside the text, after `\color`.
- **Display style math.** `LaTeXString`s get `\everymath{\displaystyle}` (`MATH_STYLE`), local to the text, because MathTeXEngine typesets math in display style.
- **Line breaks follow Makie's layout.**
  - Plain strings are split at `\n` and wherever the glyph baseline jumps (word wrap).
  - In `LaTeXString`s, MathTeXEngine breaks lines only at `\\`; newline characters are spaces, even in triple-quoted strings. PGFMakie does the same.
  - If Makie broke the text (detected by `count_line_breaks`) or the source contains `\\`, the text is put in a `tabular`, whose column follows the justification, so `\\` separates the rows. Never emit `\\` outside a tabular or paragraph: that's a LaTeX error.
- **Bold.** If all text in the figure has a single weight, there's no contrast to keep, and SemiBold (600) and heavier is bold (e.g. a figure whose only text is its bold title). Font weights come from style names (`font_weight`: Light 300, Medium 500, SemiBold 600, Bold 700, …). `render!` computes `screen.bold_at` once per render (`bold_threshold`). With `bold_weight = automatic` that is anything heavier than the most common weight of the figure's non-LaTeX text (`base_font_weight`); an `Int` is a fixed threshold. It's relative on purpose: AoG's theme uses Light and Medium, other figures use Medium and Heavy, and a fixed "Medium is bold" rule gets one of the two wrong.
- **Rich text line breaks.** Makie's rich-text layout creates *no glyph* for newlines, while plain strings do get one per newline. `text_lines(::RichText)` splits the tree with `rich_lines` and supports both cases. Each line uses the font of its own first glyph for bold/italic.
- **Word wrapping.** LaTeX and rich text with `word_wrap_width > 0` go into a `\parbox` of the equivalent width, and LaTeX does the wrapping.
- **Rich text** (`rich_to_latex`):
  - `superscript`/`subscript` become `\textsuperscript`/`\textsubscript`, like Makie's text-mode scripts. This is what log-scale tick labels like `10²` use.
  - `subsup`/`left_subsup` use the `\pgfmakiesubsup` macros.
  - Span `color`, `font` and `fontsize` are mapped; font size goes through `\pgfmakiefontscale`, relative to the size in effect.
- **Unicode** (`to_latex` in `latex.jl`). Greek letters, common operators and super/subscript characters become `\ensuremath{...}` commands, so they work with any engine and preamble; runs of script characters are merged. Other characters pass through. Other symbols from the math/symbol Unicode blocks (`is_math_symbol`, e.g. `◇`) are set as `\ensuremath{◇}`: text fonts usually lack them, math fonts have them. The default `preamble = automatic` loads `unicode-math` for LuaLaTeX and XeLaTeX (`resolved_preamble`).

## Testing

Work in the repo-level `.scratch` environment (see the root `AGENTS.md`), with ComputePipeline, Makie, CairoMakie and PGFMakie dev'ed. Then:

```julia
using PGFMakie, LaTeXStrings
include("PGFMakie/test/runtests.jl")   # ~5 min: compiles every figure with lualatex
```

- Besides unit tests (number formatting, escaping, unicode, rich text, font weights, inline display, sidecar names), the tests save a set of figures as `.pgf`, `.tex`, `.pdf` and `.png`, and check for:
  - no `NaN` and no scientific notation in the output
  - sidecar images that exist
  - the expected PNG size
- The LaTeX-compiling tests are skipped if `lualatex` isn't installed.
- **Visual check.** Compare `save("x.png", fig)` with `save("x_cairo.png", fig; backend = CairoMakie)`. Geometry and colors should match; fonts will differ. Build separate but identical figures for the two saves, so that neither backend reuses graph nodes the other already registered.
- **LaTeX documents.** Also check that the output works when `\input` into a real document, e.g. `\documentclass{article}\usepackage{pgf}` and then `\input{x.pgf}`, compiled with `pdflatex`.
- **Debugging LaTeX errors.** A failed compile raises `LaTeXError` with the tail of the log. To reproduce by hand, save as `.tex` and run the engine on it.

## Gotchas

- Sidecar image names come from the output file name. They must be LaTeX safe, so `emit_image` replaces everything except `[A-Za-z0-9_-]`: `\pgfimage` breaks on spaces and prints the filename as text.
- `image`'s default `uv_transform` is a vertical flip (`DEFAULT_IMAGE_UV_TRANSFORM` in `image.jl`), not the identity. Only that default is drawn as a direct image; other `uv_transform`s are rasterized by CairoMakie.
- Reference images: `render_refimages.jl` renders the ReferenceTests database with both backends into `PGFMakie/reference_images/` (gitignored). It is shardable, resumable and memory-capped; see the comment at its top. `compare_refimages.jl` flags pairs that differ a lot (after blurring, to ignore font differences) and writes `flagged/`, `flagged.txt` and `scores.csv`; pairs listed in `reference_images/reviewed.txt` were checked by hand and are listed separately. Both scripts currently live in the (gitignored) `.scratch/` folder and aren't versioned.
  - Rendering many figures in one process grows memory, so use `--heap-size-hint` and few workers: an earlier run with 3 unbounded workers got OOM-killed.
  - The workers are separate Julia processes and don't pick up code changes while running. After fixing something, delete the affected PGFMakie images and re-render them (only missing images are rendered).

- The first `save` in a fresh session takes over a minute to compile.
- `FileIO` has no `.pgf` or `.tex` formats. `__init__` registers them, guarded with `haskey(FileIO.sym2info, ...)`.
- Screen config defaults live in `Makie/src/theming.jl` under `PGFMakie = Attributes(...)`. `merge_screen_config` looks up every `ScreenConfig` field by name there, so each field needs a default with the same name. Adding a config field means editing both.
- **Theme** (`theme.jl`). `pgf_theme(; fontsize, tickfontsize, linewidth, thinwidth, markersize, textwidth, width_fraction, aspect)` takes TeX points and converts to Makie units with `x / pt_per_unit` (1 unit = 0.75 bp). Defaults: 10pt text, 8pt ticks, 4pt markers, 469.75pt text width, golden-ratio aspect. `set_pgf_theme!` is `Makie.update_theme!(pgf_theme(...))`, so it only changes these keys and works after `AlgebraOfGraphics.set_aog_theme!()`; a later `set_theme!`/`set_aog_theme!` resets them. Keep the theme geometry-only (no fonts, colors, palettes), and build it with `Theme`/`Attributes` so `update_theme!` merges nested `Axis`/`Legend`/`Colorbar` instead of replacing them. `Figure(size)` is the total outer size; axes shrink to fit labels and legends. Makie's unit is the bp, TeX's `pt` is 1/72.27 in, so widths are ~0.4% off unless scaled by `72 / 72.27`.
- Figures are also offered as Makie's web MIMEs (`SUPPORTED_MIMES` in `display.jl`), which embed the PNG in an `<img>` of the logical figure size. Without them, notebook frontends that ignore the PNG's dpi (VS Code) show figures at `px_per_unit` times the size. `to_output_type` maps the web MIMEs to PNG output.
- `julia tooling/formatter/format.jl` formats the whole repo and may touch unrelated files. Revert anything outside your change.

## Known limitations / TODO

- Makie lays text out with its own fonts, so LaTeX text can be wider or narrower than the space reserved for it. Upstream PR #5717 (pluggable `layout_text`, on the breaking branch) is the hook for measuring text with LaTeX.
- Rich text `offset` attributes are ignored.
- Open differences from the reference images: the Tooltip's dotted outline is black instead of red; "Float64 model with rotation" shows tick labels CairoMakie hides; perspective-projected 3D text comes out somewhat smaller than in CairoMakie; sub-pixel scatter markers look darker.
- Lines with per-vertex colors use one flat color per segment. Gradient bands and hatch patterns are rasterized.
- Scatter markers are one path each, except opaque unstroked markers of the same color, which are batched. `\pgfsys@defobject` markers would make large scatters faster.
