# Design Quality Reference (S-Tier, deduped)

Supporting criteria for the design-review Steps 2–9. Load this when the affected app's `DESIGN.md` is silent on a token or pattern.

Universal code rules are owned by the `web-design-guidelines` skill (live Web Interface Guidelines) and are **not** repeated here; items already covered by those rules — keyboard navigation, focus/hover/active state mechanics, input `type`/`inputmode`, toast `aria-live`, virtualization threshold — are omitted. Use this for design-system specifics those rules don't define.

## Philosophy (gut-check)

Users first; meticulous craft; simplicity & clarity; focus & efficiency; consistency; opinionated thoughtful defaults; WCAG AA **contrast ratios**.

## Token defaults (use when DESIGN.md is silent)

- **Color:** primary brand (strategic use); 5–7 neutral steps; semantic success/error/warning/info; dark-mode palette; all combos pass AA
- **Type:** one clean sans (Inter/Manrope/system-ui); modular scale (H1–H4, Body L/M/S/caption); limited weights; body line-height 1.5–1.7
- **Spacing:** 8px base, multiples only
- **Radii:** small set (4–6px inputs/buttons; 8–12px cards/modals)
- **Component inventory** (states/focus/hover → `web-design-guidelines` skill): buttons (primary/secondary/ghost/destructive/link + icon), inputs (text/textarea/select/date), checkbox/radio, toggle, card, table, modal, nav (sidebar/tabs), badge, tooltip, progress, icons (single set), avatar

## Layout & hierarchy

Responsive 12-col grid; ample whitespace; clear hierarchy via type/space/position; consistent alignment. Dashboard shell: persistent left sidebar (primary nav) + content area + optional top bar (search/profile/notifs). Mobile-first.

## Interaction & animation (intent; mechanics → `web-design-guidelines` skill)

Micro-interactions purposeful, feedback immediate; 150–300ms ease-in-out; skeleton screens for page loads, spinners in-component; enhance not distract.

## Module tactics

- **Data tables:** left-align text / right-align numbers; bold headers; optional zebra; adequate row height; sortable headers w/ indicators; filters above table; global search; pagination (admin) or virtual scroll; sticky headers/frozen cols; expandable rows; inline editing; bulk actions; per-row action icons
- **Config panels:** clear labels + helper/tooltips; logical grouping (sections/tabs); progressive disclosure; sensible defaults; reset-to-defaults; save confirmation; live preview if applicable
- **Media moderation:** prominent previews; labeled + color-coded actions w/ icons; status badges (pending/approved/rejected); contextual metadata; bulk actions; kbd shortcuts

## CSS architecture

Scalable methodology (utility-first Tailwind w/ tokens in config / BEM+Sass / scoped CSS-in-JS); tokens directly usable; maintainable; no bloat.

## General

Iterate w/ user testing; clear IA; responsive across desktop/tablet/mobile; document the design system + components.
