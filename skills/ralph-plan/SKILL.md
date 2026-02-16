---
name: ralph-plan
description: Create a new Ralph execution plan from a PRD file. Archives existing plan/progress, researches the codebase, and generates a comprehensive sprint plan.
allowed-tools: Bash Read Write Glob Grep Task Edit
---

# Ralph Plan Generator

Creates comprehensive sprint execution plans for the Ralph autonomous agent system.

## Trigger

When user provides a PRD file path like `@path/to/prd.md create ralph plan` or `ralph plan @prd.md`

## Workflow

### Phase 1: Archive Existing Work

1. Check if `.claude/ralph/plan.md` exists
2. If exists:
   - Extract `projectName` from YAML frontmatter
   - Move `plan.md` to `.claude/ralph/archive/{projectName}-sprint.md`
   - Move `progress.txt` to `.claude/ralph/archive/{projectName}-progress.txt`
3. Create fresh `progress.txt`:
   ```
   # Ralph Progress Log
   Started: {current date}
   ---
   ```

### Phase 2: Research the Codebase

Spawn an Explore agent to research:

```
Research the codebase to understand:
1. Existing database schema relevant to {prd topic}
2. Existing backend modules, services, controllers
3. Existing frontend pages, components, patterns
4. Existing shared packages and utilities
5. API patterns and conventions used
6. CSS/styling conventions

Focus areas from the PRD:
{extract key features from PRD}

Return a structured report with:
- Relevant existing files and their purposes
- Database tables that exist or need modification
- API endpoints that exist or need creation
- Frontend components that can be reused
- Patterns to follow for consistency
```

### Phase 3: Generate the Plan

Use this EXACT prompt structure to generate the plan:

```
{PRD CONTENT}

If you were to break this project down into sprints and tasks, how would you do it (timeline info does not need included and doesn't matter) - every task/ticket should be an atomic, commitable piece of work with tests (and if tests don't make sense another form of validation that it was completed successfully), every sprint should result in a demoable piece of software that can be run, tested, and build on top of previous work/sprints. Be exhaustive, be clear, be technical, include wireframes, navigation, endpoints, always focus on small atomic tasks that compose up into a clear goal for the sprint.

## Codebase Research Results
{RESEARCH RESULTS}

## Plan Structure Requirements

The plan MUST follow this exact structure:

1. **YAML Frontmatter**:
   ```yaml
   ---
   branchName: "ralph/{feature-name}"
   projectName: "{Feature Name}"
   totalSprints: {N}
   startDate: "{YYYY-MM-DD}"
   ---
   ```

2. **Sprint Format**:
   ```markdown
   ## Sprint N: {Sprint Goal Title}

   **Goal**: {One-line description of demoable outcome}

   ### {Category} Tasks (e.g., Backend Tasks, Frontend Tasks, Database Tasks)

   - [ ] **N.M** {Task Title}
     - **File**: `{exact file path}`
     - **Implementation**:
       {Code snippet or detailed steps}
     - **Validation**:
       - [ ] {Validation 1 - specific, testable}
       - [ ] {Validation 2 - specific, testable}
       - [ ] {Validation 3 - specific, testable}
       - [ ] {Validation 4 - specific, testable}
   ```

3. **Validation Requirements** (MINIMUM 4 per task):
   - Database tasks: migration runs, columns exist, constraints work, queries return expected data
   - Backend tasks: endpoint accessible, returns correct shape, handles errors, integrates with existing code
   - Frontend tasks: component renders, interactions work, styling correct, integrates with API

4. **Wireframes**: Include ASCII wireframes for all UI components

5. **Sprint Summary Table**: At the end, include task count per sprint

Once you're done, provide this prompt to a subagent to review your work and suggest improvements. When you're done reviewing the suggested improvements, write your tasks/tickets, sprint plans, etc to .claude/ralph/plan.md
```

### Phase 4: Review Loop

Spawn a Plan agent to review the generated plan:

```
Review this sprint plan for:
1. Task atomicity - is each task truly a single commit?
2. Validation completeness - does each task have 4+ testable validations?
3. Sprint coherence - does each sprint produce a demoable result?
4. Technical accuracy - are file paths, API shapes, and implementations correct?
5. Missing tasks - are there gaps in the implementation flow?
6. Dependency order - are tasks ordered so dependencies are built first?

Suggest specific improvements with task IDs.
```

Incorporate feedback and finalize the plan.

### Phase 5: Write the Plan

Write the final plan to `.claude/ralph/plan.md`

## Example Usage

```
User: @docs/prd-notifications.md create ralph plan

Agent:
1. Archives existing plan.md and progress.txt
2. Researches notification-related code patterns
3. Generates comprehensive sprint plan
4. Gets review feedback from Plan agent
5. Writes final plan to .claude/ralph/plan.md
```
