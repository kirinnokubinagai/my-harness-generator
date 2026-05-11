$imagegen You are designing the "<SCREEN_NAME>" screen of <PROJECT_NAME> on <PLATFORM>. Read the attached spec to understand what this screen does, then design with full creative freedom — visual style, palette, layout patterns, icon language are all your call.

Produce ONE page-mock PNG plus ONE OR MORE parts-grid PNGs in this single response (multiple `image_gen` tool calls), and end with a JSON manifest in your text response.

---

IMAGE — Full page mock (always 1 image)

Save to: `<root>/dev/docs/design/page-<PLATFORM>-<SCREEN_SLUG>.png`

- A complete <PLATFORM> mock of the "<SCREEN_NAME>" screen at the platform's natural aspect ratio.
- Realistic content (no Lorem Ipsum, no "Title goes here" placeholders).
- Use whatever resolution your tool's "high" setting produces.
- This image is the source of truth for what the implementation phase recreates in code.

---

IMAGES — PNG assets grid (zero, one, or several images, see Splitting below)

Each grid image catalogs **only the visual elements that CANNOT be recreated in HTML/CSS**. Buttons / inputs / cards / nav items / list rows / form controls / typography / library icons (Lucide, Heroicons) are ALL HTML-rendered, NOT in this grid.

**INCLUDE in the grid:**

- Custom illustrations (hero art, empty-state art, error-page art)
- Brand marks, logos, badges, mascot graphics
- Custom decorative graphics (background patterns, dividers, accents)
- Bespoke icons NOT in Lucide / common icon libraries
- Any visual element whose pixel detail matters (textures, gradient-as-image, hand-drawn shapes)

**EXCLUDE from the grid:**

- Buttons, inputs, dropdowns, checkboxes, switches, sliders
- Cards, list rows, table cells, modals, dialogs
- Nav bars, tab bars, breadcrumbs
- Standard typography (headings, body, labels)
- Icons from Lucide / Heroicons / similar libraries
- Any element that is "a colored box with text" — that is HTML

**Per-image layout (strict — the harness's cropping depends on these):**

- Exactly **4 columns** wide.
- **Maximum 7 rows per image** (so up to 28 assets per image — gpt-image-2 size limit).
- Each cell is exactly **256 × 256 pixels** with 16px padding inside (the asset occupies the central 224×224).
- Image width = 1024 px (= 4 × 256), height = rows × 256 px (max 1792 px = 7 × 256).
- **Background of the entire image is FLAT, UNIFORM, pure `<CHROMA_KEY>` (exact hex)** — this is the chroma-key color the cropper removes. CRITICAL rendering requirements for the background:
  - Every background pixel must be `<CHROMA_KEY>` exactly. No gradient. No noise. No texture. No subtle variation across the canvas.
  - **The background↔asset boundary must be pixel-perfect aliased — NO anti-aliasing, NO blending, NO smoothing.** Every pixel is EITHER exactly `<CHROMA_KEY>` background OR a definite asset color. There must NEVER be any in-between pixel along the boundary. Imagine rendering with `image-rendering: pixelated`. If your image tool cannot disable anti-aliasing directly, render assets at a higher internal resolution and then threshold/posterize the final result so the boundary becomes binary.
  - Do NOT add a drop shadow, glow, vignette, or any soft halo around assets — the cropper's chroma key cannot distinguish "intentional halo" from "anti-alias residue", so both will end up either as ugly key-color pixels in the cropped PNG or as eroded asset edges.

  This means **white pixels inside any asset are preserved as visible white** (clouds, paper, white logos, white snow, white speech bubbles all stay opaque white in the final transparent PNG). Do NOT use `<CHROMA_KEY>` or any near-`<CHROMA_KEY>` color (its visual family — e.g. pink-magenta / hot pink / fuchsia when the key is `#FF00FF`; pale green / lime / mint when the key is `#00FF00`) inside any asset, label, or accent — the key color is reserved exclusively for the background that will be removed. If the design requires colors from the key's color family, ask the user to pick a different key color before generating.
- Below each cell, write the asset's name in **kebab-case** in a small **black** sans-serif font (high contrast against the `<CHROMA_KEY>` background), positioned at the bottom of the cell (within the 16px padding zone is fine). Labels must NOT use `<CHROMA_KEY>` or any color from its visual family.

**Splitting across images:**

- If you have ≤ 28 assets → save **one** grid image to: `<root>/dev/docs/design/parts-grid-<PLATFORM>-<SCREEN_SLUG>-0.png`
- If you have 29-56 assets → save **two** grid images: `-0.png`, `-1.png`
- If you have 57-84 assets → save **three** grid images: `-0.png`, `-1.png`, `-2.png`
- … and so on. Each image carries up to 28 assets. Fill `-0.png` to 28, then start `-1.png`.
- Image suffix is always `-<N>.png` starting from `-0.png`, even when there is only one grid image.
- If you have **zero** non-HTML assets, skip the grid images entirely.

---

MANIFEST (text response, after all image_gen calls)

Output a single fenced JSON block in your text response — nothing else, no commentary around it:

```json
{
  "image_count": <integer>,
  "rows_per_image": [<integer>, ...],
  "cells": [
    { "image": 0, "row": 0, "col": 0, "name": "<kebab-case-name>" }
  ]
}
```

- `image_count`: number of parts-grid PNGs you produced (0 if no non-HTML assets).
- `rows_per_image[i]`: row count of the i-th grid image. Length equals `image_count`.
- `cells[].image`: 0-indexed grid-image index.
- `cells[].row` and `cells[].col`: 0-indexed within that image.
- `cells[].name`: matches the label visible below the cell, kebab-case.

If `image_count` is 0, `cells` is empty and `rows_per_image` is `[]`.
