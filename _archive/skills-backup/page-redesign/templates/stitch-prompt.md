# Stitch Prompt Template

Use this template structure when generating prompts for Stitch.

---

## Template

```
A professional {page type} with sage green accents and clean data visualization.
This is PAGE CONTENT ONLY - no header, sidebar, or navigation chrome.

**DESIGN SYSTEM (REQUIRED):**
- Platform: Web, Desktop-first (2560px canvas)
- Theme: Light mode, professional agricultural SaaS
- Background: Transparent (inherits from app shell)
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
3. **{Section 3}**: {Description}
...

**Functional Notes:**
- {Key interaction 1}
- {Key interaction 2}
- {Data display requirement 1}
```

---

## Keywords Reference

From DESIGN.md Section 9, use these for consistency:

**Aesthetic Keywords:**
- "Sage green accents"
- "Warm neutral backgrounds"
- "Softly rounded corners"
- "Manrope font family"
- "Material icons outlined"
- "Professional SaaS aesthetic"
- "Agricultural/workforce context"

**Mood Keywords:**
- Organic
- Professional
- Airy
- Utilitarian
- Grounded

---

## Example: Dashboard Page

```
A professional workforce dashboard with sage green accents and clean data visualization.
This is PAGE CONTENT ONLY - no header, sidebar, or navigation chrome.

**DESIGN SYSTEM (REQUIRED):**
- Platform: Web, Desktop-first (2560px canvas)
- Theme: Light mode, professional agricultural SaaS
- Background: Transparent (inherits from app shell)
- Primary Accent: Sage Field Green (#7da36d)
- Text Primary: Deep Forest (#1a2b1f)
- Text Secondary: Muted Gray (#4b5563)
- Font: Manrope, clean sans-serif
- Corners: Gently rounded (8px radius)
- Shadows: Minimal, whisper-soft
- Icons: Material Symbols Outlined (FILL 0, WGHT 400)

**Page Structure:**
1. **Metric Cards Row**: Four stat cards showing Total Hours, Active Workers, Pending Approvals, and Overtime Hours. Each card has an icon, large metric value, and trend percentage.
2. **Activity Feed**: Scrollable list of recent clock-in/out events with employee avatars, timestamps, and status badges.
3. **Quick Actions Bar**: Buttons for common tasks - Add Time Entry, Export Report, View Schedule.

**Functional Notes:**
- Metric cards should be clickable to drill down
- Activity feed auto-refreshes every 30 seconds
- Date range picker controls all displayed data
```

---

## Example: Data Table Page

```
A professional employee management table with sage green accents and bulk action capabilities.
This is PAGE CONTENT ONLY - no header, sidebar, or navigation chrome.

**DESIGN SYSTEM (REQUIRED):**
- Platform: Web, Desktop-first (2560px canvas)
- Theme: Light mode, professional agricultural SaaS
- Background: Transparent (inherits from app shell)
- Primary Accent: Sage Field Green (#7da36d)
- Text Primary: Deep Forest (#1a2b1f)
- Text Secondary: Muted Gray (#4b5563)
- Font: Manrope, clean sans-serif
- Corners: Gently rounded (8px radius)
- Shadows: Minimal, whisper-soft
- Icons: Material Symbols Outlined (FILL 0, WGHT 400)

**Page Structure:**
1. **Filter Bar**: Search input, department dropdown, status filter chips (All, Active, Inactive).
2. **Data Table**: Columns for checkbox, Employee (avatar + name), ID, Department, Status, Last Clock In, Actions dropdown.
3. **Bulk Actions Bar**: Appears when rows selected - shows count and batch operations (Assign, Export, Archive).
4. **Pagination**: Page numbers with prev/next, items per page selector.

**Functional Notes:**
- Sortable columns with click-to-sort headers
- Row hover highlights entire row
- Checkbox in header selects all visible rows
- Actions dropdown has Edit, View History, Deactivate options
```
