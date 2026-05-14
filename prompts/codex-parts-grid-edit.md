$imagegen Use **edit mode** on the page mock you generated earlier in this same session for the "<SCREEN_NAME>" screen of <PROJECT_NAME> on <FORM_FACTOR> (file: `<root>/dev/docs/design/page-<FORM_FACTOR>-<SCREEN_SLUG>.png`). The page is already visible to you in conversation context — reference it as the edit input.

Produce ONE NEW image (do NOT modify the page itself): a parts-grid PNG that lays out the non-HTML assets from that page into a 4-column grid of 256×256 cells. Save it to:

`<root>/dev/docs/design/parts-grid-<FORM_FACTOR>-<SCREEN_SLUG>-<IMAGE_INDEX>.png`

This is grid number `<IMAGE_INDEX>` out of `<IMAGE_COUNT>` total grids for this screen.

---

## IMMUTABLE STYLE INVARIANTS — repeat to yourself before each pixel

These were locked in when you made the page. Echo them exactly here. **Do not reinterpret. Do not improvise.** Drift from these = failure.

```json
<STYLE_GUIDE_JSON>
```

Every asset you render in this grid MUST:
- use ONLY hex values from the palette above (no new colors)
- match `illustration_style` exactly (no shifting from flat → painterly etc.)
- match `line_weight` exactly
- match `character_design` exactly (same silhouette / posture / proportion language)
- match the `decorative_motifs` exactly

If you cannot recall the page's exact rendering of an asset, re-examine the page image (it is in your edit context — that is the entire point of edit mode) before drawing.

---

## CELLS TO PLACE IN THIS GRID

Render exactly these cells into a 4-column × `<ROWS_IN_THIS_IMAGE>`-row grid. Cell order is row-major (left to right, top to bottom). Each cell holds ONE asset.

```json
<CELLS_JSON>
```

Cell (row, col) coordinates are 0-indexed. Each asset is the asset of the **same `name`** that appeared on the page — render the same thing, in isolation, in its own 256×256 cell.

---

## STRICT LAYOUT RULES (the cropper depends on these)

- Exactly **4 columns** wide.
- `<ROWS_IN_THIS_IMAGE>` rows of 256-pixel-tall cells = image height of `<ROWS_IN_THIS_IMAGE> × 256` pixels.
- Image width = 1024 pixels (4 × 256).
- Each cell is exactly **256 × 256 px**. The asset occupies the central **224 × 224** area; the surrounding 16 px is padding.
- **Background of the entire image is FLAT, UNIFORM, pure `<CHROMA_KEY>` (exact hex).** Every background pixel must be `<CHROMA_KEY>`. No gradient, no noise, no texture.
- **Background↔asset boundary must be pixel-perfect aliased — NO anti-aliasing, NO blending.** Every pixel is EITHER exactly `<CHROMA_KEY>` OR a definite asset color. There must NEVER be an in-between pixel along the boundary.
- Do NOT add drop shadows, glows, or halos around assets — the chroma-key cropper will eat them.
- Below each cell, write the asset's `name` in **kebab-case** in a small **black** sans-serif font at the bottom of the cell, within the 16 px padding. The label color is black, NOT `<CHROMA_KEY>` and NOT any color from `<CHROMA_KEY>`'s visual family.
- Cells appear in the exact order given above. Do not reorder.

---

## OUTPUT

- Exactly one `image_gen` call producing the parts-grid PNG at the path above.
- One short text confirmation line ("Saved parts-grid-...-<IMAGE_INDEX>.png with N cells."). No long commentary.

If you cannot honor every style invariant, abort and say so plainly — do NOT generate a divergent image.

---

## NON-NEGOTIABLE QUALITY BAR — no compromise, no Claude fill-in

The cropper that consumes this grid is deterministic and unforgiving: it reads cells by row/column index, removes magenta via a mathematical alpha formula, and bakes the result into per-asset PNGs the implementation phase imports directly. There is no "Claude visual cleanup" step that fixes partial output. Defects ship.

Rules:

1. **Pure `<CHROMA_KEY>` background, every pixel.** Not "approximately magenta", not "magenta with subtle gradient texture", not "magenta everywhere except near the cells where it transitions". Every background pixel = exact `<CHROMA_KEY>` hex. The cropper's alpha formula `alpha = g - min(r, b) + 1` is mathematically only zero on pure (1, 0, 1) magenta — anything else leaves residue, and Claude will NOT clean that residue.

2. **Zero anti-aliasing at the magenta-asset boundary.** Every pixel along that boundary must be EITHER pure magenta OR a definite asset color, never an in-between blended pixel. If your renderer's default is to anti-alias, override it — render the boundary aliased / "pixelated". The cropper preserves softness INSIDE the asset (anti-aliased curves on asset interior are fine and desired), but the OUTER edge against magenta must be hard.

3. **No drop shadows, no glows, no soft halos around assets.** These produce semi-transparent pixels at the asset rim that the cropper either keeps (= visible glow on transparent background, looks broken) or eats (= visible asset truncation). Both are failure modes. Render assets as flat-edged objects with no atmospheric effects.

4. **Every listed cell must contain its named asset, faithfully reproduced from the page.** If `<CELLS_JSON>` lists 17 cells, the grid contains 17 cells — not 15 with "I forgot", not 20 with two extras "for completeness". Same name, same visual identity, same `kind`. The page mock in your edit-mode context IS the reference — match it exactly. If you cannot recall an asset's exact appearance, re-examine the page image before drawing.

5. **Exact 4-column × `<ROWS_IN_THIS_IMAGE>`-row layout, exact 256x256 cells.** Image width = 1024 px. Image height = `<ROWS_IN_THIS_IMAGE> × 256` px. Cell (r, c) occupies pixels `(256*c, 256*r)` to `(256*c+255, 256*r+255)`. Every asset fits inside the central 224x224 area; surrounding 16 px is padding. The cropper hardcodes these — drift = cropping picks up wrong pixels.

6. **No Claude completion assumed.** There is no step where Claude redraws a missing asset, fixes a misaligned cell, or repaints a shadow-corrupted boundary. Whatever you produce is what ships.

7. **If you cannot honor every constraint, ABORT.** Output ONE plain-text line `ABORT:` plus the specific reason (e.g. `ABORT: my renderer cannot disable anti-aliasing on shape boundaries; cropping will leave magenta-tinted rim pixels`). Do NOT ship a partially-compliant grid expecting downstream tooling to compensate.
