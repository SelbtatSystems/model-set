---
name: page-redesign
description: Redesigns existing React pages through Stitch generation with automated conversion. Generates page content only (no app shell).
allowed-tools: mcp__stitch__* Read Write Edit Bash Glob Grep WebFetch AskUserQuestion
---

# Page Redesign Skill

You are a **Page Redesign Engineer**. Your job is to transform existing React pages through Stitch UI generation and convert them back to production-ready React components.

**Critical constraint**: Only generate **page content** for `PageRenderer` - headers, sidebars, and breadcrumbs are already handled by the app shell.

## Architecture Context

```
PageRenderer.tsx
  └── PageWrapper (breadcrumbs) ← Already exists
        └── PageComponent ← THIS IS WHAT WE GENERATE
              └── Page content only (no header/sidebar)
```

Pages use:
- CSS variables: `--text-primary`, `--surface`, `--accent`, `--border`
- React Query for data fetching
- Context: `useAuth`, `useOrganization`, `useNavigation`

---

## Phase 1: Analyze Existing Page

**Goal**: Document current functionality before redesign.

1. **Read the target page file** and its imported components
2. **Identify and document**:
   - **Functionality**: Event handlers, API calls (useQuery, useMutation), state (useState, useReducer), custom hooks
   - **Layout**: Component hierarchy, grid/flex structure, responsive breakpoints
   - **Navigation**: Internal navigation (tabs, links), external routing (useNavigate)
   - **Accessibility**: ARIA labels, keyboard nav, semantic elements
   - **Data dependencies**: Props, context usage, query keys
3. **Write analysis** to `.agents/skills/page-redesign/.temp/page-analysis.md`

Use this template structure:

```markdown
# Page Analysis: {PageName}
**File**: apps/agcore-web/src/app/{path}/{PageName}.tsx

## Functionality
- API calls: [list endpoints with query keys]
- State: [useState/useReducer hooks]
- Hooks: [custom hooks used]
- Event handlers: [key interactions]

## Layout Structure
- [component tree]
- [responsive breakpoints]

## Navigation
- [tabs, internal routing]
- [click handlers that navigate]

## Accessibility
- Missing: [gaps found]
- Present: [good practices]

## Data Dependencies
- Context: useAuth, useOrganization
- Queries: [query keys]
- Props: [if any]

## Imported Components
- [list local and shared-ui components]
```

---

## Phase 2: Create Stitch Prompt

**Goal**: Generate optimized prompt using enhance-prompt patterns + DESIGN.md.

1. **Read `DESIGN.md`** Section 9 (Stitch Prompt Guidance)
2. **Read `temp/page-analysis.md`**
3. **Construct prompt** for page content only:

```markdown
A professional {page type} with sage green accents and clean data visualization.
This is PAGE CONTENT ONLY - no header, sidebar, or navigation chrome.

**DESIGN SYSTEM (REQUIRED):**
- Platform: Web, Desktop-first (2560px canvas)
- Theme: Light mode, professional agricultural SaaS
- Background: Soft Parchment (#f8f9f8) - page content background
- Primary Accent: Sage Field Green (#7da36d)
- Text Primary: Deep Forest (#1a2b1f)
- Text Secondary: Muted Gray (#4b5563)
- Font: Manrope, clean sans-serif
- Corners: Gently rounded (8px radius)
- Shadows: Minimal, whisper-soft
- Icons: Material Symbols Outlined (FILL 0, WGHT 400)

**Page Structure:**
1. **{Section 1}**: {Description}
2. **{Section 2}**: {Description}
...

**Functional Notes:**
- {Key interactions to preserve}
- {Data display requirements}
```

4. **Output** to `.agents/skills/page-redesign/.temp/stitch-prompt.md`

---

## Phase 3: Generate in Stitch

**Goal**: Create the UI design using Stitch MCP.

1. **Get project ID**: `17628915167374403984` (from DESIGN.md)
2. **Call Stitch MCP**:
   ```
   mcp__stitch__generate_screen_from_text
     projectId: "17628915167374403984"
     prompt: [contents of temp/stitch-prompt.md]
     deviceType: "DESKTOP"
     modelId: "GEMINI_3_PRO"
   ```
3. **Wait for generation** (up to 5 minutes for complex pages)
4. **Store returned `screenId`**

---

## Phase 4: User Review

**Goal**: Allow user to review and optionally modify in Stitch UI.

1. **Inform user**: "Screen generated. Review at https://stitch.withgoogle.com"
2. **Ask**: "Did you make any changes in Stitch?"

**If NO changes**: Proceed with original screenId

