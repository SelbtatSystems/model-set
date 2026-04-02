---
name: loop-prompt
description: Autonomous loop agent that executes sprint tasks one-at-a-time from a roadmap. This skill should be used when running the loop agent cycle — implementing, validating, documenting, and syncing tasks from loop/roadmap/loop_roadmap.md. Triggers on "/loop-prompt" or when executing autonomous sprint task cycles.
---

# Loop Agent Instructions

Autonomous agent. One cycle = one task. Find first `- [ ]` in roadmap → implement EXACTLY as specified → validate EVERY sub-item by running the actual check → sync → stop.

## Core Rules
1. **ONE TASK per cycle** — complete it, sync to base, stop. Loop restarts you for the next.
2. **Shell state does NOT persist** between Bash calls — all state lives in `loop/.*` files.
3. **NEVER stop before step 9** — sync-to-base is mandatory. Skipping it breaks the loop.
4. **`--dangerously-skip-permissions`** — execute without confirmation.
5. **IMPLEMENT EXACTLY AS DESCRIBED** — the roadmap task specifies files, code, structure and skills to use. Follow them precisely. Do not improvise a different approach.
6. **VALIDATE BY RUNNING, NOT BY READING** — every validation sub-item must be verified by executing the actual command/query/request and checking the output. Reading code, grepping source files, or inspecting diffs is NOT validation. You must run the actual check (curl, tsc, agent-browser, postgres-mcp, /design-review skill, etc.) and see the result.
7. **NEVER MARK `[x]` ON A CHECK YOU DID NOT EXECUTE** — if a validation requires Docker and Docker is unavailable, or a tool is denied, or a skill can't run: leave that sub-item `- [ ]` and mark the task as PARTIAL. Do not mark it `[x]` and explain later. Do not ask the user what to do. The rule is absolute: unexecuted check = `[ ]` = PARTIAL.
8. **FULLY AUTONOMOUS — NEVER ASK THE USER** — you make every decision yourself based on best practices. If ambiguous, pick the best option and proceed. If blocked, mark PARTIAL and move on. Never output questions, option lists, or "should I...?" prompts. You are unattended — nobody is reading your output until the cycle ends.
9. **USE THE RIGHT SKILL FOR THE JOB**:
   - Task says "create" / "new" / "generate" a page → invoke `Skill("/new-page")`
   - Task says "redesign" / "overhaul" / "rework" an existing page → invoke `Skill("/page-redesign")`
   - Task involves any frontend change → invoke `Skill("/design-review")` during validation
   - Task says "enhance prompt" or description is vague → invoke `Skill("/enhance-prompt")` before generating
   - These are not suggestions. If the roadmap task specifies a skill, you MUST invoke it via the `Skill` tool. Writing the component by hand when a skill is specified is a violation of rule 5.

## State Files (read/write every bash block that needs them)
| File | Content |
|------|---------|
| `loop/.loopRegister` | Base branch (read-only) |
| `loop/.last-task-id` | Current task ID |
| `loop/.last-task-desc` | Current task description |
| `loop/.last-branch` | Sprint branch name |
| `loop/.last-sprint` | Sprint number |
| `loop/.last-pr` | PR number (0 if mid-sprint) |
| `loop/.sprint-status` | `SPRINT_PR_CREATED=true/false` |

## Resources
- **MCP**: postgres-mcp, redis-mcp, Context7, Stitch, Stripe
- **Context7**: `resolve-library-id` then `query-docs` — **MUST use** before touching external libs (Stripe, TypeORM, NestJS, React Query, etc.)
- **Skills** (use via `Skill` tool):
  - `/new-page` — **MUST use** when roadmap says "Use `/new-page`" or "generate page"
  - `/page-redesign` — **MUST use** when roadmap says "redesign" an existing page
  - `/enhance-prompt` — use to refine vague UI descriptions before Stitch generation
  - `/design-review` — **REQUIRED** after every frontend change. Fix Blocker/High before marking complete.
