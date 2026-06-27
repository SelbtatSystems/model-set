# Design System: Furniture Collections List

> **Scope.** Single source of truth for the Furniture Collections storefront UI.
> Documents **what exists in the build**, not aspiration — every value below is
> traceable to a token, CSS class, or component. This is an *example* DESIGN.md:
> a luxury e-commerce browse experience, desktop-first with a mobile-first
> foundation. Use it as the shape/voice target when synthesizing a real one.
>
> **Source assets analyzed:** `styles/tokens.css`, `styles/globals.css`,
> `tailwind.config.js`, `components/{ProductCard,Nav,Filters}.tsx`, and rendered
> screenshots of the Collections, Product, and Cart screens (light + dark).

---

## 0. Verbatim authoritative blocks

Conventions that must **not** be paraphrased or re-decided per screen.

### Icons
Use one set: **Lucide** (`lucide-react`). Stroke icons only, 24×24,
`stroke="currentColor"` so color follows CSS — never recolor by editing fills.
Never hand-draw bespoke decorative SVGs. Browse: https://lucide.dev/icons

### Functional-state language
Reserve the three functional colors (§3) for system feedback only — stock,
errors, info. Never use them decoratively; the brand accent (Teal-Navy) carries
all intentional emphasis.

---

## 1. Visual Theme & Atmosphere

A **sophisticated, minimalist sanctuary** — Scandinavian restraint married to
luxury editorial presentation. The interface feels **spacious and tranquil**:
breathing room and clarity above all, gallery-like and photography-first so each
piece reads as an individual art object. **Airy yet grounded** — aspirational but
approachable, utilitarian in its restraint and elegant in execution.

**Key characteristics**
- Expansive whitespace; generous breathing room between elements
- Clean architectural grid; structured content blocks
- Photography-first, minimal UI interference
- Whisper-soft hierarchy that guides without shouting
- Refined, understated interactive elements

---

## 2. Foundations

### 2.1 Type scale & rhythm
- **Root:** 16px. All sizes in `rem`.
- **Family:** Manrope (geometric humanist sans), system-ui fallback.
- **Scale:** H1 2.75–3.5rem · H2 2–2.5rem · H3 1.5–1.75rem · Body 1rem ·
  Meta 0.875rem.
- **Line-height:** headings 1.15–1.25; body 1.7 (relaxed, for long descriptions).
- **Vertical rhythm:** 2rem base between related blocks; 5–8rem between major
  sections.

### 2.2 Scale tokens
```
Spacing : --space-1 .5rem · -2 1rem · -3 1.5rem · -4 2rem · -6 3rem · -8 5rem   (8px base, multiples only)
Radius  : --radius-input .5rem (8px) · --radius-card .75rem (12px) · --radius-full 9999px
Shadow  : flat by default · --shadow-hover 0 2px 8px rgba(0,0,0,0.06)           (whisper-soft, hover only)
Trans   : --t-fast 200ms ease · --t-normal 250ms ease-in-out
Touch   : --touch-min 44px
```

---

## 3. Color Palette & Roles

Each color: **descriptive name** + (hex) + functional role. Names are the
contract — reference them, not the raw hex, in component prose.

