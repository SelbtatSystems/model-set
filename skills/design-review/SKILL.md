---
name: design-review
description: Comprehensive visual design review for front-end changes. This skill should be used when conducting design reviews on UI changes, verifying visual consistency against project design systems, testing responsive design across viewports, validating accessibility compliance, or ensuring changes meet S-Tier SaaS design standards (Stripe/Linear/Vercel). Triggers on "review design", "check UI", "design review", or after completing front-end work.
---

# Design Review Skill

Conduct comprehensive visual design reviews against project design systems and S-Tier SaaS standards.

## Prerequisites

- The `agent-browser` CLI for browser automation (see `skills/agent-browser/SKILL.md`)
- A running local preview environment
- The `design-md` skill (for generating missing DESIGN.md files)

## Step 0: Load Project Design System

Before any review work, establish the project's design context.

### Check for DESIGN.md

1. Look for `DESIGN.md` in the project root directory
2. **If DESIGN.md exists:** Read it — this is the primary styling reference for the review. All color, typography, component, and layout decisions must be validated against this file.
3. **If DESIGN.md does NOT exist:** Ask the user: *"No DESIGN.md found. Create one using the design-md skill?"*
   - If yes: invoke the `design-md` skill to generate it, then read the result
   - If no: proceed without project-specific tokens (use only `references/design-principles.md`)

### Load Design Principles

Read `references/design-principles.md` (bundled with this skill) — the S-Tier SaaS design checklist. This is the universal quality bar applied to every review regardless of project.

### Context Hierarchy

| Priority | Source | Scope |
|----------|--------|-------|
| 1 | `DESIGN.md` (project root) | Project-specific tokens, colors, components, atmosphere |
| 2 | `references/design-principles.md` | Universal S-Tier SaaS quality checklist |

When conflicts exist, `DESIGN.md` takes precedence — it defines the project's intentional design language.

## Step 1: Preparation

1. Identify the scope of changes — which pages/components were modified
2. Review the code diff to understand implementation
3. Open the affected pages in agent-browser and take an initial snapshot:
   ```bash
   agent-browser open http://localhost:<port>/<path>
   agent-browser set viewport 1440 900
   agent-browser snapshot -i
   ```

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

## Step 3: Design Token Compliance

Cross-reference all visual properties against `DESIGN.md`:

- **Colors:** Verify every color matches defined tokens (no hardcoded hex values outside the system)
- **Typography:** Font sizes, weights, and spacing follow the documented scale
- **Spacing:** Uses the defined base unit (typically 8px) and scale
- **Border radius:** Matches documented values
- **Shadows:** Follow the defined elevation system
- **Component styles:** Use established CSS classes and patterns

## Step 4: Interaction & User Flow

- Execute the primary user flow
- Test all interactive states (hover, active, disabled, focus)
- Verify destructive action confirmations exist
- Assess perceived performance and responsiveness
- Check loading, empty, and error states

## Step 5: Theme Testing

- **Light mode:** Verify backgrounds, text contrast, borders, semantic colors
- **Dark mode:** Toggle theme and verify all tokens switch correctly
- Ensure no hardcoded colors break in either mode

## Step 6: Responsive Testing

Capture screenshots and verify at each breakpoint:

| Viewport | Dimensions | Checks |
|----------|------------|--------|
| Desktop | 1440x900 | Full layout, inline actions, multi-column |
| Tablet | 768x1024 | Responsive column hiding, dropdown actions, layout adaptation |
| Mobile | 375x812 | Single column, touch targets (44px min), collapsed nav |

Verify: no horizontal scrolling, no element overlap, no orphaned content.

## Step 7: Accessibility (WCAG 2.1 AA)

- **Contrast:** Minimum 4.5:1 for text, 3:1 for large text and UI components
- **Keyboard:** Complete Tab navigation, visible focus states, Enter/Space activation
- **Semantics:** Proper HTML elements, form labels, image alt text
- **Touch targets:** Minimum 44x44px on mobile
- **Screen reader:** `sr-only` text where visual context is insufficient
- **Motion:** Respects `prefers-reduced-motion`

## Step 8: Robustness

- Form validation with invalid inputs
- Content overflow / long text handling
- Empty states and error states styled appropriately
- Console errors: run `agent-browser console` and `agent-browser errors` and flag issues

## Step 9: Report

Structure findings as:

```markdown
### Design Review Summary
[Positive opening — acknowledge what works well, overall assessment]

### Findings

#### Blockers
- [Problem + Screenshot + DESIGN.md reference if applicable]

#### High-Priority
- [Problem + Screenshot]

#### Medium-Priority / Suggestions
- [Problem]

#### Nitpicks
- Nit: [Problem]
```

**Triage rules:**
- **Blocker:** Broken functionality, missing states, accessibility failures, DESIGN.md token violations
- **High-Priority:** Visual inconsistency, responsive breakage, contrast issues
- **Medium-Priority:** Polish items, spacing tweaks, animation refinements
- **Nitpick:** Minor aesthetic preferences (prefix with "Nit:")

## agent-browser Quick Reference

All browser automation uses the `agent-browser` CLI. See `skills/agent-browser/SKILL.md` for full documentation.

| Command | Purpose |
|---------|---------|
| `agent-browser open <url>` | Navigate to pages |
| `agent-browser snapshot -i` | DOM analysis (always before/after interactions) |
| `agent-browser screenshot <path>` | Visual evidence for findings |
| `agent-browser click @ref` / `fill @ref "text"` / `select @ref "opt"` | Interaction testing |
| `agent-browser hover @ref` | Hover state testing |
| `agent-browser press <key>` | Keyboard navigation testing (Tab, Enter, Space) |
| `agent-browser set viewport <w> <h>` | Resize viewport for responsive testing |
| `agent-browser set media dark\|light` | Toggle color scheme for theme testing |
| `agent-browser console` / `errors` | Check console logs and page errors |
| `agent-browser close` | Clean up when done |

**Screenshot storage:** Always save to `~/model-set/skills/agent-browser/screenshots/`.

**Critical:** Always `snapshot -i` before interacting, and re-snapshot after navigation or dynamic changes (refs invalidate on page changes).

## Principles

- **Problems over prescriptions:** Describe the problem and impact, not the CSS fix. ("Spacing feels inconsistent with adjacent elements" not "Change margin to 16px")
- **Evidence-based:** Screenshot every visual finding
- **Design system first:** Always reference DESIGN.md tokens when flagging color/spacing/typography issues
- **Constructive tone:** Assume good intent, lead with what works
