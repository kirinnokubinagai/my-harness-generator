# UI / design

## Prohibited (AI-style elements)

- Gradients (especially purple → blue → pink)
- Neon / fluorescent colors
- Glow effects, excessive blur, blob shapes
- Space / starfield / particle backgrounds
- Floating animations, 3D gradient spheres
- Decorative badges like "AI Powered", "Smart", "Intelligent"
- Emoji inside the UI

## Required (human-feel)

- Solid colors, subtle tonal variations
- Light shadows (`shadow-sm` / `shadow-md`)
- Clear borders (`border border-neutral-200`)
- Straight lines, moderate border-radius
- **Lucide Icons only** (`lucide-react`)
- Action labels that say what happens ("Save", "Delete")

## Color system

1 brand colour (primary) + 1 accent (secondary, used sparingly) + neutral scale + semantic colours (success / error / warning / info). Prefer warm grays (stone scale) over pure gray.

## Accessibility (WCAG AA)

| Item | Requirement |
|---|---|
| Body text contrast | 4.5:1 |
| Large text (18pt+ / 14pt bold+) | 3:1 |
| Touch target | 44×44pt min (Fitts) |
| Keyboard nav | Visible focus ring; logical Tab order |
| `prefers-reduced-motion` | Always respected |
| `aria-label` | Required on icon-only buttons |

## UX psychology (10 of 47 — shokasonjuku)

Reference: <https://www.shokasonjuku.com/ux-psychology>

1. Hick's Law — one primary action per screen
2. Fitts's Law — touch targets 44×44pt+; CTAs in thumb reach
3. Miller's Law — group items in sets of 7±2
4. Jakob's Law — follow established conventions
5. Aesthetic-Usability Effect — visual care matters
6. Peak-End Rule — invest in completion / success feedback
7. Doherty Threshold — feedback within 400ms
8. Contrast (WCAG AA)
9. Keyboard (visible focus, logical order)
10. Reduced motion respect

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

- favicon.ico / favicon.svg / apple-touch-icon.png (180×180)
- android-chrome-{192,512}.png
- og-image.png (1200×630)
- No gradients; recognisable at small sizes
