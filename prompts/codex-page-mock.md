$imagegen You are designing the "<SCREEN_NAME>" screen of <PROJECT_NAME> for the **<FORM_FACTOR>** form factor:

- `pc`     → desktop / laptop viewport (~1280-1440 px wide). Multi-column where appropriate. Hover states matter. Keyboard navigation matters.
- `mobile` → smartphone viewport (~390 px wide). Single-column. Thumb-reachable CTAs at the bottom. Bottom or top nav bar, not sidebar.

Read the attached spec for what the screen does, then design with full creative freedom on the elements not constrained below.

<PRIOR_STYLE_GUIDE_BLOCK>

---

## THIS TURN PRODUCES EXACTLY ONE THING: the page mock PNG

This is an **image-only** turn. Call `image_gen` once, save the page mock, and stop. **Do NOT output a JSON manifest, a style_guide, or any structured text this turn** — a SEPARATE follow-up turn in this same session will ask you to describe the image you just made as JSON. Trying to do both in one turn is the exact failure mode we are avoiding: Codex returns no text on an image_gen turn, so a "JSON + image in one turn" request silently produces neither. Image now; JSON next turn.

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

## OUTPUT: Full page mock (one image_gen call)

Save to: `<root>/dev/docs/design/page-<FORM_FACTOR>-<SCREEN_SLUG>.png`

- Complete <FORM_FACTOR> layout of "<SCREEN_NAME>" at the platform's natural aspect ratio.
- Realistic content (no Lorem Ipsum, no "Title goes here" placeholders).
- High-quality resolution — largest size your tool's high setting produces.
- This image is the source of truth: the implementation phase recreates its layout in HTML/CSS, the next turn describes its style_guide + assets as JSON, and later turns of this same session use it as an edit-mode reference for parts.

The visual choices you make here — palette, illustration style, line weight, character design, decorative motifs, and every non-HTML asset you draw — are what the NEXT turn will record as the project's locked-in `style_guide` and `cells[]`. So be deliberate now: whatever you render is what gets locked in. There is no "I'll fix it when asked for JSON" — the JSON turn only *describes* this image, it cannot change it.

---

## NON-NEGOTIABLE QUALITY BAR — no compromise, no Claude fill-in

This page mock is the visual source of truth for the entire project. Downstream tooling (the JSON-manifest turn, parts-grid generation, HTML generation, implementation) reproduces or describes whatever you decide here. There is no human design review later that magically fixes weak choices, and there is no "Claude polish" step that silently corrects partial output.

Rules:

1. **Maximum completion on this one image_gen call.** Treat this as your only shot at the page. Use the highest-quality setting your tool exposes. Render the full page at its natural aspect ratio with every region populated by realistic content — no "Title goes here", no Lorem Ipsum, no greyed-out placeholders for "TBD" sections. If the screen has a header / footer / sidebar / bottom-nav, render all of them fully.

2. **No silent omissions.** Every region the spec implies must be drawn. A half-rendered page corrupts every downstream turn (the JSON turn will describe a broken image; parts-grid will crop nothing).

3. **No deferring detail.** Do not draw a rough block expecting to refine it later. Every later turn — the JSON manifest, every other screen, every other form factor, every parts-grid, every HTML conversion — inherits from this exact image. There is no "next turn" to redo this page.

4. **If you cannot honor a constraint, ABORT — do not ship a partial image.** If the screen's complexity genuinely exceeds what you can render at the required completeness, output ONE plain-text line beginning with `ABORT:` followed by the specific reason (e.g. `ABORT: cannot fit the requested sidebar nav items into 1280px wide without overlapping the main content area — need narrower or fewer items`). Do NOT generate a partial page hoping a later step glues it together — that is the failure mode we explicitly forbid. (An `ABORT:` line is the one allowed text output this turn.)

5. **No "Claude completion" assumed.** Whatever you leave blank, ambiguous, or wrong in the image propagates verbatim into the JSON turn and the parts-grid turns and corrupts them. There is no Claude normalization step.

If you understand this, make the one image_gen call now and save it to the path above. If anything in the spec or prior style_guide is ambiguous enough that you would have to guess, ABORT with a specific question instead of drawing.