- **Agents**: `Explore` (codebase search), `Plan` (architecture), `design-review` (visual audit)
- **Browser**: agent-browser CLI — always `snapshot -i` before interacting

## Log Files (`~/.openclaw/workspace/logs/loop/`)
- `loop-tasks.json` — every task start/complete/partial
- `loop-prs.json` — sprint PRs only. `checks` fields default `false`, updated externally by CI/reviews.

---

## Steps

### 0. SYNC + LOG START (first action every cycle)

```bash
# Ensure base branch is up-to-date with main before anything else
BASE_BRANCH=$(cat loop/.loopRegister)
git fetch origin main --quiet
git checkout "$BASE_BRANCH"
git rebase origin/main || true

LOG_DIR="$HOME/.openclaw/workspace/logs/loop"
TASK_LOG="$LOG_DIR/loop-tasks.json"
PR_LOG="$LOG_DIR/loop-prs.json"
mkdir -p "$LOG_DIR"

TASK_ID=$(grep -m1 '\- \[ \] \*\*' loop/roadmap/loop_roadmap.md | grep -oP '\*\*\K[0-9]+\.[0-9a-z]+')
TASK_DESC=$(grep -m1 '\- \[ \] \*\*' loop/roadmap/loop_roadmap.md | sed 's/.*\*\*[0-9.a-z]*\*\* //')
SPRINT_NUM=$(echo "$TASK_ID" | cut -d. -f1)
BASE_BRANCH=$(cat loop/.loopRegister)
TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "unknown")
TIMESTAMP=$(date +%s%3N)

# Persist for later bash blocks
echo "$TASK_ID" > loop/.last-task-id
echo "$TASK_DESC" > loop/.last-task-desc

[ -f "$TASK_LOG" ] || echo '[]' > "$TASK_LOG"
[ -f "$PR_LOG" ] || echo '[]' > "$PR_LOG"

jq --arg id "$TASK_ID" --arg desc "$TASK_DESC" --argjson sprint "$SPRINT_NUM" \
   --arg session "$TMUX_SESSION" --arg branch "$BASE_BRANCH" --argjson ts "$TIMESTAMP" \
   '. += [{"id":$id,"description":$desc,"sprint":$sprint,"branch":$branch,
           "tmuxSession":$session,"agent":"claude","repo":"AgCore",
           "startedAt":$ts,"completedAt":null,"status":"running"}]' \
   "$TASK_LOG" > /tmp/loop-tasks-tmp.json
if [ -s /tmp/loop-tasks-tmp.json ] && jq empty /tmp/loop-tasks-tmp.json 2>/dev/null; then
  mv /tmp/loop-tasks-tmp.json "$TASK_LOG"
else
  echo "ERROR: jq failed — $TASK_LOG preserved" >&2
fi
```

### 1. READ CONTEXT (max 5 min)
- `loop/progress.txt` — check `## Codebase Patterns`, `## Implemented Endpoints`
- **PARTIAL resume**: search for `(PARTIAL)` matching current task. If found, read `Resume:` line, skip completed parts.
- `loop/roadmap/loop_roadmap.md` — read first `- [ ]` task. **Read the FULL task spec** including:
  - **File** paths listed — these are the exact files to create/modify
  - **Implementation** section — this is the exact code/approach to use
  - **Validation** sub-items — these are the exact checks you must run
- Read ONLY target file(s) for that task

### 2. SPRINT BRANCH (one per sprint, reused across tasks)

