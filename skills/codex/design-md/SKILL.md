---
name: design-md
description: Synthesize a semantic design system into a DESIGN.md by analyzing an app's existing UI — CSS tokens, component code, and rendered screenshots. Produces the canonical design-context file consumed by the design-review skill and frontend-review agent.
---

# DESIGN.md Skill

You are an expert Design Systems Lead. Your goal is to analyze an app's existing UI
assets and synthesize a **Semantic Design System** into a file named `DESIGN.md`.

## What DESIGN.md is

`DESIGN.md` is the **single source of truth** for an app's design language. It
documents **what exists in the build** (every value traceable to a token, CSS
class, or component) in evocative, semantic language — descriptive color names with
exact hex, component prose, layout rules.

It is consumed downstream as design context by:
- the **`design-review`** skill and **`frontend-review`** agent (they resolve it to check conformance), and
- any LLM/codegen step generating a new screen (the descriptive language steers output to stay inside the system).

So write it to be both **human-readable** and **prompt-ready** context.

## Where it lives

This project keeps one per app at **`memory/AgCore/apps/<VaultName>/DESIGN.md`**
(app↔vault map in the project `CLAUDE.md`, e.g. `agcore-web → AgCore-web`,
`myfarmjob-web → MyFarmJob`, `myfarmjob-eForm-web → eForm`). If the project has no
such convention, write `DESIGN.md` at the project (or app) root. Always confirm the
target path before writing; never clobber a hand-curated DESIGN.md — update in place.

## Scope

**If the user names specific pages or components when invoking the skill, focus
exclusively on the style of those pages and components** — screenshot and document
only them, not the whole app. Otherwise, cover the app's representative surfaces.

## Inputs to analyze

Gather the real evidence first — never invent values. In priority order:

1. **Token/style sources** — `packages/shared-ui/src/styles/tokens.css`, the app's
   `globals.css`, `tailwind.config.js`. The semantic vars, raw palettes, and scale
   tokens come straight from here.
2. **Component source** — the app's real components and the CSS classes they use
   (buttons, inputs, cards, nav, tables, dropdowns, badges). Anchor each component's
   description to the file/class it comes from.
3. **Rendered UI (preferred when available)** — use the `agent-browser` skill to
   shoot screenshots of the in-scope pages in light + dark, so you build a real
   understanding of how they look before describing them. (`snapshot -i` before
   interacting; re-snapshot after navigation.) Use the shots to capture atmosphere,
   verify computed colors/fonts against the tokens, and quantify contrast. If the
   user named specific pages, screenshot only those.
4. **Design brief / mockups** — if the app (or part of it) isn't built yet, use what
   the user provides, and mark those sections as intended-not-verified in §TODO.

Use `Grep`/`Glob` to locate sources, `Read` to extract, `WebFetch` only for the
reference below.

## Analysis & synthesis steps

Work the chain: **locate → extract → translate to semantic language → synthesize**.

1. **Scope & identity** — name the app/surface; list the source assets you analyzed.
2. **Atmosphere** — evaluate the rendered screens + structure to capture the "vibe."
   Use evocative adjectives ("airy," "dense," "minimalist," "utilitarian").
3. **Foundations** — root font size + rem scale, type scale by role, and the scale
   tokens (spacing / radius / shadow / transition / touch target).
4. **Color palette & roles** — for each key color: a **descriptive natural-language
   name** ("Deep Muted Teal-Navy"), the **exact hex** in parentheses (#294056), and
   its **functional role**. Then map **semantic tokens** (var → light → dark → role).
5. **Contrast** — quantify key text/background pairs against the WCAG AA threshold
   (e.g. "Charcoal on Cream → ~13:1, AAA"). Quote ratios; flag any that fail.
6. **Typography by role** — family, weight per H1–H4/body/meta, letter-spacing, line-height.
7. **Geometry & depth** — translate technical values: `rounded-lg` → "subtly rounded
   corners"; `rounded-full` → "pill-shaped"; describe shadow presence/quality
   ("flat," "whisper-soft diffused," "heavy drop").
8. **Component stylings** — buttons, inputs, cards, nav (and tables/dropdowns/badges
   if present), each anchored to its component file/CSS class.
9. **Layout** — grid, breakpoints, whitespace strategy, and internal-vs-external
   spacing conventions.
10. **Icon conventions** — which set, name→meaning map, status glyphs.
11. **Verbatim authoritative blocks** — non-paraphrasable rules (icon set, toast
    placement, reserved functional colors) in a §0 block.
12. **Unconfirmed / TODO** — anything you couldn't verify against the rendered build.

## Output format

Follow the structure and voice of the canonical example: **`examples/DESIGN.md`**.
Read it before writing — it is the shape/voice target. Its sections:

```
# Design System: [App / Surface]
> Scope blockquote (what it documents + source assets analyzed)
## 0. Verbatim authoritative blocks
## 1. Visual Theme & Atmosphere
## 2. Foundations            (type scale + scale tokens)
## 3. Color Palette & Roles  (raw palette · semantic light/dark table · contrast)
## 4. Typography Rules
## 5. Component Stylings
## 6. Layout Principles       (incl. internal vs external spacing)
## 7. Icon Conventions
## 8. Unconfirmed / TODO
## Using this document
```

Scale the depth to the app: a marketing page needs fewer component sections than a
data-dense dashboard. Add sections (reference-page anatomies, color-by-role map)
when the app warrants them — but never pad with values you didn't verify.

## Writing principles

- **Descriptive + precise:** never "blue" or "rounded" — "Ocean-deep Cerulean
  (#0077B6)," "gently curved edges (8px)." Name colors by purpose; keep exact values.
- **Explain the why,** not just the what, behind each decision.
- **Anchor to code:** cite the token / CSS class / component file a value comes from.
- **Consistent vocabulary:** the descriptive names are the contract — reuse them
  exactly throughout, so downstream prose and generation reference one set of terms.
- **Be honest:** mark anything unverified against the rendered build in §TODO; don't
  present intended values as shipped.

## Reference: writing DESIGN.md as effective LLM context

Since DESIGN.md doubles as prompt context for screen generation, a few general
prompting techniques sharpen it — see https://www.promptingguide.ai/techniques:
- **Few-shot** — `examples/DESIGN.md` is the worked exemplar; match its structure and
  granularity rather than inventing a new shape.
- **Chain-of-thought / prompt chaining** — the locate→extract→translate→synthesize
  steps above are a deliberate decomposition; don't skip straight to prose.
- **Multimodal CoT** — reason jointly over the screenshot (image) and the
  code/tokens (text); let one verify the other (computed color vs token value).
- **Directional stimulus** — the evocative descriptive names ("whisper-soft shadow")
  are the steering hints that keep downstream generation on-brand. Choose them well.

## Common pitfalls to avoid

- ❌ Technical jargon without translation ("rounded-xl" instead of "generously rounded corners")
- ❌ Color names without hex codes, or hex without descriptive names
- ❌ Omitting functional roles, or contrast ratios for text pairs
- ❌ Vague atmosphere descriptions; ignoring shadows/spacing
- ❌ Inventing values not present in the build, or overwriting a curated DESIGN.md
