---
name: do-plan
description: Pick a refined plan from planning/active/, run a grill-with-docs session on it, then ask the user whether to publish the outcome as a PRD via to-prd — on publish, move the plan to planning/done/. Use when the user wants to grill an active plan, stress-test a plan from the planning folder, or continue the to-plan → do-plan → to-prd → to-issues → do-issue → do-pr pipeline.
---

# Do Plan

Stress-test one refined plan from `planning/active/` and close its lifecycle: grill → PRD → done. **One plan per run.** This skill orchestrates `grill-with-docs` and `to-prd`; it does not restate them.

The vault is reached via the repo's `./memory` symlink. Read + write files only — never git or scripts there.

## Process

### 1. Select the plan

If the user named a plan, use it. Otherwise list `memory/AgCore/planning/active/` and ask which to grill. The plan's `## Open questions (for grilling)` section (from `to-plan`) is the opening agenda.

✓ **Done when:** one active plan is chosen and read in full.

### 2. Grill

Invoke `grill-with-docs` on the plan: challenge it against the owning context's `CONTEXT.md` glossary + ADRs, walk the open questions first, then each key point's Problem/Solution. As decisions crystallise, glossary terms and ADRs update inline per that skill; also update the plan file's **Key requirements** lines so every decision is captured in the plan itself — the sharpened brief is the highest-leverage output of the session.

✓ **Done when:** the user says the grilling is complete (no forced end — the user closes the session).

### 3. Ask, then publish

Ask the user: **"Write the grilling outcome to a PRD via `to-prd`? (yes / no)"**

- **Yes** → invoke the `to-prd` skill; the PRD publishes to `memory/AgCore/planning/issues/<feature-slug>/PRD.md` as that skill defines. Wait for it to finish.
- **No** → skip to the non-published outcome in step 4.

✓ **Done when:** the user has answered, and on yes the PRD file exists and names the plan as its source.

### 4. Close the plan

**Published:** set the plan's frontmatter `status: done` + `completed: YYYY-MM-DD`, add a final line linking the PRD (`Refs: [[planning/issues/<slug>/PRD]]`), and move the file into `memory/AgCore/planning/done/`. Append one line to `memory/log.md`.

**Not published** (plan rejected or deferred): leave it in `active/` with the updated Key requirements — or move it to `backlog/` with `status: backlog` if the user says defer. Never mark a plan done without a PRD.

✓ **Done when:** the plan sits in `done/` with `status: done`, or its non-published outcome is applied and reported.

### 5. Report

State: plan → PRD path, the decisions that changed the plan, and the next step: `/to-issues` on the PRD, then `/do-issue` → `/do-pr`.