```bash
BASE_BRANCH=$(cat loop/.loopRegister)

# Commit dirty tracking files before switching (prevents checkout failures)
if ! git diff --quiet -- loop/ 2>/dev/null || ! git diff --cached --quiet -- loop/ 2>/dev/null; then
  git add loop/roadmap/loop_roadmap.md loop/progress.txt 2>/dev/null
  git commit -m "track: cleanup uncommitted tracking files" || true
fi

git checkout "$BASE_BRANCH"
git fetch origin main --quiet
git rebase origin/main || true

TASK_ID=$(cat loop/.last-task-id)
SPRINT_NUM=$(echo "$TASK_ID" | cut -d. -f1)
SPRINT_SLUG=$(grep -m1 "^## Sprint ${SPRINT_NUM}:" loop/roadmap/loop_roadmap.md \
  | sed "s/^## Sprint ${SPRINT_NUM}: //" \
  | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/-\+/-/g; s/^-//; s/-$//' | cut -c1-40)
SPRINT_BRANCH="loop/sprint-${SPRINT_NUM}-${SPRINT_SLUG}"

if git show-ref --verify --quiet "refs/heads/${SPRINT_BRANCH}"; then
  git checkout "$SPRINT_BRANCH"
  git pull origin "$SPRINT_BRANCH" --rebase 2>/dev/null || true
  git merge "$BASE_BRANCH" --no-edit || true
else
  git checkout -b "$SPRINT_BRANCH"
fi

echo "$SPRINT_BRANCH" > loop/.last-branch
echo "$SPRINT_NUM" > loop/.last-sprint
```

### 3. IMPLEMENT (max 15 min)

**You MUST follow the task spec exactly. You are autonomous — make all decisions yourself.**

#### 3a. Read the Implementation section line by line

The roadmap task has an `Implementation:` section. This is your blueprint — not a suggestion. Work through it sequentially:

1. Read each bullet/line in `Implementation:`
2. Execute that specific instruction (create file, add code, register module, etc.)
3. If the task includes a **code block** under `Implementation:` → use that code as-is (adapt only for imports/context that differ from the current codebase)
4. If the task includes a **wireframe**, **mockup**, or **layout description** → use it as the prompt input for `/new-page` or `/page-redesign` (see below)
5. Move to the next bullet. Do not skip any.

#### 3b. File paths

Create/modify the exact files listed in the task's `File:` fields. Do not rename or relocate them.

#### 3c. Frontend page skills (mandatory — never hand-write pages when a skill applies)

| Task says... | You MUST do... |
|-------------|----------------|
| "Create page", "new page", "generate page", "Use `/new-page`" | `Skill("/new-page")` |
| "Redesign page", "overhaul page", "rework page", "Use `/page-redesign`" | `Skill("/page-redesign")` |
| Description is vague / needs refinement before generation | `Skill("/enhance-prompt")` first, then the page skill |

**How to build the prompt for `/new-page` or `/page-redesign`:**
- Start with the task's `Implementation:` description — include ALL features/sections it specifies
- If the task includes a **wireframe or layout sketch** (ASCII, markdown table, or description of sections) → include it verbatim in the prompt so Stitch generates the correct layout
- Include the page's **functionality** (what data it shows, what actions users can take, what API endpoints it connects to)
- Include the target **file path** so the skill knows where to place the output
- Reference `DESIGN.md` tokens if the task mentions design system compliance

**Why skills over hand-writing**: These skills generate via Stitch with proper design tokens, accessibility, responsive layout, and production patterns. Hand-writing produces inferior, inconsistent results and violates rule 5.

#### 3d. Context7 (external libraries)

Before writing code that uses external libraries (Stripe SDK, TypeORM decorators, NestJS guards, React Query hooks, etc.), invoke Context7:
```
mcp__context7__resolve-library-id → get library ID
mcp__context7__query-docs → get relevant API docs
```

#### 3e. Explore agent

If you need to understand existing patterns before implementing, spawn an `Explore` agent first.

#### 3f. Decision-making

When the task is ambiguous or you face a choice (naming, structure, approach), pick the option that matches existing codebase patterns. Use `Explore` agent to find patterns if unsure. Never stop to ask — decide and proceed.

ONE task only. Minimal, focused changes. Follow existing patterns.

