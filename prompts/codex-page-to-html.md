You are converting an approved page-mock PNG into a self-contained Tailwind HTML file for the "<SCREEN_NAME>" screen of <PROJECT_NAME>, form factor `<FORM_FACTOR>` (`pc` = desktop / laptop viewport; `mobile` = smartphone viewport).

The page mock PNG is attached at the path below — open it with your file-read / image-input tool and use it as the pixel-level source of truth. **Do not invent a layout from the prompt alone**; the screen's actual structure is in the image.

Reference image:        `<PAGE_PNG>`
Parts directory:        `<root>/dev/docs/design/parts/<FORM_FACTOR>/<SCREEN_SLUG>/`
Output file:            `<OUT_HTML>`

---

## STYLE INVARIANTS (locked-in for the entire project — must match exactly)

```json
<STYLE_GUIDE_JSON>
```

Every color in the HTML MUST come from the palette above. Every illustration referenced via `<img>` MUST be one of the cropped PNGs from the parts directory (see manifest below). No new colors, no new typography choices beyond what's natural for Inter / Noto Sans JP.

---

## AVAILABLE CROPPED PARTS (use these via relative `<img src>`)

```json
<MANIFEST_JSON>
```

Each entry's `name` is the filename stem under `parts/<FORM_FACTOR>/<SCREEN_SLUG>/`. From the HTML file (which lives at `dev/docs/design/page-<FORM_FACTOR>-<SCREEN_SLUG>.html`) the relative path to a part is:

```
parts/<FORM_FACTOR>/<SCREEN_SLUG>/<name>.png
```

So an asset named `hero-illustration` becomes `<img src="parts/<FORM_FACTOR>/<SCREEN_SLUG>/hero-illustration.png" alt="..." class="...">`.

---

## REQUIRED HTML SCAFFOLD (use exactly this top-level structure)

```html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><SCREEN_NAME> — <PROJECT_NAME></title>
  <script src="https://cdn.tailwindcss.com"></script>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Noto+Sans+JP:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    body { font-family: 'Inter', 'Noto Sans JP', -apple-system, BlinkMacSystemFont, sans-serif; }
  </style>
</head>
<body class="bg-neutral-50 text-neutral-900 antialiased">
  <!-- markup that matches the reference PNG exactly -->
</body>
</html>
```

---

## MARKUP RULES

- **Tailwind utility classes only** — no custom CSS beyond the `<style>` block above. No external CSS files.
- **No JavaScript** — no `<script>` tags except the Tailwind CDN one. No event handlers.
- **No JS-loaded icon libraries** — for small icons, write a Lucide-style inline `<svg>` by hand. For larger custom graphics, use the cropped PNGs from the parts directory.
- **State variants** (hover / focus / disabled / active / selected) — Tailwind pseudo-class utilities (`hover:bg-primary-600`, `disabled:opacity-50`, etc.) plus `aria-*` attributes. One canonical element per UI piece — do NOT duplicate elements to show different states.
- **Realistic content** — never Lorem Ipsum, never "Title goes here". Match what's in the PNG. Japanese stays Japanese; English stays English.
- **Semantic HTML** — `<header>`, `<main>`, `<nav>`, `<section>`, `<article>`, `<footer>`, `<button>`, `<label>`, `<input>`, etc. used correctly. `aria-label` on icon-only buttons. `<a href="#">` for nav links (real routes get filled in at implementation time).
- **Decorative `<img>`** — `alt=""` + `aria-hidden="true"`.

## LAYOUT & RESPONSIVENESS

- Match the reference PNG's aspect ratio, column count, spacing, and component hierarchy as closely as you can in HTML.
- Page container max-width:
  - `<FORM_FACTOR>` == `pc` → `max-w-7xl` (1280 px) for app dashboards, narrower (`max-w-2xl`) for content-heavy pages
  - `<FORM_FACTOR>` == `mobile` → `max-w-[430px]`
- Mobile-first responsive utilities (`sm:`, `md:`, `lg:`) — even on `pc`, the page should degrade gracefully to mobile width.

## SELF-COMPLETENESS

The HTML must render correctly when opened directly via `file://` (no dev server, no build). That means:
- Tailwind CDN must load via the `<script>` tag.
- Fonts must load via the Google Fonts `<link>` tags.
- Image paths must resolve as relative URLs from `dev/docs/design/`.

---

## OUTPUT PROTOCOL

Write the complete HTML file to `<OUT_HTML>` using your file-write tool. After writing, your text response should be **one short confirmation sentence** ("Wrote page-<FORM_FACTOR>-<SCREEN_SLUG>.html with N components."). Do NOT paste the HTML body in your text response.
