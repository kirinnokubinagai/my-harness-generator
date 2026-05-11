$imagegen You are designing the "<SCREEN_NAME>" screen of <PROJECT_NAME> on <PLATFORM>. Read the attached spec for what this screen does, then design with full creative freedom — visual style, palette, layout patterns, icon language are all your call.

In this **first turn** you produce ONE artifact: the full page mock PNG. The parts grid that catalogs the page's non-HTML assets is produced in **subsequent turns** using `image_gen`'s edit mode against this page — that is why pixel-perfect style consistency across calls is achievable. To make that consistency possible you must also output a JSON `style_guide` describing the exact design decisions you applied here, so they can be embedded verbatim into every later turn's prompt as invariants.

---

## OUTPUT 1: Full page mock (one `image_gen` call)

Save to: `<root>/dev/docs/design/page-<PLATFORM>-<SCREEN_SLUG>.png`

- Complete <PLATFORM> mock of "<SCREEN_NAME>" at the platform's natural aspect ratio.
- Realistic content (no Lorem Ipsum, no "Title goes here" placeholders).
- High-quality resolution — use the largest size your tool's high setting supports.
- This image is the source of truth: the implementation phase recreates its layout in code, and later turns of this same session use it as an edit-mode reference to produce style-matched parts.

## OUTPUT 2: JSON in text response

After the `image_gen` call, output exactly one fenced ` ```json ` block — nothing else, no commentary around it:

```json
{
  "style_guide": {
    "palette": [
      { "role": "primary",    "hex": "#xxxxxx" },
      { "role": "secondary",  "hex": "#xxxxxx" },
      { "role": "neutral_bg", "hex": "#xxxxxx" },
      { "role": "neutral_fg", "hex": "#xxxxxx" },
      { "role": "accent",     "hex": "#xxxxxx" }
    ],
    "illustration_style": "<one short phrase, e.g., 'flat geometric, no outlines, soft gradients'>",
    "line_weight": "<e.g., 'no outlines on shapes; only thin 1.5px strokes for accents'>",
    "character_design": "<e.g., 'rounded silhouettes, no facial details, friendly postures' OR 'n/a — no characters'>",
    "decorative_motifs": "<e.g., 'rounded squircles, soft drop shadows at 4px Y offset, 12px radii'>"
  },
  "image_count": <integer — how many parts-grid PNGs will be needed in subsequent turns (ceil(asset_count / 28))>,
  "rows_per_image": [<int>, ...],
  "cells": [
    { "image": 0, "row": 0, "col": 0, "name": "<kebab-case>", "kind": "<illustration|mascot|brand-mark|decorative-graphic|bespoke-icon>" }
  ]
}
```

Field rules:

- `style_guide.*` — fill from the actual choices you made for the page. These get echoed back as **immutable invariants** in every parts-grid turn so the grid matches the page exactly. Be specific (hex codes, concrete phrases) — vague entries cause drift.
- `image_count` — number of parts-grid PNGs to be produced in subsequent turns. `0` if the page has no non-HTML assets (buttons / inputs / cards / list rows / library icons are all HTML, NOT in the grid). Otherwise `ceil(non_html_asset_count / 28)`.
- `rows_per_image[i]` — row count of the i-th grid image, in 4-column layout. Length equals `image_count`.
- `cells[]` — one entry per non-HTML asset on the page (only). `kind` classifies what it is so the parts-grid prompt can reference it precisely.

If `image_count` is 0, omit `cells` and set `rows_per_image` to `[]`.

---

## What COUNTS as a non-HTML asset (included in the grid in later turns)

- Custom illustrations (hero art, empty-state art, error-page art)
- Brand marks, logos, badges, mascot graphics
- Custom decorative graphics (background patterns, dividers, accents)
- Bespoke icons NOT in Lucide / Heroicons / common libraries
- Any visual element whose pixel detail matters (textures, gradient-as-image, hand-drawn shapes)

## What DOES NOT count (HTML/CSS recreates these later)

- Buttons, inputs, dropdowns, checkboxes, switches, sliders
- Cards, list rows, table cells, modals, dialogs
- Nav bars, tab bars, breadcrumbs
- Standard typography (headings, body, labels)
- Icons from Lucide / Heroicons / similar libraries
- Any element that is "a colored box with text" — that is HTML
