---
name: to-plan
description: Pick up a raw idea/bug/improvement file from the planning backlog, research only the points it raises (relevant code files + vault refs), rewrite it as a structured key-point plan in planning/active/, and archive the raw original. Use when the user wants to organise, refine, or sharpen a backlog plan, or says "pick up my plan/notes from backlog". The intake end of the to-plan → do-plan → to-prd → to-issues → do-issue → do-pr pipeline.
---

# To Plan

Turn one raw plan file into a structured, researched plan. **One file per run.** Raw notes go in, a key-point plan comes out in `planning/active/`; the original is archived, never edited in place.

The vault is reached via the repo's `./memory` symlink. Read + write files only — never git or scripts there.

## Process

### 1. Select the raw file

If the user named a file, use it. Otherwise list the intake inbox — `memory/AgCore/planning/backlog/` — and ask which file to refine. Only consider files WITHOUT the structured key-point format (already-refined plans are not intake).

✓ **Done when:** exactly one raw file is chosen and you know its owning context (app-level backlog → that app; cross-cutting → shared).

### 2. Research only what the file raises

For each distinct point in the raw file — no gold-plating, no adjacent ideas:

- **Code:** locate the files/modules the point touches (`rg`, glob). Record exact paths.
- **Vault:** grep the catalog (`memory/scripts/output/catalog.jsonl`) and `rg memory/AgCore` for the point's terms. Read only hits: matching glossary terms (owning context's `CONTEXT.md`), relevant accepted ADRs, and any existing plan that overlaps — overlap is a finding, link it, don't duplicate it.
- Classify each point: *bug fix* / *structural refactor* / *feature* / *improvement*, with a verdict (e.g. Worth exploring · Quick win · Needs grilling).

✓ **Done when:** every point has real file paths, its vault refs, and a classification — and nothing outside the raw file's points was researched.

### 3. Write the refined plan to active/

Create `memory/AgCore/planning/active/<slug>.md`. All plans live in the one central `planning/` tree — there are no per-app planning folders (the two landing sites are the only exception, and they are not fed by this pipeline). Frontmatter per the vault schema (`type: plan`, `status: active`, `app:`, `created:`/`updated:`, `source:` = the raw file's archive path). Then one section per point, exactly this format:

```markdown
### N. <Title> — *<classification> (<verdict>)*
**Form section / Files:** `path/one.tsx`, `path/two.ts`
**Problem:** <what is wrong / missing, grounded in the researched code>
**Solution:** <the proposed change, one direction — alternatives go to grilling>
**Benefits:**
- <benefit>
- <benefit>
**Refs:** [[<adr-or-note>]] (<what it decides>).

**Key requirements**
- <binding requirement>
- <binding requirement>
```

Order points by leverage. Open questions you could not resolve from code/vault go in a final `## Open questions (for grilling)` list — do not guess answers.

✓ **Done when:** the plan file exists in the right `active/`, lint-valid frontmatter, every point in the format above.

### 4. Archive the original

Move the raw file to `memory/AgCore/planning/archive/` (archives keep no frontmatter). Append one line to `memory/log.md`.

✓ **Done when:** backlog no longer contains the raw file; archive does; log updated.

### 5. Report

Name the new plan path, list the points with classifications, flag overlaps with existing plans, and state the next step: `/do-plan <file>` to grill it and publish the PRD.
