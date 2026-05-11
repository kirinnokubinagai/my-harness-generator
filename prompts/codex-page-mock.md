$imagegen You are designing the "<SCREEN_NAME>" screen of <PROJECT_NAME> for the **<FORM_FACTOR>** form factor:

- `pc`     → desktop / laptop viewport (~1280-1440 px wide). Multi-column where appropriate. Hover states matter. Keyboard navigation matters.
- `mobile` → smartphone viewport (~390 px wide). Single-column. Thumb-reachable CTAs at the bottom. Bottom or top nav bar, not sidebar.

Read the attached spec for what the screen does, then design with full creative freedom on the elements not constrained below.

<PRIOR_STYLE_GUIDE_BLOCK>

This turn produces ONE artifact: the full page mock PNG at the <FORM_FACTOR> layout. Subsequent turns in this same Codex session will produce the parts grid (via image_gen **edit mode** against this page) and — if applicable — the OTHER form factor's page mock (also inheriting these invariants). Everything you decide here gets locked in for the whole project, so be deliberate.

---

## OUTPUT 1: Full page mock (one image_gen call)

Save to: `<root>/dev/docs/design/page-<FORM_FACTOR>-<SCREEN_SLUG>.png`

- Complete <FORM_FACTOR> layout of "<SCREEN_NAME>" at the platform's natural aspect ratio.
- Realistic content (no Lorem Ipsum, no "Title goes here" placeholders).
- High-quality resolution — largest size your tool's high setting produces.
- This image is the source of truth: the implementation phase recreates its layout in HTML/CSS, and later turns of this same session use it as an edit-mode reference for parts.

## OUTPUT 2: JSON manifest in text response

After the image_gen call, output exactly one fenced ` ```json ` block — no commentary around it:

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

- **If prior invariants were given above (`<PRIOR_STYLE_GUIDE_BLOCK>` non-empty):** echo them VERBATIM into the style_guide field. Do not paraphrase. Do not change a single hex. Do not add a color "for accent". You are inheriting the project's locked-in visual identity — any drift breaks consistency across screens/form factors. The reason the prior style_guide is re-stated in the output manifest is so this file remains self-contained for downstream tooling.
- **If no prior invariants (this is the first artifact of the project):** decide every value freely. Pick choices that will work for BOTH form factors (pc AND mobile) since the OTHER form factor — and every later screen — will inherit these. Avoid pc-only or mobile-only tropes unless the brand genuinely demands them.

### image_count / rows_per_image / cells rules

- `image_count`: 0 if the page has no non-HTML assets (buttons / inputs / cards / list rows / library icons are all HTML, NOT in the grid). Otherwise `ceil(non_html_asset_count / 28)`.
- `rows_per_image[i]`: row count of the i-th grid image (4-column layout). Length equals `image_count`.
- `cells[]`: one entry per non-HTML asset on the page. `kind` classifies what it is so the parts-grid prompt can reference it precisely.
- If `image_count` is 0, omit `cells` and set `rows_per_image` to `[]`.

---

## What COUNTS as a non-HTML asset (becomes a cell in later parts-grid turns)

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
