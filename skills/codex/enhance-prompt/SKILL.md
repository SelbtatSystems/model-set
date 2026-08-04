---
name: enhance-prompt
description: Turn a rough UI idea, an existing page, or a reference screenshot into a precise, build-ready prompt for a coding agent to implement a page in this repo. Works with frontend-design (aesthetic direction), web-design-guidelines (quality floor), and DESIGN.md (project design language).
---

# Enhance Prompt — Frontend Build Prompt

You are a **Frontend Build-Prompt Engineer**. Transform a rough UI idea — or an
existing page, or a reference screenshot — into a precise, **build-ready prompt** that
a coding agent uses to implement a real page **in this repo**. Your output is a
*prompt*, not code.

## Works with

- **`frontend-design`** — aesthetic *direction*: distinctive palette/type/layout, a
  signature element, no templated defaults. Lean on it for new pages; the output
  prompt also tells the builder to apply it.
- **`web-design-guidelines`** — the **quality floor** (semantic landmarks, visible
  keyboard focus, AA contrast, reduced motion, responsive, ≥44px touch targets).
  Bake these in as explicit constraints, and tell the builder to self-check against it.
- **`design-md` / DESIGN.md** — the project's **design language**, the visual source
  of truth. Resolve it before writing the prompt (see Step 2).

## Modes — detect which one first

| Mode | Trigger | What you produce |
|------|---------|------------------|
| **1. New page** | User gives an idea/prompt and wants a brand-new page ("investigate the feature") | A grounded build prompt for a new page |
| **2. Existing page** | User names an existing page / route / component | A prompt to rebuild or refine that page |
| **3. Screenshot → our design** | User provides a screenshot of a reference page | A prompt to build that page **in our design language** |

## Pipeline

### Step 0 — Detect the mode
Read the request: a fresh idea → Mode 1; a path/route/page name that already exists →
Mode 2; an attached image → Mode 3. If genuinely ambiguous, ask one question.

### Step 1 — Investigate (mode-specific)
- **Mode 1 (new):** Use `Grep`/`Glob`/`Read` to investigate the feature in the
  codebase — its route, data shapes/types, related components, and domain vocabulary.
  Ground the prompt in the feature's **real content**, never lorem (per `frontend-design`).
- **Mode 2 (existing):** `Read` the page component(s) and the CSS classes they use.
  Then use the **`agent-browser`** skill to screenshot it in light + dark, so you
  capture how it actually looks today (`snapshot -i` before interacting; re-snapshot
  after navigation). Note what to preserve vs. what to change.
- **Mode 3 (screenshot):** `Read` the provided screenshot. Extract **structure only** —
  layout regions, components, hierarchy, content blocks. Do **not** carry over its
  colors/type/spacing; those come from DESIGN.md in Step 2.

### Step 2 — Resolve the design language (DESIGN.md)
Look for **`memory/AgCore/apps/<VaultName>/DESIGN.md`** (app↔vault map in the project
`CLAUDE.md`, e.g. `agcore-web → AgCore-web`, `myfarmjob-web → MyFarmJob`).
- **If present:** the enhanced prompt **must** target that design language — pull the
  descriptive color names + hex, type scale, component prose, and icon conventions
  into the DESIGN SYSTEM block. For Mode 3 this is the whole point: foreign layout,
  our tokens.
- **If absent:** derive aesthetic direction from the **`frontend-design`** skill
  instead, and add a one-line tip that running **`design-md`** first yields a reusable
  design language.

### Step 3 — Bake in the quality floor
Add explicit constraints from **`web-design-guidelines`**: semantic HTML + landmarks,
visible keyboard focus, AA contrast, `prefers-reduced-motion` respected, responsive
down to mobile, touch targets ≥ 44px. End the prompt by telling the builder to
self-check against `web-design-guidelines` after building.

### Step 4 — Apply design direction
- **New pages (esp. without DESIGN.md):** apply `frontend-design` thinking — a
  distinctive palette/type pairing, one signature element, avoid the AI-default looks,
  match execution complexity to the vision.
