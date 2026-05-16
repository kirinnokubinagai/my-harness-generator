You just generated the page mock for the "<SCREEN_NAME>" screen of <PROJECT_NAME> (**<FORM_FACTOR>** form factor) in THIS Codex session. That image is in your conversation context — look at it.

## THIS IS A TEXT-ONLY TURN — do NOT call image_gen

Do **not** generate, edit, or regenerate any image this turn. Do **not** call `image_gen`. The page already exists from the previous turn. Your only job now is to **describe that exact image** as one JSON manifest. (Why this is a separate turn: Codex returns no text on an image_gen turn, so asking for the image and the JSON together silently produces neither. The image was turn 1; this is turn 2.)

<PRIOR_STYLE_GUIDE_BLOCK>

---

## OUTPUT: exactly one fenced ```json block, no commentary

Output exactly one fenced ` ```json ` block and nothing else around it (no preamble, no "Here is the manifest:", no trailing notes):

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
  "image_count": <integer — number of parts-grid PNGs needed in subsequent turns, = ceil(non_html_asset_count / 28); 0 if the page has no non-HTML assets>,
  "rows_per_image": [<int>, ...],
  "cells": [
    { "image": 0, "row": 0, "col": 0, "name": "<kebab-case>", "kind": "<illustration|mascot|brand-mark|decorative-graphic|bespoke-icon>" }
  ]
}
```

### style_guide rules

- **Describe the image you actually drew last turn.** Every hex must be a real color you can see in that page mock — sample it, do not invent a "nice" palette. `illustration_style`, `line_weight`, `character_design`, `decorative_motifs` must each be a concrete phrase describing what is actually in the image (write `"n/a — no characters in this project"` rather than leaving `character_design` vague).
- **If prior invariants were given above (`<PRIOR_STYLE_GUIDE_BLOCK>` non-empty):** echo them VERBATIM into the style_guide field. Do not paraphrase. Do not change a single hex. You inherited the project's locked-in visual identity last turn and drew with it; record it unchanged here so this manifest file stays self-contained for downstream tooling.
- **If no prior invariants (this is the first artifact of the project):** record the values you actually committed to in the image. These become the project's locked-in style_guide that every later screen AND the other form factor must honor.

### image_count / rows_per_image / cells rules

- `image_count`: `0` if the page has no non-HTML assets. Otherwise `ceil(non_html_asset_count / 28)`.
- `rows_per_image[i]`: row count of the i-th parts-grid image (4-column layout). Array length equals `image_count`.
- `cells[]`: one entry per non-HTML asset visible in the page mock. `kind` classifies it so the parts-grid prompt can reference it precisely.
- If `image_count` is `0`, omit `cells` and set `rows_per_image` to `[]`.

---

## What COUNTS as a non-HTML asset (becomes a cell)

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

---

## NON-NEGOTIABLE — no fabrication, no partial

1. **Every field filled with a real value** read off the actual image. `palette` lists 5 distinct roles, each a real 6-digit hex sampled from the mock. No `"TBD"`, no empty strings.
2. **No fabricated cells.** Every `cells[]` entry must correspond to an actual non-HTML asset you can point to in the page mock. A phantom cell (listed but not in the image) breaks parts-grid cropping.
3. **No fabricated counts.** `image_count = ceil(non_html_asset_count / 28)`. Count the assets in the image carefully. `0` ⇒ `cells` omitted, `rows_per_image: []`.
4. **No image_gen.** If you feel the urge to regenerate the page to "make the JSON match", STOP — the image is fixed; describe it as-is. Mismatch means describe what IS there, not what should be.
5. **If the image is genuinely unreadable or missing from context, ABORT.** Output ONE plain-text line beginning with `ABORT:` and the specific reason (e.g. `ABORT: the previous turn's page mock is not in my context — cannot describe an image I cannot see`). Do not invent a manifest for an image you cannot see.

Output the single ```json block now (or one `ABORT:` line). No image_gen. No other text.