### 4. REBUILD

Rebuild/restart affected services. **Always run from `infrastructure/docker/`:**
```bash
cd infrastructure/docker
docker compose --env-file ../../.env build <service>
docker compose --env-file ../../.env up -d <service>
cd ../..
```
Wait for healthy before proceeding. Check with:
```bash
cd infrastructure/docker && docker compose --env-file ../../.env ps && cd ../..
```

### 5. VALIDATE (mandatory — run each check, verify output, one by one)

> **THIS IS THE MOST CRITICAL STEP. DO NOT CUT CORNERS.**
>
> **`- [x]` means "I ran the check and it passed." Nothing else.**
> Grepping code, reading diffs, or inspecting files is NOT validation. If you did not execute the command and see the output, the sub-item stays `- [ ]`.
>
> **If a tool is blocked** (Docker denied, permission error, skill unavailable): leave that sub-item `- [ ]`, proceed to the next sub-item, and at the end mark the task as PARTIAL. Do not ask the user. Do not mark `[x]` and explain. Just `[ ]` and PARTIAL.

For EACH `- [ ]` validation sub-item in the task:

1. **READ** the validation text — it describes the exact check to run
2. **EXECUTE** the check — run the actual command, query, or request:
   - SQL validation → use `mcp__postgres__execute_sql` or docker exec psql
   - API endpoint → use `curl` with auth headers, check status code AND response body
   - TypeScript compile → run `npx tsc --noEmit` via docker: `cd infrastructure/docker && docker compose --env-file ../../.env run --rm backend npx tsc --noEmit 2>&1 && cd ../..`
   - Frontend render → use agent-browser: `open` → `snapshot -i` → verify elements exist
   - `/design-review` → invoke `Skill("/design-review")` — this is a real execution, not optional
   - File exists → use `Read` tool or `ls` to confirm
3. **VERIFY** the output matches what the validation expects:
   - If the check says "returns 200" → verify the HTTP status is exactly 200
   - If the check says "returns 403" → verify the HTTP status is exactly 403
   - If the check says "no errors" → verify the command exit code is 0 AND no error text in output
   - If the check says "table exists" → verify the table is in the query result
   - If the check says "column X has type Y" → verify the exact type matches
   - If the check says "Use `/design-review`" → you must invoke the skill and see its output
4. **DECIDE**:
   - **PASS** (you executed the check and it succeeded) → mark `- [x]`
   - **FAIL** (you executed the check and it failed) → **DO NOT MARK [x]**. Instead:
     a. Read the error output carefully
     b. Fix the implementation
     c. Rebuild if needed
     d. Re-run the same validation
     e. Repeat until it passes or you've tried 3 times
     f. If still failing after 3 attempts → mark task as PARTIAL (see Partial Completion)
   - **BLOCKED** (tool denied, Docker unavailable, permission error) → **DO NOT MARK [x]**. Leave `- [ ]`. Document the blocker. Continue to next sub-item. Task becomes PARTIAL at the end.

**NEVER mark a sub-item `[x]` without actually running the check and seeing it pass.**
**NEVER mark the task complete unless ALL sub-items are `[x]`.**

#### Validation Protocol by Type

**Database Tasks** (postgres-mcp preferred):
```
1. mcp__postgres__execute_sql → Run migration SQL
2. mcp__postgres__list_objects → Verify table/column exists in result
3. mcp__postgres__get_object_details → Check column types, constraints, defaults match spec
4. mcp__postgres__execute_sql → Run test queries from validation section, verify row counts/shapes
```

**Backend Tasks** (curl + docker):
```
1. Rebuild: cd infrastructure/docker && docker compose --env-file ../../.env build backend && docker compose --env-file ../../.env up -d backend && cd ../..
2. Wait: sleep 10, then check logs for startup errors
3. Auth: Get JWT token via curl -X POST localhost:3100/api/v1/auth/login
4. Test endpoint: curl -H "Authorization: Bearer $TOKEN" localhost:3100/api/v1/<path>
5. Verify: Check HTTP status code AND response JSON shape match expected
6. Negative test: If validation says "returns 403 for X user" → test with that user's token
```

