$imagegen You are designing the "<SCREEN_NAME>" screen of <PROJECT_NAME> for the **<FORM_FACTOR>** form factor:

- `pc`     → desktop / laptop viewport (~1280-1440 px wide). Multi-column where appropriate. Hover states matter. Keyboard navigation matters.
- `mobile` → smartphone viewport (~390 px wide). Single-column. Thumb-reachable CTAs at the bottom. Bottom or top nav bar, not sidebar.

Read the attached spec for what the screen does, then design with full creative freedom on the elements not constrained below.

<PRIOR_STYLE_GUIDE_BLOCK>

---

## SHARED CHROME — header / footer / sidebar / bottom-nav must be IDENTICAL across screens

The project's "chrome" — the navigation and frame elements that wrap each page's main content — must be visually identical on every screen of this project. Specifically, these are SHARED, not per-screen:

- **Header**: logo (position, size, mark vs wordmark), top-level nav labels and their order, right-side action area (search, notifications, profile avatar), any top-of-page utility band.
- **Footer**: column structure, link groups and their order, copyright line, social icon row.
- **Sidebar** (when present on pc): logo / brand block at top, primary nav item list and order, active-state visual, collapse / expand affordance, secondary footer block at bottom.
- **Bottom-nav** (when present on mobile): tab count, labels, icon style, active-state visual.

Rules for THIS turn:

- **If this is the FIRST screen of the project** (no prior style_guide / chrome exists): design the chrome thoughtfully, knowing every later screen will inherit it pixel-for-pixel. Pick choices that read well on BOTH `pc` AND `mobile` layouts. Avoid form-factor-specific tropes unless the brand demands them.

- **If a prior screen exists in this Codex session** (you can see its page mock in your edit-mode context, OR `<PRIOR_STYLE_GUIDE_BLOCK>` is non-empty): the chrome from that screen is LAW. Reproduce it pixel-for-pixel in this screen — same logo, same nav order, same labels, same right-side actions, same footer columns, same sidebar / bottom-nav. The ONLY area you may redesign is the **main content region** between the chrome elements. Drift in any chrome detail (a renamed nav item, a moved icon, a different footer link, a recolored sidebar selection) breaks project-wide design consistency and is a failure of this turn.

If you cannot recall an exact chrome detail from the prior screen, re-examine its page image in edit-mode context BEFORE drawing — that is the entire point of edit-mode chaining.

Per-form-factor adaptation is permitted ONLY for affordances that are intrinsically per-form-factor (e.g. mobile collapses the desktop sidebar into a hamburger; mobile uses a bottom-nav where desktop uses a left-side nav). The CONTENT of those navs (labels, order, icons) must still match between form factors.

---

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

---

## NON-NEGOTIABLE QUALITY BAR — no compromise, no Claude fill-in

This page mock is the visual source of truth for the entire project. Downstream tooling (parts-grid generation, HTML generation, implementation) will reproduce whatever you decide here pixel-for-pixel. There is no human design review later that magically fixes weak choices, and there is no "Claude polish" step that silently corrects partial output.

Rules:

1. **Maximum completion on the first call.** Treat this as your only shot. Use the highest-quality setting your tool exposes. Render the full page at its natural aspect ratio with every region populated by realistic content — no "Title goes here", no Lorem Ipsum, no greyed-out placeholders for "TBD" sections. If the screen has a header / footer / sidebar / bottom-nav, render all of them fully.

2. **No silent omissions.** Every field of the JSON manifest must be filled with a real value. `style_guide.palette` must list 5 distinct roles, each with a real 6-digit hex. `illustration_style`, `line_weight`, `character_design`, and `decorative_motifs` must each be a concrete phrase, not "TBD" or "n/a unless …" — even when there are no characters, write "n/a — no characters in this project" so downstream tooling sees an explicit decision.

3. **No fabricated cells.** Every entry in `cells[]` must correspond to an actual non-HTML asset you rendered on the page. If you list a cell, it must point to a pixel-region in the page mock you can re-render in a subsequent parts-grid turn. Phantom cells (listed but never drawn) break cropping.

4. **No fabricated counts.** `image_count` is `ceil(non_html_asset_count / 28)`. Count carefully. If `image_count` is 0, `cells` must be omitted and `rows_per_image` must be `[]`.

5. **No Claude completion assumed.** Do NOT think "Claude will normalize this later". There is no Claude normalization step. Whatever fields you leave blank, ambiguous, or wrong will propagate verbatim into the next prompt and corrupt the parts-grid turn.

6. **If you cannot honor a constraint, ABORT — do not ship partial.** If the screen's complexity genuinely exceeds what you can render at the required completeness, output ONE plain-text line beginning with `ABORT:` followed by the specific reason (e.g. `ABORT: cannot fit the requested sidebar nav items into 1280px wide without overlapping the main content area — need narrower or fewer items`). Do NOT generate a partial page and a partial manifest hoping Claude will glue it together — that is the failure mode we are explicitly forbidding.

7. **No "I'll do better next turn" deferrals.** This turn produces the page that locks in the project's visual identity. Every later turn — every other screen, every other form factor, every parts-grid, every HTML conversion — inherits from this one. There is no "next turn" to redo this.

If you understand this, proceed. If anything in the spec or prior style_guide is ambiguous enough that you would have to guess, ABORT with a specific question.
