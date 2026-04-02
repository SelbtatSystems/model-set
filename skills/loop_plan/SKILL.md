---
name: loop-plan
description: Create a new loop execution plan from a PRD file. Archives existing review.md, researches the codebase, and generates a comprehensive sprint plan.
allowed-tools: Bash Read Write Glob Grep Task Edit
---

# loop Plan Generator

Creates comprehensive sprint execution plans for the loop autonomous agent system.

## Trigger

When user provides a PRD file path like `@path/to/prd.md create loop plan` or `loop plan @prd.md`

## Workflow

### Phase 1: Archive Existing Work

1. Check if `./loop/roadmap/review.md` exists
2. If exists:
   - Attempt to extract `projectName` from YAML frontmatter
   - If frontmatter is missing or `projectName` is not found, fall back to using the PRD filename (without extension) as `projectName`
   - Move `review.md` to `./loop/roadmap/archive/{projectName}-sprint.md`

### Phase 2: Research the Codebase

Spawn an Explore agent to research:

```
Research the codebase to understand:
1. Existing database schema relevant to {prd topic}
2. Existing backend modules, services, controllers
3. Existing frontend pages, components, patterns
4. Existing shared packages and utilities
5. API patterns and conventions used
6. CSS/DESIGN.md styling conventions

Focus areas from the PRD:
{extract key features from PRD}

Return a structured report with:
- Tech-stack and Dependencies
- Relevant existing files and their purposes
- Database tables that exist or need modification
- API endpoints that exist or need creation
- Frontend components that can be reused
- Frontend components that need to be created
- Patterns to follow for consistency
```

### Phase 3: Generate the Plan

First, read the plan template:
`Read /skills/loop_plan/templates/plan-template.md`

Use the template structure above as the basis for the generated plan, then use this prompt to drive generation:

```
{PRD CONTENT}

If you were to break this project down into sprints and tasks, how would you do it (timeline info does not need to be included and doesn't matter) - every task/ticket should be an atomic, commitable piece of work with tests (and if tests don't make sense another form of validation that it was completed successfully), every sprint should result in a demoable piece of software that can be run, tested, and build on top of previous work/sprints. Be exhaustive, be clear, be technical, include wireframes, navigation, endpoints, always focus on small atomic tasks that compose up into a clear goal for the sprint.

## Codebase Research Results
{RESEARCH RESULTS}
```
## Plan Structure Requirements

The plan MUST follow the structure defined in `.skills/loop_plan/templates/plan-template.md`, including:

1. **YAML Frontmatter**:
```yaml
   ---
   branchName: "loop/{feature-name}"
   projectName: "{Feature Name}"
   totalSprints: {N}
   startDate: "{YYYY-MM-DD}"
   ---
```
   


2. **Sprint Format**:
```markdown
## Sprint N: {Sprint Goal Title}

**Goal**: {description of demoable outcome}

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

Write the completed plan to `./loop/roadmap/review.md`


### Phase 4: Review Loop

Spawn a Plan agent to review the generated plan:

```
Review the sprint plan at `./loop/roadmap/review.md` for:
1. Task atomicity - is each task truly a single commit?
2. Validation completeness - does each task have 4+ testable validations?
3. Sprint coherence - does each sprint produce a demoable result?
4. Technical accuracy - are file paths, API shapes, and implementations correct?
5. Missing tasks - are there gaps in the implementation flow?
6. Dependency order - are tasks ordered so dependencies are built first?

Incorporate specific improvements and update `./loop/roadmap/review.md` with the finalized plan.
```

### Phase 5: Append the Plan

Append the final plan from `./loop/roadmap/review.md` to `./loop/roadmap/loop_roadmap.md`

## Example Usage

```
User: @docs/prd-notifications.md create loop plan

Agent:
1. Archives existing review.md to ./loop/roadmap/archive/{projectName}-sprint.md
2. Researches notification-related code patterns
3. Reads plan-template.md, generates comprehensive sprint plan, writes to review.md
4. Spawns Plan agent to review and finalize review.md
5. Appends final plan to ./loop/roadmap/loop_roadmap.md
```