**TypeScript Compile**:
```
cd infrastructure/docker && docker compose --env-file ../../.env run --rm backend npx tsc --noEmit 2>&1 && cd ../..
# Exit code 0 = pass. Any non-zero = fail. Read error output to fix.
```

**Frontend Tasks** (agent-browser + /design-review):
```
1. Rebuild: cd infrastructure/docker && docker compose --env-file ../../.env build <app> && docker compose --env-file ../../.env up -d <app> && cd ../..
2. Wait for healthy (check docker compose ps)
3. Open: agent-browser open http://localhost:<PORT>/<path>
4. Snapshot: agent-browser snapshot -i   (MUST do before any interaction)
5. Verify: Check that expected elements exist in the snapshot
6. Interact: agent-browser click/fill as needed
7. Screenshot: agent-browser screenshot <path> (for evidence)
8. Console: agent-browser console — check for API errors, JS errors
9. Close: agent-browser close
10. Design review: Skill("/design-review") — MANDATORY for all frontend changes
    - If Blocker or High findings → fix them → rebuild → re-run /design-review
    - Only proceed when no Blocker/High findings remain
```

### 6. DOCUMENT (mandatory)
Append to `loop/progress.txt` under `## Progress Entries`:
```
## [YYYY-MM-DD HH:MM] - Task X.Y
- Impl: [what was done]
- Files: [files changed]
- Valid: PASS ([n]/[n]) or FAIL ([passed]/[total] — [which failed])
- Learn: [pattern discovered, if any]
---
```
Update `## Implemented Endpoints` if new endpoint. Update `## Codebase Patterns` if reusable learning.

### 7. COMMIT + PUSH

```bash
SPRINT_BRANCH=$(cat loop/.last-branch)
SPRINT_NUM=$(cat loop/.last-sprint)
TASK_ID=$(cat loop/.last-task-id)
TASK_DESC=$(cat loop/.last-task-desc)
git checkout "$SPRINT_BRANCH"

git add -A && git commit -m "feat: ${TASK_ID} - ${TASK_DESC}"
git push origin "$SPRINT_BRANCH"

# PR only on last task in sprint
LAST_TASK=$(grep -oP "^\- \[.\] \*\*\K${SPRINT_NUM}\.[0-9a-z]+" loop/roadmap/loop_roadmap.md | tail -1)

if [ "$TASK_ID" = "$LAST_TASK" ]; then
  SPRINT_TASKS=$(grep -oP "^\- \[x\] \*\*\K${SPRINT_NUM}\.[0-9a-z]+" loop/roadmap/loop_roadmap.md | tr '\n' ', ' | sed 's/,$//')
  SPRINT_TITLE=$(grep -m1 "^## Sprint ${SPRINT_NUM}:" loop/roadmap/loop_roadmap.md | sed 's/^## //')

  PR_URL=$(gh pr create --draft \
    --title "feat: ${SPRINT_TITLE}" \
    --body "$(cat <<'PREOF'
## Summary
See `loop/progress.txt` for per-task implementation details.
PREOF
)" --base main)

  echo "$(echo "$PR_URL" | grep -oP '(?<=/pull/)\d+')" > loop/.last-pr
  echo "SPRINT_PR_CREATED=true" > loop/.sprint-status
else
  echo "0" > loop/.last-pr
  echo "SPRINT_PR_CREATED=false" > loop/.sprint-status
fi
```

### 8. MARK COMPLETE

**Two checkboxes must change** (both in `loop/roadmap/loop_roadmap.md`):
1. Each validation sub-item: `- [ ]` → `- [x]` *(done in step 5, only after running the actual check)*
2. **The task line itself**: `- [ ] **X.Y**` → `- [x] **X.Y**`

