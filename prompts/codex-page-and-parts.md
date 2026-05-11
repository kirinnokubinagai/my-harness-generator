$imagegen You are designing the "<SCREEN_NAME>" screen of <PROJECT_NAME> on <PLATFORM>. Read the attached spec to understand what this screen does, then design with full creative freedom — visual style, palette, layout patterns, icon language are all your call.

Produce **two separate PNG images** in this one response (two `image_gen` tool calls) AND a JSON manifest in your text response.

---

IMAGE 1 — Full page mock

Save to: `<root>/dev/docs/design/page-<PLATFORM>-<SCREEN_SLUG>.png`

- A complete <PLATFORM> mock of the "<SCREEN_NAME>" screen at the platform's natural aspect ratio.
- Realistic content (not Lorem Ipsum, no "Title goes here" placeholders).
- Use whatever resolution your tool's "high" setting produces.
- Render every UI element at its correct visual hierarchy. This image is the source of truth for what the implementation phase recreates in code.

---

IMAGE 2 — PNG assets grid

Save to: `<root>/dev/docs/design/parts-grid-<PLATFORM>-<SCREEN_SLUG>.png`

This image catalogs **only the visual elements that CANNOT be recreated in HTML/CSS**. The implementation phase will recreate buttons / inputs / cards / nav items / list rows / form controls / typography in code using Tailwind — those are NOT in this grid.

**INCLUDE in this grid:**

- Custom illustrations (hero art, empty-state art, error-page art)
- Brand marks, logos, badges, mascot graphics
- Custom decorative graphics (background patterns, dividers, accents)
- Bespoke icons that are NOT in the Lucide / common icon libraries
- Any visual element whose pixel detail matters (textures, gradients-as-images, hand-drawn shapes)

**EXCLUDE from this grid:**

- Buttons, inputs, dropdowns, checkboxes, switches, sliders — HTML primitives
- Cards, list rows, table cells, modals, dialogs — HTML containers
- Nav bars, tab bars, breadcrumbs — HTML structure
- Standard typography (headings, body text, labels)
- Icons from Lucide / Heroicons / similar libraries — those load from the package
- Any element that is "a colored box with text inside" — that is HTML, not a PNG asset

**Grid layout (strict — the harness's cropping script depends on these):**

- Exactly **4 columns** wide.
- Number of rows = ⌈number_of_assets / 4⌉.
- Each cell is exactly **256 × 256 pixels**, with 16px transparent padding inside (the asset itself occupies the central 224×224 area).
- Total image dimensions: width = 1024 px (= 4 × 256), height = rows × 256 px.
- Background of the entire image is solid white (#FFFFFF). This is the color that the cropper will flood-fill into transparency.
- Below each cell, write the asset's name in kebab-case (e.g., "hero-illustration", "empty-state-art", "brand-mark", "decorative-divider"). Use a simple sans-serif at a readable size, positioned at the bottom of the cell (within the 16px padding zone is fine).

---

MANIFEST (text response, after the two image_gen calls)

Output a single fenced JSON block in your text response — nothing else, no commentary around it:

```json
{
  "rows": <integer, total row count>,
  "cells": [
    { "row": 0, "col": 0, "name": "<kebab-case asset name>" },
    { "row": 0, "col": 1, "name": "<kebab-case asset name>" }
  ]
}
```

- `row` and `col` are 0-indexed.
- `name` matches the label visible below each cell.
- Include every cell that has an asset. If a row is partially filled (e.g., 3 assets in the last row), only include the cells that have assets — omit the empty cells.

---

If there are zero non-HTML assets in this screen (the screen is entirely buttons / inputs / cards / typography), generate IMAGE 1 only, skip IMAGE 2, and output `{ "rows": 0, "cells": [] }` as the manifest.
