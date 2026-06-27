---
name: design-review
description: Comprehensive visual + code design review for front-end changes. This skill should be used when conducting design reviews on UI changes, verifying visual consistency against the project design system, confirming CSS classes are applied correctly (e.g. icon colors inside input fields, dropdown/select background colors and styling), testing responsive design across viewports, validating accessibility, auditing against Web Interface Guidelines, or ensuring changes meet S-Tier SaaS standards (Stripe/Linear/Vercel). Triggers on "review design", "check UI", "design review", "review my UI", "check accessibility", "audit design", "review UX", "check styling", or after completing front-end work.
metadata:
  author: selbtat
  version: "2.0.0"
  argument-hint: <file-or-pattern>
---

# Design Review Skill

Conduct comprehensive design reviews against the project design system, the Web Interface Guidelines (via the `web-design-guidelines` skill), and S-Tier SaaS standards. Combines code-level rule checking with browser-driven visual review.

## Prerequisites

- `agent-browser` CLI for browser automation (see `skills/agent-browser/SKILL.md`)
- A running local preview environment
- `design-md` skill (for generating a missing app `DESIGN.md`)
- `web-design-guidelines` skill (live Web Interface Guidelines + terse `file:line` format)

---

## Execution Protocol — READ FIRST (progressive, strict order)

This review is **sequential**. The agent MUST:

1. Execute steps **in numeric order**, top to bottom.
2. **Complete a step fully** — perform every check, capture required evidence, log findings — before starting the next.
3. **Not begin step N+1** until step N's **Gate** condition is satisfied.
4. Announce each transition: `✓ Step N complete → starting Step N+1`.
5. Maintain a running ledger (below). If a Gate cannot be met (e.g. preview won't load), **stop** and report the blocker — do not skip ahead.

```text
Progress Ledger
[ ] Step 0  Load design system
[ ] Step 1  Preparation
[ ] Step 2  Million Dollar Minimal
[ ] Step 3  Design token compliance
[ ] Step 4  Component conventions (icons + toasts)
[ ] Step 5  Interaction & user flow
[ ] Step 6  Theme testing
[ ] Step 7  Responsive testing
[ ] Step 8  Accessibility (WCAG 2.1 AA)
[ ] Step 9  Robustness
[ ] Step 10 Report
```

The **Design Quality Reference** (S-Tier, deduped) lives in `references/design-principles.md` — supporting criteria to consult during Steps 2–9, do not treat it as a step.

---

## Step 0: Load Project Design System

Establish design context before any review work. **`DESIGN.md` is per-app** — each app owns its design language, tokens, and component conventions (icons, toasts, status glyphs) inside its own `DESIGN.md`.

### Resolve the app(s) & load DESIGN.md
1. From the changed files, determine which app(s) they belong to.
2. Resolve each app's `DESIGN.md` location from the project's context map (its `CLAUDE.md` / `CONTEXT-MAP.md`). In this repo, design references live at **`llm-wiki/apps/<VaultName>/DESIGN.md`**, where `<VaultName>` is the app's vault name from CLAUDE.md's app↔vault map (e.g. `agcore-web → AgCore-web`, `myfarmjob-web → MyFarmJob`, `myfarmjob-eForm-web → eForm`).
3. For **each** affected app, load that `DESIGN.md`:
   - **If it exists:** read it — primary styling reference **for that app's surfaces**. All color/typography/component/layout/icon/toast decisions for that app's files validate against it.
   - **If missing:** invoke the `design-md` skill to generate it for that app, then read the result.
4. If the change spans multiple apps, load **each** app's `DESIGN.md` and apply the matching one per file — never validate one app's surfaces against another app's design language. Note any cross-app inconsistency as a finding, not a violation.

### Universal guidelines — via the `web-design-guidelines` skill
Invoke the **`web-design-guidelines`** skill before reviewing. It fetches the live Web Interface Guidelines and owns the universal S-Tier rules + the terse `file:line` output format. Apply its rules throughout Steps 2–9.

### Context Hierarchy
| Priority | Source | Scope |
|----------|--------|-------|
| 1 | The app's `DESIGN.md` (`llm-wiki/apps/<VaultName>/DESIGN.md`) | That app's tokens, colors, components, icon/toast conventions, atmosphere — authoritative for that app's files |
| 2 | Web Interface Guidelines (via the `web-design-guidelines` skill) | Universal S-Tier SaaS quality checklist |
| 3 | `references/design-principles.md` (this skill) | S-Tier design-system criteria not in 1–2 |

On conflict, the relevant app's `DESIGN.md` wins — it defines that app's intentional language.

**Gate:** the `DESIGN.md` for every affected app read (or generated then read) AND the `web-design-guidelines` skill applied.

---

## Step 1: Preparation

1. Identify scope — which pages/components changed, and **which app** each belongs to.
2. Review the code diff to understand implementation.
3. Open affected pages and snapshot:
   ```bash
   agent-browser open http://localhost:<port>/<path>
   agent-browser set viewport 1440 900
   agent-browser snapshot -i
   ```

**Gate:** scope listed, diff read, initial snapshot captured for each affected page.

---

## Step 2: Million Dollar Minimal Check (CRITICAL — DO FIRST)

Premium corporate design inspired by Stripe, Linear, Vercel. Verify:

- No unnecessary cards/boxes — flat layouts preferred
- Ghost buttons for secondary actions (NO borders)
- Only ONE primary button per view (main CTA)
- Generous whitespace — content breathes
- No decorative elements — every pixel has purpose
- Subtle borders only (1px max) — prefer spacing to separate
- Shadows ONLY on elevated elements (modals, dropdowns)
- Monochromatic palette + single accent color

**Gate:** every item above assessed for the changed surfaces; violations logged.

---

## Step 3: Design Token Compliance

Cross-reference all visual properties against the affected app's `DESIGN.md`:

- **Colors:** every color matches defined tokens (no hardcoded hex outside the system)
- **Typography:** sizes, weights, spacing follow the documented scale
- **Spacing:** uses the defined base unit (typically 8px) and scale
- **Border radius:** matches documented values
- **Shadows:** follow the defined elevation system
- **Component styles:** use established CSS classes/patterns

### CSS class application (not just token values)
Verify the right classes are actually **applied and resolving** — correct token present but mis-wired is still a defect. Inspect computed styles in-browser (`agent-browser snapshot -i`), don't trust the markup alone:

- **Icon colors inside inputs:** leading/trailing icons in entry/search fields inherit the intended token (`currentColor` / placeholder vs text color), not a default black/inherited stray. Check default, focus, filled, disabled, and error states.
- **Dropdown / `<select>` backgrounds:** option list and trigger have explicit `background-color` **and** `color` applied (native `<select>` won't inherit — Windows/dark-mode regression). Verify open state, hover/active option, and selected option.
- **State classes wired:** hover/focus/active/disabled/error class variants are present AND winning the cascade (not overridden by a later rule or lost to specificity).
- **No empty/typo class hooks:** flag class names that resolve to nothing (missing utility, typo, unpurged/purged Tailwind class) — styling silently drops.
- **Theme vars resolve:** CSS custom properties referenced by classes actually resolve in both themes (no `var(--x)` falling back to initial).

If the app's `DESIGN.md` is silent on a token, fall back to the defaults in `references/design-principles.md`.

**Gate:** all six categories checked against the app's `DESIGN.md`; CSS class application verified via computed styles for icons-in-inputs and dropdown backgrounds; hardcoded/off-token/unresolved/overridden classes logged with the token or class they should use.

---

## Step 4: Component Conventions — Icons, Toasts & Patterns

Each app documents its component standards — icon set(s), toast placement, status glyphs, and other reusable patterns — in its **`DESIGN.md`** (see Step 0). Read that app's conventions there first, then verify the changed code follows them. Do not assume a default; the authoritative values (library names, import paths, utility classes, CSS vars) live in `DESIGN.md`.

### Icons
- Icons trace to the app's documented icon set(s) — typically a primary library plus a named fallback. **No bespoke decorative SVGs** outside the documented system.
- Inlined SVGs follow the documented form (e.g. `stroke="currentColor"` so color follows CSS) — never recolored by editing fills.
- Status glyphs in buttons/semantic indicators use the documented characters (commonly `✓` U+2713 / `✗` U+2717), not stray icons.

### Toast / transient notifications
- Toasts appear in the documented position and use the documented utility/component — anchoring respects any documented content-area offsets (e.g. sidebar-aware centering via CSS vars) rather than raw viewport units.
- No ad-hoc corner-anchored toasts (`fixed bottom-4 right-4` and similar) unless `DESIGN.md` says so.
- Entry animation matches the documented timing/easing.

If the app's `DESIGN.md` is silent on a convention, fall back to `references/design-principles.md`.

**Gate:** icons, toasts, and status glyphs checked against the app's documented conventions; bespoke/off-convention usages logged with the documented standard they should follow.

---

## Step 5: Interaction & User Flow

- Execute the primary user flow
- Test all interactive states (hover, active, disabled, focus)
- Verify destructive-action confirmations exist
- Assess perceived performance and responsiveness
- Check loading, empty, and error states

**Gate:** primary flow executed end-to-end; all states exercised; missing states logged.

---

## Step 6: Theme Testing

- **Light mode:** backgrounds, text contrast, borders, semantic colors
- **Dark mode:** `agent-browser set media dark` — verify all tokens switch correctly
- Ensure no hardcoded colors break in either mode

**Gate:** both themes captured and compared; theme-break issues logged.

---

## Step 7: Responsive Testing

Capture screenshots and verify at each breakpoint:

| Viewport | Dimensions | Checks |
|----------|------------|--------|
| Desktop | 1440x900 | Full layout, inline actions, multi-column |
| Tablet | 768x1024 | Responsive column hiding, dropdown actions, layout adaptation |
| Mobile | 375x812 | Single column, touch targets (44px min), collapsed nav |

Verify: no horizontal scrolling, no element overlap, no orphaned content.

**Gate:** screenshots at all three viewports; layout failures logged.

---

## Step 8: Accessibility (WCAG 2.1 AA)

- **Contrast:** min 4.5:1 text, 3:1 large text & UI components
- **Keyboard:** full Tab navigation, visible focus, Enter/Space activation
- **Semantics:** proper HTML elements, form labels, image alt text
- **Touch targets:** min 44×44px on mobile
- **Screen reader:** `sr-only` text where visual context is insufficient
- **Motion:** respects `prefers-reduced-motion`

**Gate:** all six categories tested in-browser; failures triaged as Blockers.

---

## Step 9: Robustness

- Form validation with invalid inputs
- Content overflow / long-text handling
- Empty and error states styled appropriately
- Console: run `agent-browser console` and `agent-browser errors`, flag issues

**Gate:** edge cases exercised; console clean or issues logged.

---

## Step 10: Report

Structure findings as:

```markdown
### Design Review Summary
[Positive opening — acknowledge what works, overall assessment]

### Findings

#### Blockers
- [Problem + Screenshot + app DESIGN.md reference if applicable]

#### High-Priority
- [Problem + Screenshot]

#### Medium-Priority / Suggestions
- [Problem]

#### Nitpicks
- Nit: [Problem]
```

For code-level rule violations also use the `web-design-guidelines` skill's terse `file:line` format inside the relevant severity bucket.

**Triage rules:**
- **Blocker:** broken functionality, missing states, a11y failures, app `DESIGN.md` token violations, bespoke icons, corner-anchored toasts
- **High-Priority:** visual inconsistency, responsive breakage, contrast issues
- **Medium-Priority:** polish, spacing tweaks, animation refinements
- **Nitpick:** minor aesthetic preferences (prefix "Nit:")

**Gate:** all prior steps' findings consolidated; review complete.

---

## Design Quality Reference

S-Tier design-system criteria that the `web-design-guidelines` skill doesn't define — philosophy, token defaults, layout, interaction intent, module tactics, CSS architecture — live in **`references/design-principles.md`**. Load that file as supporting criteria during Steps 2–9, especially when an app's `DESIGN.md` is silent on a token or pattern. Do not treat it as a step.

---

## agent-browser Quick Reference

See `skills/agent-browser/SKILL.md` for full docs.

| Command | Purpose |
|---------|---------|
| `agent-browser open <url>` | Navigate to pages |
| `agent-browser snapshot -i` | DOM analysis (always before/after interactions) |
| `agent-browser screenshot <path>` | Visual evidence for findings |
| `agent-browser click @ref` / `fill @ref "text"` / `select @ref "opt"` | Interaction testing |
| `agent-browser hover @ref` | Hover state testing |
| `agent-browser press <key>` | Keyboard nav testing (Tab, Enter, Space) |
| `agent-browser set viewport <w> <h>` | Resize for responsive testing |
| `agent-browser set media dark\|light` | Toggle color scheme |
| `agent-browser console` / `errors` | Console logs and page errors |
| `agent-browser close` | Clean up when done |

**Screenshot storage:** always save to `~/model-set/skills/agent-browser/screenshots/`.

**Critical:** always `snapshot -i` before interacting, and re-snapshot after navigation or dynamic changes (refs invalidate on page changes).

---

## Principles

- **Problems over prescriptions:** describe problem + impact, not the CSS fix.
- **Evidence-based:** screenshot every visual finding.
- **Design system first:** reference the affected app's `DESIGN.md` tokens when flagging color/spacing/typography.
- **Constructive tone:** assume good intent, lead with what works.
- **One step at a time:** never start a step before the previous Gate is met.