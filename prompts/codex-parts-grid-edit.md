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