- **Existing / DESIGN.md cases:** stay inside the established system — the boldness is
  already decided; consistency wins.

### Step 5 — Assemble the enhanced prompt
Output this structure (markdown):

```markdown
[One-line description of the page's purpose and vibe]

**TARGET:** [New page at <route> | Refine existing <page> | Build <page> in our design language]

**DESIGN SYSTEM (REQUIRED):**
- [From DESIGN.md: descriptive color names (#hex) + roles, type scale, component
  conventions, icons] — or, if no DESIGN.md, the frontend-design direction
- Platform / theme / spacing / radius as applicable

**PAGE STRUCTURE:**
1. **[Section]:** [components + behavior]
2. ...

**CONTENT:** [real copy/data from Step 1 investigation — not lorem]

**CONSTRAINTS (quality floor):**
- Semantic landmarks, visible keyboard focus, AA contrast, reduced motion, responsive, ≥44px targets
- Apply the `frontend-design` skill for visual direction
- Self-check the result against the `web-design-guidelines` skill

[Mode 2 only] **PRESERVE:** [what must not change] — make only the changes listed.
```

## Output

- **Default:** return the enhanced prompt as text for the user to copy or feed to the
  build agent.
- **Optional file:** if asked, write `next-prompt.md` (or a user-named file) for the
  **`loop-prompt`** skill.

## Enhancement tactics

- **Add UI/UX keywords** — replace vague terms with specific component names; see
  `references/KEYWORDS.md` for the vocabulary, adjective palettes, and shape
  translations (`rounded-lg` → "generously rounded corners").
- **Amplify the vibe** — "modern" → "clean, minimal, generous whitespace"; keep it
  matched to the brief, don't over-design a simple ask.
- **Format colors** — always `Descriptive Name (#hex) for [role]`.
- **Structure** — numbered sections so the build agent reads hierarchy clearly.
- **One change at a time** for edits — don't bundle unrelated changes.

## Examples

### Example A — Mode 1: new page from a feature
**User:** "Build a new applicant-review page. Investigate the feature first."
**You:** Grep the `applicant`/`review` routes, types, and existing list components;
read DESIGN.md; then output:
```markdown
A focused applicant-review page: scan candidates fast, act with confidence.

**TARGET:** New page at /workforce/applicants/:id/review

**DESIGN SYSTEM (REQUIRED):**
- Accent: Sage Green (#7da36d) for primary actions and active states
- Surface: White (#ffffff) cards on Warm White (#F8F9F8) page bg
- Text: Near-black Sage (#1a2b1f) primary, Gray (#4b5563) secondary
- Status pills per DESIGN.md badge palette; Lucide icons; toast-bottom-center

**PAGE STRUCTURE:**
1. **Header:** breadcrumb + applicant name + status pill
2. **Summary card:** photo, contact, applied role, applied date
3. **Decision bar:** Approve / Reject (Sage primary / destructive), sticky on scroll
...

**CONTENT:** real fields from the Applicant type — name, role, visa status, availability.

**CONSTRAINTS (quality floor):** landmarks, keyboard focus, AA contrast, responsive,
≥44px targets. Apply `frontend-design`. Self-check against `web-design-guidelines`.
```

### Example B — Mode 3: screenshot → our design language
**User:** [attaches a screenshot of a competitor's pricing page] "Build this in our design."
**You:** Read the screenshot for structure (3-tier pricing grid, toggle, FAQ); read
DESIGN.md; then output a prompt whose **PAGE STRUCTURE** mirrors the screenshot but
whose **DESIGN SYSTEM** is entirely our tokens — so the layout is theirs, the look is ours.

## Tips

1. **Investigate before enhancing** — a grounded prompt beats a generic one.
2. **DESIGN.md is the contract** — when it exists, never invent off-system colors.
3. **Match the user's intent** — don't over-design a simple request.
4. **The output is a prompt** — hand the builder direction + constraints, not code.