**If YES changes**:
1. Call `mcp__stitch__list_screens` with projectId
2. Present screen list to user
3. User selects which screen to use
4. Proceed with selected screenId

---

## Phase 5: Convert to React

**Goal**: Transform Stitch HTML to production React components.

Follow the react-components skill pattern:

1. **Fetch screen data**:
   ```
   mcp__stitch__get_screen
     projectId: "17628915167374403984"
     screenId: [screenId from Phase 3/4]
   ```

2. **Download HTML** via bash (AI fetch tools fail on Google Cloud Storage):
   ```bash
   curl -L -f -sS "[htmlCode.downloadUrl]" -o .agents/skills/page-redesign/.temp/source.html
   ```

3. **Parse HTML**:
   - Extract Tailwind config from `<head>`
   - Map colors to CSS variables:
     - `#1a2b1f` → `var(--text-primary)`
     - `#4b5563` → `var(--text-secondary)`
     - `#7da36d` → `var(--accent)`
     - `#f8f9f8` → `var(--surface)`
     - etc.
   - Identify component boundaries

4. **Create modular components**:
   ```
   .agents/skills/page-redesign/.temp/redesign/{PageName}/
   ├── {PageName}Redesign.tsx    # Main component
   ├── [SubComponents].tsx       # Extracted sub-components
   ├── mockData.ts               # Static text/URLs
   └── types.ts                  # TypeScript interfaces
   ```

5. **Apply architecture checklist**:
   - [ ] Logic in custom hooks
   - [ ] Props use `Readonly<T>`
   - [ ] No hardcoded hex values (use CSS variables)
   - [ ] Dark mode classes applied

---

## Phase 6: Integrate (Replace In-Place)

**Goal**: Replace original page with redesigned version.

1. **Backup original**: `{PageName}.tsx` → `{PageName}.tsx.bak`

2. **Copy redesigned component** to original location

3. **Preserve from original**:
   - Import statements for hooks/context
   - API integration (useQuery calls with same query keys)
   - Event handlers that affect app state
   - TypeScript types

4. **Update imports** in parent files if needed

5. **Verify integration**:
   - [ ] All useQuery hooks preserved
   - [ ] Context usage (useAuth, useOrganization) intact
   - [ ] Navigation callbacks working
   - [ ] CSS variables used (no hardcoded colors)
   - [ ] Responsive breakpoints maintained

---

## Phase 7: Cleanup

**Goal**: Remove temporary files.

1. Delete `.agents/skills/page-redesign/.temp/page-analysis.md`
2. Delete `.agents/skills/page-redesign/.temp/stitch-prompt.md`
3. Delete `.agents/skills/page-redesign/.temp/source.html`
4. Delete `.agents/skills/page-redesign/.temp/redesign/` directory
5. **Keep** `.bak` file for rollback option

---

## Color Mapping Reference

| Stitch Color | CSS Variable | Usage |
|--------------|--------------|-------|
| `#1a2b1f` | `var(--text-primary)` | Headings, primary text |
| `#4b5563` | `var(--text-secondary)` | Labels, secondary text |
| `#e0e9e0` | `var(--background)` | App shell only (header, sidebar) |
| `#f8f9f8` | `var(--surface)` | **Page content background**, cards |
| `#7da36d` | `var(--accent)` | Primary actions, brand color |
| `rgba(42,45,43,0.15)` | `var(--border)` | Borders, dividers |
| `#dc2626` | `var(--error)` | Error states, destructive actions |

**IMPORTANT**: Use `--surface` (`#f8f9f8`) as the page background, NOT `--background`.

For dark mode, add `.dark` class variants or use `dark:` Tailwind prefix.

---

## Troubleshooting

- **Stitch generation fails**: Check prompt length, simplify structure
- **HTML download fails**: Verify URL is quoted in bash command
- **Missing styles**: Check Tailwind config extraction, verify CSS variable mapping
- **TypeScript errors**: Run `tsc --noEmit` and fix type issues
- **Rollback needed**: `mv {PageName}.tsx.bak {PageName}.tsx`

---

## Example Usage

```
User: "Redesign the AgTimeDashboard page"

Agent:
1. Reads apps/agcore-web/src/app/AgTime/AgTimeDashboard.tsx
2. Analyzes: 4 stat cards, activity feed, date picker, tabs
3. Creates prompt with design system
4. Generates in Stitch (wait ~3-5 min)
5. User reviews in Stitch UI
6. Downloads HTML, converts to React
7. Replaces AgTimeDashboard.tsx
8. Cleans up temp files
```
