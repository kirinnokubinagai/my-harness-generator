# UI / design

## Prohibited (AI-style)

Gradients (purple → blue → pink), neon / fluorescent colours, glow / blur / blob shapes, space / starfield / particle backgrounds, floating animations, 3D gradient spheres, decorative badges ("AI Powered", "Smart"), emoji inside the UI.

## Required (human-feel)

Solid colours; subtle tonal variations; light shadows (`shadow-sm` / `shadow-md`); clear borders (`border border-neutral-200`); straight lines + moderate border-radius; **Lucide Icons only** (`lucide-react`); action labels that say what happens ("Save", "Delete").

## Colour system

1 brand colour (primary) + 1 accent (secondary, sparingly) + neutral scale + semantic (success / error / warning / info). Prefer warm grays (stone scale) over pure gray.

## Accessibility (WCAG AA)

| Item | Requirement |
|---|---|
| Body text contrast | 4.5:1 |
| Large text (18pt+ / 14pt bold+) | 3:1 |
| Touch target | 44×44pt min (Fitts) |
| Keyboard nav | Visible focus ring; logical Tab order |
| `prefers-reduced-motion` | Always respected |
| `aria-label` | Required on icon-only buttons |

## UX psychology (shokasonjuku — apply all 10)

Hick's Law (one primary action per screen) · Fitts's Law (44×44pt+, thumb reach) · Miller's Law (groups of 7±2) · Jakob's Law (follow conventions) · Aesthetic-Usability Effect · Peak-End Rule · Doherty Threshold (≤ 400 ms) · Contrast · Keyboard · Reduced motion.

Reference: <https://www.shokasonjuku.com/ux-psychology>

## Icons (Lucide only)

```tsx
import { Check, AlertCircle, Loader2, Plus, Settings } from 'lucide-react';
<Check className="h-4 w-4 text-success" />
<Button><Plus className="h-4 w-4 mr-2" />Add</Button>
<Button variant="ghost" size="icon" aria-label="Settings"><Settings className="h-5 w-5" /></Button>
<Loader2 className="h-4 w-4 animate-spin" />
```

Sizes: inline `h-4 w-4`, button `h-4 w-4`–`h-5 w-5`, nav `h-5 w-5`–`h-6 w-6`.

## App icons

`favicon.ico` / `favicon.svg` / `apple-touch-icon.png` (180×180), `android-chrome-{192,512}.png`, `og-image.png` (1200×630). No gradients; recognisable at small sizes.
