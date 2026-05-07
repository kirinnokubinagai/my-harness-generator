---
name: harness-design-rules
description: Prohibits AI-style design, requires Lucide Icons exclusively, mandates 10 key UX psychology principles from the shokasonjuku set of 47, and enforces WCAG AA compliance. Fires when the user says "implement UI", "design", "add a component", "choose colors", or similar.
---

# harness-design-rules

Applies to all UI and visual elements under the harness.

## Prohibited (AI-style elements)

- Gradients (especially purple → blue → pink)
- Neon colors / fluorescent colors
- Glow effects / excessive blur / blob shapes
- Space, starfield, or particle backgrounds
- Floating animations / 3D gradient spheres
- Decorative badges like "AI Powered", "Smart", "Intelligent"
- Emoji (especially inside UI)

## Required (human-feel design)

- Solid colors or subtle tonal variations
- Light shadows (`shadow-sm` / `shadow-md`)
- Clear borders (`border border-neutral-200`)
- Straight lines / moderate border-radius
- **Lucide Icons only** (`lucide-react`)
- Labels that directly describe the action (e.g. "Save", "Delete")

## Color system

1 brand color + 1 accent + neutral scale + semantic colors:

```ts
primary: 1 color + lightness variants (500 is the base)
secondary: 1 color (complementary or analogous — use sparingly)
neutral: 50–950 (text / backgrounds / borders)
semantic: success / error / warning / info
```

Prefer warm grays (stone scale) over pure gray.

## Accessibility (WCAG AA)

| Item | Requirement |
|------|-------------|
| Body text contrast | 4.5:1 minimum |
| Large text (18pt+ / 14pt bold+) | 3:1 minimum |
| Touch target size | 44×44pt minimum (Fitts's Law) |
| Keyboard navigation | Focus ring must not be removed; Tab order must be logical |
| `prefers-reduced-motion` | Must always be respected (disable animations) |
| `aria-label` | Required on icon-only buttons |

## 10 required UX psychology principles (from shokasonjuku's 47)

Reference: <https://www.shokasonjuku.com/ux-psychology>

1. **Hick's Law**: One primary action per screen
2. **Fitts's Law**: Touch targets 44×44pt+; CTAs within thumb reach
3. **Miller's Law**: Group items in sets of 7±2
4. **Jakob's Law**: Follow established conventions (avoid novel UI patterns)
5. **Aesthetic-Usability Effect**: Appearance matters — don't neglect it
6. **Peak-End Rule**: Put care into completion screens / success feedback
7. **Doherty Threshold**: Interaction feedback within 400ms
8. **Contrast**: WCAG AA required
9. **Keyboard**: Visible focus, logical order
10. **Reduced motion**: Respect it

## Icon conventions (Lucide only)

```tsx
import { Check, AlertCircle, Loader2 } from 'lucide-react';

<Check className="h-4 w-4 text-success" />
<Button><Plus className="h-4 w-4 mr-2" />Add</Button>
<Button variant="ghost" size="icon" aria-label="Settings"><Settings className="h-5 w-5" /></Button>
<Loader2 className="h-4 w-4 animate-spin" />
```

Sizes:
- Inline: `h-4 w-4`
- Inside button: `h-4 w-4` or `h-5 w-5`
- Navigation: `h-5 w-5` or `h-6 w-6`

## App icons

- favicon.ico / favicon.svg / apple-touch-icon.png (180×180)
- android-chrome-{192,512}.png
- og-image.png (1200×630)
- No gradients; keep shapes simple and recognizable at small sizes

## Checklist

- [ ] No emoji used in the UI
- [ ] No gradients / neon colors
- [ ] No icon library other than Lucide
- [ ] WCAG AA contrast verified
- [ ] `prefers-reduced-motion` handled
- [ ] `aria-label` on icon-only buttons
- [ ] Focus ring not removed