**Pre-flight check before marking the task line:**
- Count all validation `- [ ]` under this task. If ANY remain unchecked → DO NOT mark the task line.
- This is your final gate. If you skipped a validation or it didn't truly pass, the task stays `[ ]`.

### 9. SYNC TO BASE + LOG + STOP

> **CRITICAL — this step is non-negotiable.** If you skip it, the next cycle cannot see your work and the loop breaks. Every bash block below re-reads state from files.

#### 9a. Sync tracking files to main

The commit message IS the task report — no separate terminal output needed.

**SAFETY**: Detach HEAD at origin/main so ONLY tracking files can reach main. Never push a branch to main.

```bash
SPRINT_BRANCH=$(cat loop/.last-branch)
BASE_BRANCH=$(cat loop/.loopRegister)
TASK_ID=$(cat loop/.last-task-id)
TASK_DESC=$(cat loop/.last-task-desc)

git fetch origin main --quiet

# Detach HEAD at exactly origin/main — prevents code leaking to main
git checkout --detach origin/main

# Cherry-pick ONLY tracking files from sprint branch
git checkout "$SPRINT_BRANCH" -- loop/roadmap/loop_roadmap.md loop/progress.txt
git add loop/roadmap/loop_roadmap.md loop/progress.txt
git commit -m "track: ${TASK_ID} - ${TASK_DESC}" || true
git push origin HEAD:main

# Return to base branch and rebase on updated main
git checkout "$BASE_BRANCH"
git rebase origin/main || true
```

#### 9b. Update loop-tasks.json

```bash
LOG_DIR="$HOME/.openclaw/workspace/logs/loop"
TASK_LOG="$LOG_DIR/loop-tasks.json"
TASK_ID=$(cat loop/.last-task-id)
COMPLETED_AT=$(date +%s%3N)

jq --arg id "$TASK_ID" --argjson ts "$COMPLETED_AT" \
   'map(if .id == $id and .status == "running" then . + {"status":"done","completedAt":$ts} else . end)' \
   "$TASK_LOG" > /tmp/loop-tasks-tmp.json
if [ -s /tmp/loop-tasks-tmp.json ] && jq empty /tmp/loop-tasks-tmp.json 2>/dev/null; then
  mv /tmp/loop-tasks-tmp.json "$TASK_LOG"
else
  echo "ERROR: jq failed — $TASK_LOG preserved" >&2
fi
```

#### 9c. Update loop-prs.json (sprint completion only)

```bash
LOG_DIR="$HOME/.openclaw/workspace/logs/loop"
PR_LOG="$LOG_DIR/loop-prs.json"
TASK_ID=$(cat loop/.last-task-id)
SPRINT_NUM=$(echo "$TASK_ID" | cut -d. -f1)
SPRINT_STATUS=$(cat loop/.sprint-status 2>/dev/null || echo "SPRINT_PR_CREATED=false")

if echo "$SPRINT_STATUS" | grep -q "SPRINT_PR_CREATED=true"; then
  PR_NUMBER=$(cat loop/.last-pr 2>/dev/null || echo "0")
  SPRINT_BRANCH=$(cat loop/.last-branch)
  SPRINT_TITLE=$(grep -m1 "^## Sprint ${SPRINT_NUM}:" loop/roadmap/loop_roadmap.md | sed 's/^## //')
  COMPLETED_AT=$(date +%s%3N)
  SPRINT_TASK_IDS=$(grep -oP "^\- \[x\] \*\*\K${SPRINT_NUM}\.[0-9a-z]+" loop/roadmap/loop_roadmap.md | jq -R . | jq -s .)

  jq --argjson sprint "$SPRINT_NUM" --arg title "$SPRINT_TITLE" --arg branch "$SPRINT_BRANCH" \
     --argjson pr "$PR_NUMBER" --argjson tasks "$SPRINT_TASK_IDS" --argjson ts "$COMPLETED_AT" \
     '. += [{"sprint":$sprint,"title":$title,"branch":$branch,"pr":$pr,"tasks":$tasks,
             "createdAt":$ts,"checks":{"ciPassed":false,"geminiReviewPassed":false,
             "codexReviewPassed":false,"claudeReviewPassed":false}}]' \
     "$PR_LOG" > /tmp/loop-prs-tmp.json
  if [ -s /tmp/loop-prs-tmp.json ] && jq empty /tmp/loop-prs-tmp.json 2>/dev/null; then
    mv /tmp/loop-prs-tmp.json "$PR_LOG"
  else
    echo "ERROR: jq failed — $PR_LOG preserved" >&2
  fi
fi
```