### 3.1 Raw palette
- **Warm Barely-There Cream** (#FCFAFA) — primary background; imperceptible warmth, more inviting than pure white.
- **Crisp Very Light Gray** (#F5F5F5) — secondary surface; card and content-area backgrounds.
- **Deep Muted Teal-Navy** (#294056) — sole brand accent; primary CTAs, active nav, selected filters, focus.
- **Charcoal Near-Black** (#2C2C2C) — primary text; headlines, product names. Softer than pure black.
- **Soft Warm Gray** (#6B6B6B) — secondary text; body, descriptions, metadata.
- **Ultra-Soft Silver Gray** (#E0E0E0) — borders, dividers, placeholders.

### 3.2 Semantic tokens — light / dark / role
| Semantic var | Light | Dark | Role |
|---|---|---|---|
| `--background` | `#FCFAFA` Cream | `#1A1816` warm charcoal | Page background |
| `--surface` | `#FFFFFF` | `#211F1D` | Cards, panels, modals |
| `--surface-alt` | `#F5F5F5` | `#2A2725` | Layered content areas |
| `--text-primary` | `#2C2C2C` | `#F2F0ED` | Headlines, product names |
| `--text-secondary` | `#6B6B6B` | `#B6B2AD` | Body, descriptions, meta |
| `--accent` | `#294056` | `#7FA8C9` (lightened for dark contrast) | CTAs, active nav, focus |
| `--accent-text` | `#FFFFFF` | `#1A1816` | Text/icon on accent fills |
| `--border` | `#E0E0E0` | `rgba(242,240,237,0.14)` | Dividers, hairline card borders |

### 3.3 Functional states (system feedback only)
- **Success Moss** (#10B981) — in stock, confirmations.
- **Alert Terracotta** (#EF4444) — low stock, errors.
- **Informational Slate** (#64748B) — neutral system messages.

### 3.4 Contrast (WCAG AA, quantified)
Verify every text/bg pair against rendered values; quote the ratio.
- Charcoal #2C2C2C on Cream #FCFAFA → **~13:1** (AAA).
- Soft Warm Gray #6B6B6B on Cream → **~5.1:1** (AA, body text passes).
- White on Teal-Navy #294056 (CTA label) → **~11:1** (AAA).
- Dark mode: `--text-secondary #B6B2AD` on `--background #1A1816` → **~7.6:1** (AAA).

---

## 4. Typography Rules

- **H1 (display):** Semi-bold 600, letter-spacing 0.02em, 2.75–3.5rem. Hero / major titles, used sparingly.
- **H2 (section):** Semi-bold 600, 0.01em, 2–2.5rem. Content zones, featured collections.
- **H3 (subsection):** Medium 500, normal spacing, 1.5–1.75rem. Product names, category labels.
- **Body:** Regular 400, line-height 1.7, 1rem. Descriptions prioritize comfortable reading.
- **Meta:** Regular 400, line-height 1.5, 0.875rem. Prices, availability — legible but recessive.
- **CTA label:** Medium 500, 0.01em, 1rem. Present without aggression.

Headers carry slightly expanded tracking for refinement; body stays at relaxed
1.7 for effortless reading.

---

## 5. Component Stylings

Anchor each component to its descriptive values; note the shape + color role, not
just raw numbers.

### Buttons
- **Shape:** subtly rounded corners (8px / `--radius-input`) — modern, not playful.
- **Primary CTA:** Teal-Navy (#294056) fill, white label, padding 0.875rem × 2rem.
- **Hover:** darken to deeper navy, 250ms ease-in-out.
- **Focus:** soft outer glow in accent for keyboard nav (never remove the ring).
- **Secondary:** Teal-Navy outline, transparent fill; hover fills with whisper-soft teal tint.

### Cards & product containers
- **Corners:** gently rounded (12px / `--radius-card`).
- **Background:** `--surface`, alternating with `--surface-alt` by layering need.
- **Shadow:** flat by default; on hover `--shadow-hover` (`0 2px 8px rgba(0,0,0,0.06)`).
- **Border:** optional 1px Silver Gray hairline when shadow is absent.
- **Padding:** generous 2–2.5rem internal.
- **Image:** full-bleed top, 1:1 or 4:3, edge-to-edge.
- **Hover:** gentle lift (`translateY(-4px)`) + enhanced shadow.

### Inputs & forms
- **Stroke:** 1px Soft Warm Gray border; corners match buttons (8px).
- **Background:** Cream → Light Gray on focus; border shifts to Teal-Navy with soft glow.
- **Padding:** 0.875rem × 1.25rem (touch-friendly). Placeholder in Silver Gray.

### Navigation
- **Layout:** horizontal, 2–3rem item spacing.
- **Type:** Medium 500, subtle uppercase, 0.06em tracking.
- **Default:** Charcoal text. **Active/hover:** 200ms shift to Teal-Navy + 2px underline.
- **Mobile:** hamburger → sliding drawer.

---

## 6. Layout Principles

### Grid & structure
- **Max content width:** 1440px.
- **Grid:** 12-column, fluid gutters (24px mobile → 32px desktop).
- **Product grid:** 4 cols large desktop · 3 desktop · 2 tablet · 1 mobile.
- **Breakpoints:** mobile <768px · tablet 768–1024px · desktop 1024–1440px · large >1440px.

### Whitespace (critical to the brand)
- **Base:** 8px micro, 16px component.
- **Sections:** 5–8rem (80–128px) between major sections for dramatic breathing room.
- **Hero:** extra-generous 8–12rem top/bottom.

### Internal vs external spacing
- **Page edge → content:** 1.5rem mobile, 3rem tablet/desktop (external framing).
- **Card → content:** 2–2.5rem internal padding (own breathing room).
- **Section gaps belong to the section, not the card** — cards stay flush to their grid cell; the grid gutter does the separating.

### Alignment & balance
- Left-align body and nav; center hero headlines and featured content.
- Image-to-text weighted ~70/30 (photography-first).
- Touch targets ≥ 44×44px. Responsive images, lazy-loaded.

---

## 7. Icon Conventions (name → meaning)

One set (Lucide), consistent meaning across screens.

| Icon | Meaning | Where |
|---|---|---|
| `search` | Open search | Nav, filter bar |
| `shopping-bag` | Cart | Nav (right) |
| `heart` | Wishlist / save | Product card, product page |
| `sliders-horizontal` | Open filters | Collections toolbar |
| `chevron-down` | Expandable / sort menu | Filters, sort control |
| `check` | Selected / in stock | Filter chips, stock badge |
| `x` | Dismiss / clear filter | Chips, modal close |

Status glyphs in dense contexts: in stock `✓` (U+2713), out `✗` (U+2717) — use
glyphs over icons inside compact pills/badges.

---

## 8. Unconfirmed / TODO

- Dark-mode accent (`#7FA8C9`) is a proposed lightening of Teal-Navy for contrast on
  dark surfaces — **confirm against the real dark build**; not yet shipped.
- Cart screen was synthesized from the design brief, not a rendered screenshot —
  spacing values there are intended, not verified.
- Confirm whether `--surface-alt` is used on the Product page or only Collections.

---

## Using this document

When generating or coding a new screen, feed this file as context and reference the
**descriptive color names + hex**, the **scale tokens**, and the **component prose**
verbatim — e.g. "primary CTA in Deep Muted Teal-Navy (#294056), subtly rounded
corners, whisper-soft shadow on hover." Refine one component at a time and keep the
language consistent so every generated screen stays inside this system.
