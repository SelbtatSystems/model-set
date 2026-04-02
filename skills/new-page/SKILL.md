---
name: new-page
description: Creates new React pages from a text description. Enhances the prompt, generates in Stitch, converts to production React components, and integrates into the app. This skill should be used when the user wants to create a new page that doesn't exist yet.
allowed-tools: mcp__stitch__* Read Write Edit Bash Glob Grep WebFetch AskUserQuestion
---

# New Page

You are a **Page Builder**. The user describes a page they want, and you handle everything: prompt enhancement, Stitch generation, React conversion, and app integration.

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

## Phase 1: Enhance the Prompt

**Goal**: Transform the user's description into an optimized Stitch prompt using the `enhance-prompt` skill patterns.

1. **Read `DESIGN.md`** in the project root to extract the design system block
2. **Apply enhance-prompt techniques** to the user's description:
   - Replace vague terms with specific UI/UX keywords
   - Add structure with numbered page sections
   - Format colors as `Descriptive Name (#hex) for role`
   - Amplify the vibe with descriptive adjectives
3. **Prepend the PageRenderer constraint** — every prompt MUST include:

```markdown
**IMPORTANT: This is PAGE CONTENT ONLY.** This page is rendered inside a PageRenderer
that already provides the app header, sidebar navigation, and breadcrumbs.
Do NOT include any header, sidebar, top navigation bar, or breadcrumb trail.
Start directly with the page content.
```

4. **Include the design system block** from `DESIGN.md`. If no `DESIGN.md` exists, use the default:

```markdown
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
```

5. **Write enhanced prompt** to `/tmp/new-page/stitch-prompt.md`

---

## Phase 2: Generate in Stitch

**Goal**: Create ONE screen for the entire page.

1. **Get project ID**: `17628915167374403984` (from DESIGN.md)
2. **Call Stitch MCP**:
   ```
   mcp__stitch__generate_screen_from_text
     projectId: "17628915167374403984"
     prompt: [contents of /tmp/new-page/stitch-prompt.md]
     deviceType: "DESKTOP"
     modelId: "GEMINI_3_PRO"
   ```
3. **Wait 1 minute** (rate limiting):
   ```bash
   sleep 60
   ```
4. **Wait 10 minutes** for generation to complete. Stitch is slow — calling too early will fail:
   ```bash
   sleep 600
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

## Phase 3: Convert to React (via react-components skill)

**Goal**: Use the `react-components` skill to convert Stitch HTML into modular React components.

### 3a: Set up workspace

Create the workspace and copy in the react-components scaffolding:

```bash
mkdir -p /tmp/new-page/redesign
cp -r /home/ziteht/model-set/skills/react-components/scripts /tmp/new-page/redesign/
cp -r /home/ziteht/model-set/skills/react-components/resources /tmp/new-page/redesign/
cp /home/ziteht/model-set/skills/react-components/package.json /tmp/new-page/redesign/
cp /home/ziteht/model-set/skills/react-components/package-lock.json /tmp/new-page/redesign/
cd /tmp/new-page/redesign && npm install
```

### 3b: Download HTML

Use the react-components fetch script (AI fetch tools fail on Google Cloud Storage):
```bash
bash /tmp/new-page/redesign/scripts/fetch-stitch.sh "[htmlCode.downloadUrl]" "/tmp/new-page/redesign/temp/source.html"
```

### 3c: Convert following react-components rules

Follow the `react-components` SKILL.md execution steps:

1. **Extract Tailwind config** from the HTML `<head>`, sync with `/tmp/new-page/redesign/resources/style-guide.json`
2. **Create `src/data/mockData.ts`** with static text/URLs from the design
3. **Draft components** using `/tmp/new-page/redesign/resources/component-template.tsx` as base — replace all `StitchComponent` placeholders with actual names
4. **Run validation** on each component:
   ```bash
   cd /tmp/new-page/redesign && npm run validate src/components/{Component}.tsx
   ```
5. **Verify against** `/tmp/new-page/redesign/resources/architecture-checklist.md`:
   - [ ] Logic extracted to custom hooks
   - [ ] No monolithic files — modular components
   - [ ] All static text in mockData.ts
   - [ ] Props use `Readonly<T>`
   - [ ] No hardcoded hex values — use theme-mapped Tailwind classes
   - [ ] Dark mode (`dark:`) applied
   - [ ] Google license headers removed

---

## Phase 4: Integrate into App

**Goal**: Place the new page into the agcore app with proper routing and data wiring.

1. **Determine target location** — ask the user or infer from the page description:
   ```
   apps/agcore-web/src/app/{FeatureArea}/{PageName}/
   ├── {PageName}.tsx          # Main page component
   ├── [SubComponents].tsx     # Extracted sub-components
   └── types.ts                # TypeScript interfaces
   ```

2. **Copy components** from `/tmp/new-page/redesign/src/components/` to the target directory

3. **Map CSS** — replace any remaining hardcoded hex values with CSS variables:
   - `#1a2b1f` → `var(--text-primary)`
   - `#4b5563` → `var(--text-secondary)`
   - `#7da36d` → `var(--accent)`
   - `#f8f9f8` → `var(--surface)`
   - `rgba(42,45,43,0.15)` → `var(--border)`
   - `#dc2626` → `var(--error)`

4. **Wire data layer** — replace mockData with real hooks where applicable:
   - Add `useQuery`/`useMutation` for API data
   - Add context hooks (`useAuth`, `useOrganization`) as needed
   - Add `useNavigate` for any navigation actions

5. **Register the page route** — add the page to the app's routing config so `PageRenderer` can render it

6. **Verify integration**:
   - [ ] CSS variables used (no hardcoded colors)
   - [ ] TypeScript compiles (`tsc --noEmit`)
   - [ ] Page renders inside PageRenderer (no header/sidebar/breadcrumbs in component)
   - [ ] Route registered and accessible

---

## Phase 5: Cleanup

**Goal**: Remove temporary files.

1. Delete entire `/tmp/new-page/` directory

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

---

## Troubleshooting

- **Stitch generation fails**: Check prompt length, simplify structure
- **HTML download fails**: Verify URL is quoted in bash command
- **Missing styles**: Check Tailwind config extraction, verify CSS variable mapping
- **TypeScript errors**: Run `tsc --noEmit` and fix type issues
- **Validation fails**: Fix issues reported by `npm run validate`, re-run
- **Screen not found after 10 min**: Retry after 5 more min (built into Phase 2)
- **Rate limiting errors**: Ensure 1 min sleep after every Stitch MCP call

---

## Example Usage

```
User: "I need a page where employees can submit expense reports
       with receipt uploads and category selection"

Agent:
1. Enhances prompt: adds UI keywords, design system, page structure,
   PageRenderer constraint
2. Writes enhanced prompt to /tmp/new-page/stitch-prompt.md
3. Generates in Stitch (sleep 60 + sleep 600 wait)
4. Retrieves screen (sleep 60 rate limit, retry +5 min if needed)
5. Sets up react-components workspace in /tmp/new-page/redesign/
6. Downloads HTML, converts to modular React, validates
7. Copies components to apps/agcore-web/src/app/Expenses/SubmitExpense/
8. Maps hex → CSS variables, wires useQuery/useAuth, registers route
9. Cleans up /tmp/new-page/
```
