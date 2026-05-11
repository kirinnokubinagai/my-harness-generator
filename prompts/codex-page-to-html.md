You are converting an approved page-mock PNG into a self-contained Tailwind HTML file. Read the attached spec to understand what the screen does, look at the reference image at the path below, and produce **one HTML file**.

This is the **design-fidelity stage**, not the implementation stage. No JavaScript logic, no state, no event handlers, no React. Just markup and Tailwind classes that reproduce the visual exactly.

---

Reference image (look at this carefully):

`<PAGE_PNG>`

Output file path (write here, do NOT print the HTML in your text response):

`<OUT_HTML>`

Project: `<PROJECT_NAME>` — platform: `<PLATFORM>` — screen: `<SCREEN_SLUG>`

---

## Requirements

### Document scaffolding (use this exact structure)

```html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><SCREEN_SLUG> — <PROJECT_NAME></title>
  <script src="https://cdn.tailwindcss.com"></script>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Noto+Sans+JP:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    body { font-family: 'Inter', 'Noto Sans JP', -apple-system, BlinkMacSystemFont, sans-serif; }
  </style>
</head>
<body class="bg-neutral-50 text-neutral-900 antialiased">
  <!-- your page markup here -->
</body>
</html>
```

### Markup rules

- **Use Tailwind utility classes only** — no custom CSS classes beyond the `<style>` block above. No external CSS files.
- **No JavaScript whatsoever.** No `<script>` tags except the Tailwind CDN. No event handlers.
- **No icons libraries via JS** — Lucide etc. are not loaded. For icons, either:
  - use a Lucide-style inline `<svg>` written out by hand (preferred for small icons), or
  - reference a PNG asset from the parts manifest if Codex placed an icon there.
- **State variants** (hover, focus, disabled, active, selected) — express via Tailwind pseudo-class utilities (`hover:bg-primary-600`, `disabled:opacity-50`, etc.) and `aria-*` attributes. Do not duplicate elements just to show different states; one canonical element per UI piece.
- **Realistic content** — never use Lorem Ipsum, "Title goes here", or placeholder strings. Match what's in the reference image. Japanese content stays Japanese; English content stays English.
- **Semantic HTML** — use `<header>`, `<main>`, `<nav>`, `<section>`, `<article>`, `<footer>`, `<button>`, `<label>`, `<input>`, etc. correctly. Add `aria-label` on icon-only buttons. Use `<a href="#">` for navigation links (real routes are added at implementation time).

### Asset usage rules (THE critical part)

A `manifest.json` attached at the end lists every non-HTML asset for this screen (custom illustrations, brand marks, decorative graphics, bespoke icons). Each asset is a transparent PNG cropped to 256×256.

- **Reference each asset relatively** — from the HTML file's location at `dev/docs/design/`, the parts directory is `../../public/design/parts/<PLATFORM>/<SCREEN_SLUG>/`. So the `<img>` src for a part named `hero-illustration` is:
  ```html
  <img src="../../public/design/parts/<PLATFORM>/<SCREEN_SLUG>/hero-illustration.png" alt="..." class="...">
  ```
- **Use parts only for non-HTML assets** — illustrations, brand marks, decorative graphics, bespoke icons that don't exist in standard libraries. Everything else (buttons, inputs, dropdowns, cards, list rows, nav items, modals, standard typography, library icons) must be **plain Tailwind markup**, NOT an `<img>`.
- **Display size** — if a part is rendered at a larger size than 256×256 in the page (e.g., a 1200px-wide hero illustration), reference its upscaled variant if present in the manifest. Otherwise, use the 256×256 version with appropriate Tailwind size classes — the implementation phase will swap in an upscaled asset.
- **Decorative-only `<img>`** — set `alt=""` and `aria-hidden="true"` on assets that are purely decorative.

### Layout & responsiveness

- **Match the reference image's aspect ratio and structure exactly.** Same column count, same spacing, same component hierarchy.
- **Set a sensible max-width** for the page container based on platform:
  - `web` → `max-w-7xl` (1280px) for app dashboards, `max-w-2xl` for content-heavy pages
  - `ios` / `android` → `max-w-[430px]` (mobile-only width)
  - `desktop` → `max-w-7xl`
- **Mobile-first responsive utilities** (`sm:`, `md:`, `lg:`) — even on `web`, design degrades gracefully to mobile width.

### Self-completeness

The HTML must render correctly when opened directly in a browser via `file://` (no dev server). That means:
- Tailwind CDN must load (single `<script>` tag).
- Fonts must load (Google Fonts links).
- Image paths must work as relative URLs.

---

## Output protocol

Write the complete HTML file to `<OUT_HTML>` using the file_write tool (or whatever file-writing capability is available in this session). After writing, your text response should be **one short sentence confirming the path**, nothing else. Do not paste the HTML body in the text response.