#### 9d. STOP

- ALL roadmap tasks `[x]` → reply `<promise>COMPLETE</promise>`
- Otherwise → **STOP. End response. Do not continue.**

---

## Validation Protocols

**IMPORTANT — Docker commands**: Always run `docker compose` from `infrastructure/docker/` with `--env-file ../../.env`. Never run from repo root.
```bash
cd infrastructure/docker
docker compose --env-file ../../.env <command>
cd ../..  # return to repo root after
```

**DB** (postgres-mcp preferred, or docker compose exec):
- Prefer MCP: `execute_sql` (run migration) → `list_objects` (verify exists) → `get_object_details` (types/constraints) → test queries from roadmap
- If using docker: `cd infrastructure/docker && docker compose --env-file ../../.env exec -T postgres psql -U agcore_user -d agcore_db -c "SQL" && cd ../..`

**Backend**: rebuild (`cd infrastructure/docker && docker compose --env-file ../../.env build backend && docker compose --env-file ../../.env up -d backend && cd ../..`) → wait healthy → check logs → `curl` endpoint → verify response shape

**Frontend** (agent-browser + /design-review):
1. Rebuild (`cd infrastructure/docker && docker compose --env-file ../../.env build <app> && docker compose --env-file ../../.env up -d <app> && cd ../..`) → wait healthy → `open` → `snapshot -i` → `screenshot` → test interactions → `console` (check API errors) → `close`
2. Run `/design-review` — fix Blocker/High findings before marking complete

## Partial Completion

If you cannot complete fully:
1. Do NOT mark `[x]`
2. Commit `wip: X.Y - partial` → push sprint branch
3. Update task log:
```bash
LOG_DIR="$HOME/.openclaw/workspace/logs/loop"
TASK_LOG="$LOG_DIR/loop-tasks.json"
TASK_ID=$(cat loop/.last-task-id)
jq --arg id "$TASK_ID" \
  'map(if .id == $id and .status == "running" then .status = "partial" else . end)' \
  "$TASK_LOG" > /tmp/loop-tasks-tmp.json
if [ -s /tmp/loop-tasks-tmp.json ] && jq empty /tmp/loop-tasks-tmp.json 2>/dev/null; then
  mv /tmp/loop-tasks-tmp.json "$TASK_LOG"
else
  echo "ERROR: jq failed — $TASK_LOG preserved" >&2
fi
```
4. Return to base: `git checkout "$(cat loop/.loopRegister)"`
5. Append to progress.txt:
```
## [DateTime] - Task X.Y (PARTIAL)
- Done: [completed parts]
- Left: [remaining parts]
- Resume: [file:line or next action]
---
```
Next cycle auto-resumes via step 1 PARTIAL check.

## Error Handling
- **Build fails**: log, retry once, then document and skip
- **Migration fails**: do NOT retry, document, skip
- **Test fails**: fix if implementation issue, note if test issue
- **Browser timeout**: close, retry once, then document
- **Dirty worktree**: commit tracking files first (step 2 handles this). **NEVER** `rm -f .git/index.lock`, `git stash`, or `git checkout .`
