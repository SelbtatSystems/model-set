---
name: page-redesign
description: Redesigns existing React pages through Stitch generation with automated conversion. Generates page content only (no app shell).
allowed-tools: mcp__stitch__* Read Write Edit Bash Glob Grep WebFetch AskUserQuestion
---

# Page Redesign Skill

You are a **Page Redesign Engineer**. Your job is to transform existing React pages through Stitch UI generation and convert them back to production-ready React components.

**Critical constraint**: Only generate **page content** for `PageRenderer` — headers, sidebars, and breadcrumbs are already handled by the app shell. Every Stitch prompt MUST state this explicitly.

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

## Stitch Rate Limiting

**After every Stitch MCP call**, wait 1 minute before making the next call:

```bash
sleep 60
```

This applies to ALL `mcp__stitch__*` calls: `generate_screen_from_text`, `get_screen`, `list_screens`, etc. No exceptions.

---

## Phase 1: Analyze Existing Page

**Goal**: Document current functionality and identify all components before redesign.

1. **Read the target page file** and ALL its imported local components
2. **Identify and document**:
   - **Functionality**: Event handlers, API calls (useQuery, useMutation), state (useState, useReducer), custom hooks
   - **Layout**: Component hierarchy, grid/flex structure, responsive breakpoints
   - **Navigation**: Internal navigation (tabs, links), external routing (useNavigate)
   - **Accessibility**: ARIA labels, keyboard nav, semantic elements
   - **Data dependencies**: Props, context usage, query keys
   - **Component map**: Every local component imported by this page — file path, what it renders, what props/data it needs
3. **Write analysis** to `/tmp/page-redesign/page-analysis.md`

Use this template:

```markdown
# Page Analysis: {PageName}
**File**: apps/agcore-web/src/app/{path}/{PageName}.tsx

## Component Map
| Component | File | Renders | Props/Data |
|-----------|------|---------|------------|
| {PageName} | {path} | Parent layout | useQuery(...), useAuth |
| StatsBar | ./StatsBar.tsx | 4 metric cards | stats: Stats[] |
| ActivityFeed | ./ActivityFeed.tsx | Scrollable list | entries: Entry[] |
| ... | ... | ... | ... |

## Functionality
- API calls: [list endpoints with query keys]
- State: [useState/useReducer hooks]
- Hooks: [custom hooks used]
- Event handlers: [key interactions]

## Layout Structure
- [component tree with grid/flex details]
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
```

---

## Phase 2: Create Stitch Prompt

**Goal**: Use the `enhance-prompt` skill to Build a single prompt for the ENTIRE page, describing all components as sections.

1. **Read `/tmp/page-redesign/page-analysis.md`**
2. **Construct prompt** — the prompt MUST describe each component from the Component Map as a labeled section of the page:

```markdown
A professional {page type} with sage green accents and clean data visualization.

**IMPORTANT: This is PAGE CONTENT ONLY.** This page is rendered inside a PageRenderer
that already provides the app header, sidebar navigation, and breadcrumbs.
Do NOT include any header, sidebar, top navigation bar, or breadcrumb trail.
Start directly with the page content.

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
1. **{Component1 section}**: {What it shows, layout details}
2. **{Component2 section}**: {What it shows, layout details}
3. **{Component3 section}**: {What it shows, layout details}
...

**Functional Notes:**
- {Key interactions to preserve}
- {Data display requirements}
```

4. **Output** to `/tmp/page-redesign/stitch-prompt.md`

---

## Phase 3: Generate in Stitch

**Goal**: Create ONE screen for the entire page.

1. **Get project ID**: `17628915167374403984` (from DESIGN.md)
2. **Call Stitch MCP**:
   ```
   mcp__stitch__generate_screen_from_text
     projectId: "17628915167374403984"
     prompt: [contents of /tmp/page-redesign/stitch-prompt.md]
     deviceType: "DESKTOP"
     modelId: "GEMINI_3_PRO"
   ```
3. **Wait 1 minute** (rate limiting):
   ```bash
   sleep 60
   ```
4. **Wait 4 minutes** for generation to complete. Stitch is slow — calling too early will fail:
   ```bash
   sleep 240
   ```
5. **Call `mcp__stitch__get_screen`** to verify the screen exists and retrieve the `screenId`.
6. **Wait 1 minute** (rate limiting):
   ```bash
   sleep 60
   ```
7. **Retry if not found**: If `get_screen` fails or returns no screen data, wait 5 more minutes and try once more:
   ```bash
   sleep 300
   ```
   Call `get_screen` again. Wait 1 minute after. If it still fails, report the failure to the user.
8. **Store returned `screenId`**

---

## Phase 4: Convert to React (via react-components skill)

**Goal**: Use the `react-components` skill to convert Stitch HTML into modular React components.

### 4a: Set up workspace

Create the workspace and copy in the react-components scaffolding from its source location:

```bash
mkdir -p /tmp/page-redesign/redesign
cp -r /home/ziteht/model-set/skills/react-components/scripts /tmp/page-redesign/redesign/
cp -r /home/ziteht/model-set/skills/react-components/resources /tmp/page-redesign/redesign/
cp /home/ziteht/model-set/skills/react-components/package.json /tmp/page-redesign/redesign/
cp /home/ziteht/model-set/skills/react-components/package-lock.json /tmp/page-redesign/redesign/
cd /tmp/page-redesign/redesign && npm install
```

### 4b: Download HTML

Use the react-components fetch script (AI fetch tools fail on Google Cloud Storage):
```bash
bash /tmp/page-redesign/redesign/scripts/fetch-stitch.sh "[htmlCode.downloadUrl]" "/tmp/page-redesign/redesign/temp/source.html"
```

### 4c: Convert following react-components rules

Follow the `react-components` SKILL.md execution steps:

1. **Extract Tailwind config** from the HTML `<head>`, sync with `/tmp/page-redesign/redesign/resources/style-guide.json`
2. **Create `src/data/mockData.ts`** with static text/URLs from the design
3. **Draft components** using `/tmp/page-redesign/redesign/resources/component-template.tsx` as base — replace all `StitchComponent` placeholders with actual names
4. **Run validation** on each component:
   ```bash
   cd /tmp/page-redesign/redesign && npm run validate src/components/{Component}.tsx
   ```
5. **Verify against** `/tmp/page-redesign/redesign/resources/architecture-checklist.md`:
   - [ ] Logic extracted to custom hooks
   - [ ] No monolithic files — modular components
   - [ ] All static text in mockData.ts
   - [ ] Props use `Readonly<T>`
   - [ ] No hardcoded hex values — use theme-mapped Tailwind classes
   - [ ] Dark mode (`dark:`) applied
   - [ ] Google license headers removed

### 4d: Map output to original component structure

After react-components produces its modular output, map the generated components back to the original page's component structure from the Phase 1 Component Map:

- **Direct match**: A generated component clearly maps to an original component → use it
- **Stitch merged sections**: Two original components became one visual block in Stitch → keep them merged as one component. Adopt Stitch's layout.
- **Stitch split a section**: One original component became multiple in the output → keep the split if it makes sense, or recombine
- **New structure**: If Stitch restructured the layout in a way that's better than the original → adopt the new structure

**Do NOT force the output into the old component tree.** The goal is a better design, not a 1:1 copy of the old file organization.

---

## Phase 5: Integrate (Replace In-Place)

**Goal**: Replace original page with redesigned version, preserving all business logic.

1. **Backup originals**: `{Component}.tsx` → `{Component}.tsx.bak` for each file being replaced

2. **Copy components** from `/tmp/page-redesign/redesign/src/components/` to the original page directory

3. **Re-attach business logic** from the originals:
   - Import statements for hooks/context (`useAuth`, `useOrganization`, etc.)
   - API integration (`useQuery`/`useMutation` calls with same query keys)
   - Event handlers that affect app state
   - TypeScript types and interfaces
   - Replace mockData references with real data hooks where applicable

4. **Map CSS** — replace any remaining theme-mapped Tailwind classes with CSS variables:
   - `#1a2b1f` → `var(--text-primary)`
   - `#4b5563` → `var(--text-secondary)`
   - `#7da36d` → `var(--accent)`
   - `#f8f9f8` → `var(--surface)`
   - `rgba(42,45,43,0.15)` → `var(--border)`
   - `#dc2626` → `var(--error)`

5. **Update imports** in parent files if component names or structure changed

6. **Verify integration**:
   - [ ] All useQuery hooks preserved
   - [ ] Context usage (useAuth, useOrganization) intact
   - [ ] Navigation callbacks working
   - [ ] CSS variables used (no hardcoded colors)
   - [ ] Responsive breakpoints maintained
   - [ ] No header/sidebar/breadcrumbs in generated components

---

## Phase 6: Cleanup

**Goal**: Remove temporary files.

1. Delete entire `/tmp/page-redesign/` directory (workspace, prompts, HTML, everything)
2. **Keep** `.bak` files for rollback option

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
- **Validation fails**: Fix issues reported by `npm run validate`, re-run
- **Rollback needed**: Restore from `.bak` files
- **Screen not found after 10 min**: Retry after 5 more min (built into Phase 3)
- **Rate limiting errors**: Ensure 1 min sleep after every Stitch MCP call

---

## Example Usage

```
User: "Redesign the AgTimeDashboard page"

Agent:
1. Reads AgTimeDashboard.tsx + StatsBar.tsx + ActivityFeed.tsx + TimeChart.tsx
2. Documents component map: 4 components, their props, shared state
3. Creates ONE Stitch prompt describing full page with all sections
4. Generates in Stitch (sleep 60 rate limit + sleep 600 wait)
5. Retrieves screen (sleep 60 rate limit)
6. Sets up react-components workspace in /tmp/page-redesign/redesign/
7. Downloads HTML, converts to modular React, validates
8. Maps output back to component structure (merges/splits as needed)
9. Replaces originals, re-attaches useQuery/useAuth/handlers
10. Cleans up /tmp/page-redesign/, keeps .bak files
```
