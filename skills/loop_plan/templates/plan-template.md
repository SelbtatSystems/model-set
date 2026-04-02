---
branchName: "ralph/{feature-name}"
projectName: "{Feature Name}"
totalSprints: {N}
startDate: "{YYYY-MM-DD}"
---

# {Feature Name} Sprint Plan

Execute sprints 0-N in order. Each task must pass ALL validation before marking complete.

**Existing Infrastructure**: {Note relevant existing tables, modules, components}

---

## Sprint 0: Foundation & Setup

**Goal**: Database schema, shared components, seed data

### Database Tasks

- [ ] **0.1** {Task title}
  - **File**: `db/migrations/YYYYMMDD_description.sql`
  - **Implementation**:
    ```sql
    -- SQL implementation here
    ```
  - **Validation**:
    - [ ] Migration file exists at path
    - [ ] Run via postgres-mcp: `mcp__postgres__execute_sql` - no errors
    - [ ] Query returns expected data
    - [ ] `mcp__postgres__get_object_details` shows correct schema

### Backend Tasks

- [ ] **0.2** {Task title}
  - **File**: `backend/src/{module}/{file}.ts`
  - **Implementation**:
    ```typescript
    // TypeScript implementation here
    ```
  - **Validation**:
    - [ ] File exists at path
    - [ ] Compiles: `cd backend && npx tsc --noEmit`
    - [ ] Exported from module index
    - [ ] Unit test passes (if applicable)

### Frontend Tasks

- [ ] **0.3** {Task title}
  - **File**: `apps/agcore-web/src/app/{feature}/{Component}.tsx`
  - **Implementation**:
    - Props: `{ prop1: Type, prop2: Type }`
    - Description of component behavior
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ Component Title                                     │
    ├─────────────────────────────────────────────────────┤
    │ [Content layout here]                               │
    └─────────────────────────────────────────────────────┘
    ```
  - **Validation**:
    - [ ] Component file exists
    - [ ] TypeScript compiles
    - [ ] Renders without errors
    - [ ] Layout matches wireframe

---

## Sprint 1: {Core Feature}

**Goal**: {Demoable outcome description}

### Backend Tasks

- [ ] **1.1** Create GET /{resource} endpoint
  - **File**: `backend/src/{module}/{module}.controller.ts`
  - **Implementation**:
    ```typescript
    @Get()
    async getResource(
      @Query('param') param: string,
    ): Promise<ResourceDto[]>
    ```
  - **Validation**:
    - [ ] Endpoint accessible: GET /{resource}?param=value
    - [ ] Returns correct DTO shape
    - [ ] Query params filter correctly
    - [ ] Handles empty results gracefully

### Frontend Tasks

- [ ] **1.2** Create {Feature}Page.tsx
  - **File**: `apps/agcore-web/src/app/{Feature}/{Feature}Page.tsx`
  - **Implementation**:
    - Fetch data via React Query
    - Display in table/list/cards
    - Loading and empty states
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ {Page Title}                    [Action Button]     │
    ├─────────────────────────────────────────────────────┤
    │ Column 1 │ Column 2 │ Column 3 │ Actions           │
    ├──────────┼──────────┼──────────┼───────────────────┤
    │ Data     │ Data     │ Data     │ [Edit] [Delete]   │
    └──────────┴──────────┴──────────┴───────────────────┘
    ```
  - **Validation**:
    - [ ] Page renders at route
    - [ ] Data loads from API
    - [ ] Loading spinner shows during fetch
    - [ ] Empty state when no data
    - [ ] Layout matches wireframe

---

## Summary

| Sprint | Goal | Tasks |
|--------|------|-------|
| 0 | Foundation | X |
| 1 | {Feature} | X |
| ... | ... | ... |

**Total**: ~XX tasks
