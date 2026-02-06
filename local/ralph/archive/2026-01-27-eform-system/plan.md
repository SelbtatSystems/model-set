---
branchName: "ralph/agtime-sprint"
projectName: "AgTime Module"
totalSprints: 15
startDate: "2026-01-27"
---

# AgTime Sprint Plan

Execute sprints 0-14 in order. Each task must pass ALL validation before marking complete.

**Existing Infrastructure**: `time_entries` table, TimeEntriesModule, BulkTimeEntryModal, `piece_entries`, PieceEntriesModule exist. Map spec's "employees" to `worker_assignments`.

---

## Sprint 0: Foundation & Code Audit

**Goal**: DB columns, shared components, seed data

### Database Tasks

- [ ] **0.1** Add worker status tracking columns
  - **File**: `db/migrations/20260127_worker_status_tracking.sql`
  - **Implementation**:
    ```sql
    ALTER TABLE worker_assignments ADD COLUMN IF NOT EXISTS current_status VARCHAR(10) DEFAULT 'out' CHECK (current_status IN ('in', 'out'));
    ALTER TABLE worker_assignments ADD COLUMN IF NOT EXISTS last_activity_at TIMESTAMPTZ;
    ALTER TABLE worker_assignments ADD COLUMN IF NOT EXISTS pin_code VARCHAR(4);
    ALTER TABLE worker_assignments ADD COLUMN IF NOT EXISTS biometric_registered_at TIMESTAMPTZ;
    ALTER TABLE worker_assignments ADD COLUMN IF NOT EXISTS geofencing_enabled BOOLEAN DEFAULT true;
    ```
  - **Validation**:
    - [ ] Migration file exists at path
    - [ ] Run via postgres-mcp: `mcp__postgres__execute_sql` - no errors
    - [ ] Query `SELECT current_status, geofencing_enabled FROM worker_assignments LIMIT 1` returns defaults
    - [ ] `mcp__postgres__get_object_details` shows all 5 new columns on worker_assignments

- [ ] **0.2** Add employee payroll/integration columns
  - **File**: `db/migrations/20260127_worker_payroll_columns.sql`
  - **Implementation**:
    ```sql
    ALTER TABLE worker_assignments ADD COLUMN IF NOT EXISTS employee_external_id VARCHAR(50);
    ALTER TABLE worker_assignments ADD COLUMN IF NOT EXISTS job_title VARCHAR(100);
    ALTER TABLE worker_assignments ADD COLUMN IF NOT EXISTS hourly_rate_override DECIMAL(10,2);
    ALTER TABLE worker_assignments ADD COLUMN IF NOT EXISTS permission_read_mytime BOOLEAN DEFAULT true;
    ALTER TABLE worker_assignments ADD COLUMN IF NOT EXISTS permission_write_mytime BOOLEAN DEFAULT false;
    ALTER TABLE worker_assignments ADD COLUMN IF NOT EXISTS notify_on_punch BOOLEAN DEFAULT false;
    ```
  - **Validation**:
    - [ ] Migration file exists
    - [ ] Execute via postgres-mcp - no errors
    - [ ] Query `SELECT employee_external_id, permission_read_mytime FROM worker_assignments LIMIT 1` works
    - [ ] Can UPDATE a row: `UPDATE worker_assignments SET employee_external_id='TEST-001' WHERE id=(SELECT id FROM worker_assignments LIMIT 1)`

- [ ] **0.3** Create worker_department_memberships junction table
  - **File**: `db/migrations/20260127_worker_dept_memberships.sql`
  - **Implementation**:
    ```sql
    CREATE TABLE IF NOT EXISTS worker_department_memberships (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      assignment_id UUID NOT NULL REFERENCES worker_assignments(id) ON DELETE CASCADE,
      dept_id UUID NOT NULL REFERENCES org_departments(id) ON DELETE CASCADE,
      hourly_rate DECIMAL(10,2),
      is_primary BOOLEAN DEFAULT false,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      UNIQUE(assignment_id, dept_id)
    );
    CREATE INDEX IF NOT EXISTS idx_worker_dept_membership_assignment ON worker_department_memberships(assignment_id);
    CREATE INDEX IF NOT EXISTS idx_worker_dept_membership_dept ON worker_department_memberships(dept_id);
    ```
  - **Validation**:
    - [ ] Table exists: `mcp__postgres__list_objects` shows worker_department_memberships
    - [ ] Columns correct: `mcp__postgres__get_object_details` for table
    - [ ] Insert test: Insert a row with valid assignment_id and dept_id
    - [ ] FK works: Delete fails if referencing non-existent assignment_id
    - [ ] Unique constraint: Second insert with same assignment_id+dept_id fails

- [ ] **0.4** Add performance indexes
  - **File**: `db/migrations/20260127_time_entry_indexes.sql`
  - **Implementation**:
    ```sql
    CREATE INDEX IF NOT EXISTS idx_time_entries_assignment_date ON time_entries(assignment_id, DATE(clock_in AT TIME ZONE 'Australia/Sydney'));
    CREATE INDEX IF NOT EXISTS idx_worker_assignments_org_status ON worker_assignments(org_id, status) WHERE status = 'active';
    CREATE INDEX IF NOT EXISTS idx_time_entries_clock_in ON time_entries(clock_in DESC);
    ```
  - **Validation**:
    - [ ] Migration runs without errors
    - [ ] `mcp__postgres__analyze_db_health` shows new indexes
    - [ ] EXPLAIN on `SELECT * FROM time_entries WHERE assignment_id='...' ORDER BY clock_in DESC` uses index

### Backend Entity Updates

- [ ] **0.5** Update WorkerAssignment entity with new columns
  - **File**: `backend/src/workers/entities/worker-assignment.entity.ts`
  - **Implementation**:
    - Add `@Column({ name: 'current_status', default: 'out' }) currentStatus: 'in' | 'out'`
    - Add `@Column({ name: 'last_activity_at', nullable: true }) lastActivityAt: Date`
    - Add `@Column({ name: 'pin_code', nullable: true }) pinCode: string`
    - Add `@Column({ name: 'biometric_registered_at', nullable: true }) biometricRegisteredAt: Date`
    - Add `@Column({ name: 'geofencing_enabled', default: true }) geofencingEnabled: boolean`
    - Add `@Column({ name: 'employee_external_id', nullable: true }) employeeExternalId: string`
    - Add `@Column({ name: 'job_title', nullable: true }) jobTitle: string`
    - Add `@Column({ name: 'hourly_rate_override', type: 'decimal', nullable: true }) hourlyRateOverride: number`
    - Add `@Column({ name: 'permission_read_mytime', default: true }) permissionReadMytime: boolean`
    - Add `@Column({ name: 'permission_write_mytime', default: false }) permissionWriteMytime: boolean`
    - Add `@Column({ name: 'notify_on_punch', default: false }) notifyOnPunch: boolean`
  - **Validation**:
    - [ ] File compiles: `cd backend && npx tsc --noEmit`
    - [ ] Entity has all 11 new properties
    - [ ] Column decorators use correct snake_case names

- [ ] **0.6** Create WorkerDepartmentMembership entity
  - **File**: `backend/src/workers/entities/worker-department-membership.entity.ts`
  - **Implementation**:
    ```typescript
    @Entity('worker_department_memberships')
    export class WorkerDepartmentMembership {
      @PrimaryGeneratedColumn('uuid') id: string;
      @Column({ name: 'assignment_id' }) assignmentId: string;
      @Column({ name: 'dept_id' }) deptId: string;
      @Column({ name: 'hourly_rate', type: 'decimal', nullable: true }) hourlyRate: number;
      @Column({ name: 'is_primary', default: false }) isPrimary: boolean;
      @CreateDateColumn({ name: 'created_at' }) createdAt: Date;
      @ManyToOne(() => WorkerAssignment) @JoinColumn({ name: 'assignment_id' }) assignment: WorkerAssignment;
      @ManyToOne(() => OrgDepartment) @JoinColumn({ name: 'dept_id' }) department: OrgDepartment;
    }
    ```
  - **Validation**:
    - [ ] File exists at path
    - [ ] Compiles without errors
    - [ ] Entity exported from module index
    - [ ] Relations correctly defined

- [ ] **0.7** Register entity in WorkersModule
  - **File**: `backend/src/workers/workers.module.ts`
  - **Implementation**:
    - Import WorkerDepartmentMembership
    - Add to TypeOrmModule.forFeature([..., WorkerDepartmentMembership])
  - **Validation**:
    - [ ] Module imports entity
    - [ ] Backend starts without errors: `cd backend && npm run start:dev` (check logs)

### Frontend Shared Components

- [ ] **0.8** Create DateTimePicker component
  - **File**: `packages/shared-ui/src/components/DateTimePicker/DateTimePicker.tsx`
  - **Implementation**:
    - Props: `{ value: Date, onChange: (date: Date) => void, showTime?: boolean, quickPresets?: string[] }`
    - Date input with calendar icon
    - Optional time picker (hour:minute AM/PM)
    - Quick presets: [Now] [6:00 AM] [7:00 AM] buttons
    - Uses existing CSS variables from agcore-web
  - **Validation**:
    - [ ] Component file exists
    - [ ] Exports from `packages/shared-ui/src/index.ts`
    - [ ] TypeScript compiles
    - [ ] Import works in agcore-web test file

- [ ] **0.9** Create DeductionSelect component
  - **File**: `packages/shared-ui/src/components/DeductionSelect/DeductionSelect.tsx`
  - **Implementation**:
    - Props: `{ value: number | 'auto', onChange: (val) => void, deductionType: string, onTypeChange: (type) => void }`
    - Dropdown options: Auto, None, 15min, 30min, 45min, 1h, 1.5h, 2h, Custom
    - Type dropdown: None, Lunch, Break, Leave (disabled when Auto selected)
    - Custom shows numeric input
  - **Validation**:
    - [ ] Component exists and exports
    - [ ] Type dropdown disabled when value='auto'
    - [ ] Custom input appears when 'Custom' selected
    - [ ] TypeScript compiles

- [ ] **0.10** Create VerificationBadge component
  - **File**: `packages/shared-ui/src/components/VerificationBadge/VerificationBadge.tsx`
  - **Implementation**:
    - Props: `{ type: 'biometric' | 'gps', status: 'ok' | 'flagged' | 'unknown' }`
    - Displays: biometric=👤, gps=📍
    - Status: ok=green checkmark, flagged=red !, unknown=gray ?
    - Tooltip on hover explaining status
  - **Validation**:
    - [ ] Component exists and exports
    - [ ] Renders all 6 combinations (2 types × 3 statuses)
    - [ ] Colors match: ok=green, flagged=red, unknown=gray

- [ ] **0.11** Create SelectionActionBar component
  - **File**: `packages/shared-ui/src/components/SelectionActionBar/SelectionActionBar.tsx`
  - **Implementation**:
    - Props: `{ count: number, onClear: () => void, primaryAction?: ReactNode, secondaryActions?: ReactNode[], moreActions?: { label: string, onClick: () => void, destructive?: boolean }[] }`
    - Fixed position bar at top of viewport when count > 0
    - Shows "{count} Employees Selected"
    - Primary action button, secondary buttons, More dropdown, X clear button
    - Slides in/out with animation
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │              {count} Employees Selected             │
    │ [Primary Action] [Secondary] [More ▼]           [X] │
    └─────────────────────────────────────────────────────┘
    ```
  - **Validation**:
    - [ ] Component exists and exports
    - [ ] Hidden when count=0
    - [ ] Shows when count > 0
    - [ ] X button calls onClear
    - [ ] More dropdown renders all items
    - [ ] Layout matches wireframe

### Seed Data

- [ ] **0.12** Create AgTime demo seed script
  - **File**: `scripts/seed-agtime-demo.ts`
  - **Implementation**:
    - Use TypeORM or raw SQL
    - Create 10 workers in worker_assignments (linked to existing test org)
    - Create 3 departments in org_departments
    - Create worker_department_memberships linking workers to depts
    - Create 50 time_entries across workers (various dates, some open)
    - Create 20 piece_entries
    - Set some workers to currentStatus='in' with open time entries
  - **Validation**:
    - [ ] Script runs: `npx ts-node scripts/seed-agtime-demo.ts`
    - [ ] Query shows 10 workers: `SELECT COUNT(*) FROM worker_assignments WHERE org_id='...'`
    - [ ] Query shows time entries exist
    - [ ] Some workers have currentStatus='in'

---

## Sprint 1: AgTime Employee List View

**Goal**: UnitsHours.tsx page with employee table, status, verification columns

### Backend Tasks

- [ ] **1.1** Create GET /workers/agtime-list endpoint
  - **File**: `backend/src/workers/workers.controller.ts`
  - **Implementation**:
    ```typescript
    @Get('agtime-list')
    async getAgtimeList(
      @Query('orgId') orgId: string,
      @Query('departmentId') departmentId?: string,
      @Query('status') status?: 'in' | 'out',
      @Query('search') search?: string,
      @Query('sortBy') sortBy?: 'name' | 'status' | 'lastActivity',
      @Query('sortOrder') sortOrder?: 'asc' | 'desc',
    ): Promise<{ workers: AgtimeWorkerDto[], total: number }>
    ```
    - Join with users table for name
    - Join with worker_department_memberships for primaryDepartment
    - Calculate verificationStatus from latest time_entry
    - Filter by departmentId, status, search (name ILIKE)
    - Sort by specified column
  - **Validation**:
    - [ ] Endpoint accessible: GET /workers/agtime-list?orgId=...
    - [ ] Returns workers with id, name, currentStatus, lastActivityAt
    - [ ] Returns primaryDepartment object
    - [ ] Returns verificationStatus object
    - [ ] Filter by departmentId works
    - [ ] Search by name works (partial match)
    - [ ] Sort by name works both directions

- [ ] **1.2** Create AgtimeWorkerDto
  - **File**: `backend/src/workers/dto/agtime-worker.dto.ts`
  - **Implementation**:
    ```typescript
    export class AgtimeWorkerDto {
      id: string;
      name: string;
      currentStatus: 'in' | 'out';
      lastActivityAt: Date | null;
      primaryDepartment: { id: string; name: string } | null;
      verificationStatus: { biometric: 'ok' | 'flagged' | 'unknown'; gps: 'ok' | 'flagged' | 'unknown' };
    }
    ```
  - **Validation**:
    - [ ] DTO file exists
    - [ ] All properties defined with correct types
    - [ ] Exported from dto/index.ts

- [ ] **1.3** Add getCurrentStatus helper to WorkersService
  - **File**: `backend/src/workers/workers.service.ts`
  - **Implementation**:
    ```typescript
    async getCurrentStatus(assignmentId: string): Promise<'in' | 'out'> {
      // Find latest time_entry for this assignment
      // If exists and clock_out is null → 'in'
      // Otherwise → 'out'
    }
    ```
  - **Validation**:
    - [ ] Method exists on service
    - [ ] Worker with open entry (clock_out=null) returns 'in'
    - [ ] Worker with closed entry returns 'out'
    - [ ] Worker with no entries returns 'out'

### Frontend Tasks

- [ ] **1.4** Create UnitsHours.tsx page
  - **File**: `apps/agcore-web/src/app/AgTime/UnitsHours.tsx`
  - **Implementation**:
    - Page title "Hours & Units" with search input
    - "Employees (N)" header with "+ Add Employee" button
    - Table with columns: Checkbox, Name, Department, Status, Verify, Action
    - Use React Query to fetch /workers/agtime-list
    - Loading and empty states
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ Hours & Units        [🔍 Search...]                 │
    ├─────────────────────────────────────────────────────┤
    │ Employees (34)                       [+ Add Employee]│
    ├─────────────────────────────────────────────────────┤
    │ [ ] Name (▲)   │ Department (Y) │ Status │ Verify  │ Action │
    ├────────────────┼────────────────┼────────┼─────────┼────────┤
    │ [ ] Abel Wea   │ Kent Paddock   │ 🔴 Out │ 👤✓ 📍✓│ ✏️  ❐ │
    │ [ ] Aleixo G.  │ Gauci Farming  │ 🟢 In  │ 👤! 📍✓│ ✏️  ❐ │
    └────────────────┴────────────────┴────────┴─────────┴────────┘
    ```
  - **Validation**:
    - [ ] File exists at path
    - [ ] Page renders without errors
    - [ ] Table shows employee rows from API
    - [ ] Loading spinner while fetching
    - [ ] Empty state when no employees
    - [ ] Layout matches wireframe

- [ ] **1.5** Create EmployeeTableRow component
  - **File**: `apps/agcore-web/src/app/AgTime/components/EmployeeTableRow.tsx`
  - **Implementation**:
    - Props: `{ worker: AgtimeWorker, selected: boolean, onSelect: () => void, onEdit: () => void, onDuplicate: () => void }`
    - Checkbox for selection
    - Name as clickable link
    - Department name
    - Status icon: 🟢 In / 🔴 Out
    - VerificationBadge components for biometric + gps
    - Action buttons: ✏️ edit, ❐ duplicate
  - **Validation**:
    - [ ] Component renders all columns
    - [ ] Checkbox toggles selected state
    - [ ] Name click navigates to profile (verify with console.log for now)
    - [ ] Status shows correct icon based on currentStatus
    - [ ] VerificationBadges render

- [ ] **1.6** Implement table sorting
  - **File**: `apps/agcore-web/src/app/AgTime/UnitsHours.tsx`
  - **Implementation**:
    - Sortable columns: Name, Status
    - Click header → sort ASC, click again → sort DESC
    - Visual indicator ▲/▼ on sorted column
    - Pass sortBy, sortOrder to API
  - **Validation**:
    - [ ] Click Name header → sorts A-Z
    - [ ] Click again → sorts Z-A
    - [ ] Arrow indicator shows on sorted column
    - [ ] Status sort: In first or Out first

- [ ] **1.7** Implement department filter dropdown
  - **File**: `apps/agcore-web/src/app/AgTime/UnitsHours.tsx`
  - **Implementation**:
    - Filter icon in Department column header
    - Click opens dropdown with department checkboxes
    - Multi-select: check departments to filter
    - Show employee count per department
    - "Clear" button to reset
  - **Validation**:
    - [ ] Filter icon visible in header
    - [ ] Click opens dropdown
    - [ ] Departments listed with counts
    - [ ] Check one → table filters
    - [ ] Check multiple → shows union
    - [ ] Clear resets filter

- [ ] **1.8** Implement search by name
  - **File**: `apps/agcore-web/src/app/AgTime/UnitsHours.tsx`
  - **Implementation**:
    - Search input in header area
    - Debounce 300ms before API call
    - Case-insensitive
    - Clear (X) button when text present
  - **Validation**:
    - [ ] Input visible in UI
    - [ ] Type "Abe" → waits 300ms → filters to matches
    - [ ] X button clears and shows all
    - [ ] Empty search shows all employees

- [ ] **1.9** Add route /agtime/hours-units
  - **File**: `apps/agcore-web/src/main.tsx`
  - **Implementation**:
    - Add route: `<Route path="/agtime/hours-units" element={<UnitsHours />} />`
    - Import UnitsHours component
  - **Validation**:
    - [ ] Navigate to localhost:3101/agtime/hours-units → page loads
    - [ ] Browser back button works
    - [ ] Direct URL access works

- [ ] **1.10** Add Hours & Units to sidebar navigation
  - **File**: `apps/agcore-web/src/components/Sidebar.tsx`
  - **Implementation**:
    - Add "Hours & Units" link under AgTime section
    - Icon: Clock or similar from Lucide
    - Active state when on /agtime/hours-units
  - **Validation**:
    - [ ] Link visible in sidebar
    - [ ] Click navigates to /agtime/hours-units
    - [ ] Active styling when on page

---

## Sprint 2: Employee Profile & Activity Table

**Goal**: Click employee → profile page with info card + time entry history

### Backend Tasks

- [ ] **2.1** Create GET /workers/:id/profile endpoint
  - **File**: `backend/src/workers/workers.controller.ts`
  - **Implementation**:
    ```typescript
    @Get(':id/profile')
    async getProfile(@Param('id') id: string): Promise<WorkerProfileDto> {
      // Return full profile with departments, permissions
    }
    ```
    Response includes: id, name, currentStatus, lastActivityAt, externalId, jobTitle, email, pinCode (masked), biometricRegisteredAt, geofencingEnabled, primaryDepartment, departments[], permissions
  - **Validation**:
    - [ ] Endpoint returns 200 for valid worker ID
    - [ ] Returns 404 for invalid ID
    - [ ] All expected fields present in response
    - [ ] departments array populated from memberships
    - [ ] pinCode returned as "****" not actual value

- [ ] **2.2** Create WorkerProfileDto
  - **File**: `backend/src/workers/dto/worker-profile.dto.ts`
  - **Implementation**:
    - All profile fields with proper types
    - Nested DepartmentMembershipDto for departments array
  - **Validation**:
    - [ ] DTO file exists
    - [ ] Types match API contract
    - [ ] Exported from index

- [ ] **2.3** Add netHours calculation to time entries
  - **File**: `backend/src/time-entries/time-entries.service.ts`
  - **Implementation**:
    - Add `calculateNetHours(entry: TimeEntry): number` method
    - Formula: (clockOut - clockIn - breakMinutes) / 60 in decimal hours
    - Handle null clockOut (return null or ongoing)
    - Include in GET /time-entries response
  - **Validation**:
    - [ ] Method exists on service
    - [ ] 6:00 AM to 4:00 PM with 30min break = 9.5 hours
    - [ ] 7:00 AM to 3:00 PM with 0 break = 8.0 hours
    - [ ] Null clockOut returns null

### Frontend Tasks

- [ ] **2.4** Create EmployeeProfile.tsx page
  - **File**: `apps/agcore-web/src/app/AgTime/EmployeeProfile.tsx`
  - **Implementation**:
    - Breadcrumb: Home / AgTime / {Employee Name}
    - Profile header with name, action buttons
    - Info card section
    - Activity table section
    - Fetch profile via useQuery
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ ← Back | 🏠 / AgTime / Abel Wea                     │
    ├─────────────────────────────────────────────────────┤
    │ Profile ▶ Abel Wea                                  │
    │ [Edit Profile] [Employee Details] [Print QR] [Bio]  │
    ├─────────────────────────────────────────────────────┤
    │ Name: Abel Wea           Primary Dept: Kent Paddock │
    │ ID: #EMP-001             Status: 🔴 Out             │
    ├─────────────────────────────────────────────────────┤
    │ Employee Activity                   [Create Manual] │
    ├─────────────┬────────┬───────┬───────┬──────┬──────┤
    │ Department  │ Date   │ In    │ Out   │ Ded. │ Hrs  │
    ├─────────────┼────────┼───────┼───────┼──────┼──────┤
    │ Kent Paddock│ Jan 26 │ 06:00 │ 04:00 │ 0.5  │ 9.5  │
    │ Kent Paddock│ Jan 25 │ 07:00 │ 03:00 │ 0.5  │ 7.5  │
    └─────────────┴────────┴───────┴───────┴──────┴──────┘
    ```
  - **Validation**:
    - [ ] Page renders at /agtime/employees/:id
    - [ ] Shows employee name in header
    - [ ] Breadcrumb navigation works
    - [ ] Loading state while fetching
    - [ ] Layout matches wireframe

- [ ] **2.5** Create EmployeeInfoCard component
  - **File**: `apps/agcore-web/src/app/AgTime/components/EmployeeInfoCard.tsx`
  - **Implementation**:
    - Grid layout with key-value pairs
    - Name, External ID, Primary Dept, Status (with icon)
    - Biometric status: "✅ Registered Jan 10" or "Not Registered"
    - Geofencing enabled indicator
  - **Validation**:
    - [ ] Component renders all fields
    - [ ] Status icon matches currentStatus (🟢/🔴)
    - [ ] Biometric shows date if registered
    - [ ] Handles null values gracefully

- [ ] **2.6** Create EmployeeActivityTable component
  - **File**: `apps/agcore-web/src/app/AgTime/components/EmployeeActivityTable.tsx`
  - **Implementation**:
    - Columns: Department, Date, In, Out, Deduction, Hours, Action
    - Fetch time entries for employee via API
    - Sort by date DESC (newest first)
    - Pagination: 10 per page
    - Action column: ✏️ edit, ❐ duplicate
  - **Validation**:
    - [ ] Table renders with correct columns
    - [ ] Data sorted newest first
    - [ ] Pagination controls work
    - [ ] Net hours calculated and displayed
    - [ ] Empty state when no entries

- [ ] **2.7** Add profile action buttons (placeholders)
  - **File**: `apps/agcore-web/src/app/AgTime/EmployeeProfile.tsx`
  - **Implementation**:
    - "Edit Profile" button → disabled, tooltip "Coming in Sprint 8"
    - "Employee Details" button → navigates to /workforce/employees/:id
    - "Print QR Card" button → disabled
    - "Biometric Verification" button → disabled
    - "Create Manual Entry" button → disabled, tooltip "Coming in Sprint 3"
  - **Validation**:
    - [ ] All 5 buttons visible
    - [ ] Employee Details navigates correctly
    - [ ] Disabled buttons show tooltips
    - [ ] Buttons styled consistently

- [ ] **2.8** Link employee name click to profile
  - **File**: `apps/agcore-web/src/app/AgTime/components/EmployeeTableRow.tsx`
  - **Implementation**:
    - Wrap name in Link or onClick handler
    - Navigate to `/agtime/employees/${worker.id}`
  - **Validation**:
    - [ ] Click name → navigates to profile
    - [ ] Profile loads with correct employee data
    - [ ] Back button returns to list

- [ ] **2.9** Add route /agtime/employees/:id
  - **File**: `apps/agcore-web/src/main.tsx`
  - **Implementation**:
    - Add route with id param
    - Import EmployeeProfile
  - **Validation**:
    - [ ] Direct URL access works
    - [ ] :id param passed to component

---

## Sprint 3: Time Entry CRUD

**Goal**: Create, edit, delete time entries from profile page

### Backend Tasks

- [ ] **3.1** Add auto-calculate deduction logic
  - **File**: `backend/src/time-entries/time-entries.service.ts`
  - **Implementation**:
    ```typescript
    calculateAutoDeduction(shiftMinutes: number, orgSettings: OrgTimeSettings): number {
      // Default: 30min if shift > 5hrs (300 min)
      // Use orgSettings.autoDeductionThreshold and autoDeductionMinutes
      if (shiftMinutes > (orgSettings.autoDeductionThreshold || 300)) {
        return orgSettings.autoDeductionMinutes || 30;
      }
      return 0;
    }
    ```
  - **Validation**:
    - [ ] 8hr shift → 30min deduction
    - [ ] 4hr shift → 0 deduction
    - [ ] Custom threshold (6hr) works
    - [ ] Custom deduction (45min) works

- [ ] **3.2** Add worker status sync on entry changes
  - **File**: `backend/src/time-entries/time-entries.service.ts`
  - **Implementation**:
    ```typescript
    async syncWorkerStatus(assignmentId: string): Promise<void> {
      // Find latest time_entry for assignment
      // If clock_out is null → update worker to 'in'
      // Otherwise → update worker to 'out'
      // Update last_activity_at to now
    }
    ```
    - Call after create, update, delete
  - **Validation**:
    - [ ] Create entry (in only) → worker status='in'
    - [ ] Add clock_out → worker status='out'
    - [ ] Delete open entry → worker status='out'
    - [ ] last_activity_at updated

### Frontend Tasks

- [ ] **3.3** Create ManualTimeEntryModal component
  - **File**: `apps/agcore-web/src/app/AgTime/components/ManualTimeEntryModal.tsx`
  - **Implementation**:
    - Modal with title "Manual Adjustment ▶ {Employee Name}"
    - Time In: DateTimePicker with quick presets [Now] [6:00 AM] [7:00 AM]
    - Time Out: DateTimePicker with quick presets [Now] [5:00 PM] [6:00 PM]
    - Deduction: DeductionSelect component
    - Department: Dropdown (worker's departments, primary marked)
    - Notes: Text input
    - Delete button (red, only in edit mode)
    - Save button
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ Manual Adjustment ▶ Abel Wea                        │
    ├─────────────────────────────────────────────────────┤
    │ Time In:   [📅 Jan 26, 2026 | 06:00 AM 🕒]         │
    │            [Now] [06:00 AM] [07:00 AM]              │
    │                                                     │
    │ Time Out:  [📅 Jan 26, 2026 | 04:00 PM 🕒]         │
    │            [Now] [05:00 PM] [06:00 PM]              │
    │                                                     │
    │ Deduction: [Auto ▼]    Type: [Lunch ▼]              │
    │                                                     │
    │ Department: [Kent Paddock (Primary) ▼]              │
    │                                                     │
    │ Notes:     [________________________________]       │
    │                                                     │
    │              [Delete]                 [Save]        │
    └─────────────────────────────────────────────────────┘
    ```
  - **Validation**:
    - [ ] Modal opens and closes
    - [ ] All form fields render
    - [ ] DateTimePicker presets work
    - [ ] DeductionSelect type disabled when Auto
    - [ ] Department defaults to primary
    - [ ] Delete button only shows in edit mode
    - [ ] Layout matches wireframe

- [ ] **3.4** Wire "Create Manual Entry" button
  - **File**: `apps/agcore-web/src/app/AgTime/EmployeeProfile.tsx`
  - **Implementation**:
    - Enable button (remove disabled)
    - onClick opens ManualTimeEntryModal in create mode
    - Pre-select worker's primary department
    - On save: POST /time-entries → refresh activity table
    - Show success toast
  - **Validation**:
    - [ ] Button enabled and clickable
    - [ ] Modal opens in create mode
    - [ ] Department pre-selected
    - [ ] Submit creates entry
    - [ ] Entry appears in table
    - [ ] Toast shows

- [ ] **3.5** Wire edit action in activity table
  - **File**: `apps/agcore-web/src/app/AgTime/components/EmployeeActivityTable.tsx`
  - **Implementation**:
    - ✏️ button opens ManualTimeEntryModal in edit mode
    - Pre-populate all fields from entry
    - On save: PATCH /time-entries/:id
    - Refresh table
  - **Validation**:
    - [ ] Click edit → modal opens
    - [ ] All fields populated correctly
    - [ ] Change time → save → table updated
    - [ ] Delete button visible

- [ ] **3.6** Implement delete with confirmation
  - **File**: `apps/agcore-web/src/app/AgTime/components/ManualTimeEntryModal.tsx`
  - **Implementation**:
    - Delete button shows confirmation dialog
    - "Delete this time entry?" with Cancel/Delete buttons
    - On confirm: DELETE /time-entries/:id
    - Close modal, refresh table
  - **Validation**:
    - [ ] Delete button shows dialog
    - [ ] Cancel closes dialog, keeps modal
    - [ ] Confirm deletes entry
    - [ ] Entry removed from table
    - [ ] Modal closes

- [ ] **3.7** Implement duplicate action
  - **File**: `apps/agcore-web/src/app/AgTime/components/EmployeeActivityTable.tsx`
  - **Implementation**:
    - ❐ button shows confirmation: "Copy this entry to today's date?"
    - On confirm: POST /time-entries with same data but date=today
    - Refresh table
  - **Validation**:
    - [ ] Duplicate button shows confirmation
    - [ ] Creates new entry for today
    - [ ] New entry appears in table
    - [ ] Original entry unchanged

- [ ] **3.8** Implement inline time editing
  - **File**: `apps/agcore-web/src/app/AgTime/components/EmployeeActivityTable.tsx`
  - **Implementation**:
    - Click In or Out time cell → inline time picker appears
    - Small popover with hour/minute/AM-PM inputs
    - Save on blur or Enter key
    - Cancel on Escape key
    - PATCH /time-entries/:id with new time
  - **Validation**:
    - [ ] Click time cell → editor appears
    - [ ] Change time → blur → saves
    - [ ] Enter key saves
    - [ ] Escape cancels without saving
    - [ ] Table cell updates

---

## Sprint 4: Piece Rate System

**Goal**: Enhance piece entry modal with "Save & Add Another"

### Frontend Tasks

- [ ] **4.1** Enhance PieceEntryModal to match spec
  - **File**: `apps/agcore-web/src/components/piece-entry/PieceEntryModal.tsx` (or create)
  - **Implementation**:
    - Title: "Piece Rate Entry ▶ {Employee Name}"
    - Date picker
    - Piece Type dropdown (fetch from /piece-types)
    - Quantity input (numeric, allows decimals)
    - Rate per Piece input (pre-filled from type, editable)
    - Auto-calculated Total Pay display
    - Department dropdown
    - Notes input
    - Buttons: [+ Save & Add Another] [Save Entry]
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ Piece Rate Entry ▶ Abel Wea                         │
    ├─────────────────────────────────────────────────────┤
    │ Date:           [Jan 26, 2026 📅]                   │
    │ Piece Type:     [Blueberry Crates ▼]                │
    │ Quantity:       [      45.00        ]               │
    │ Rate per Piece: [$     2.50         ] (pre-filled)  │
    │                                                     │
    │ ─────────── Auto-Calculated ───────────             │
    │ Total Pay:      $ 112.50                            │
    │                                                     │
    │ Department:     [Kent Paddock (Primary) ▼]          │
    │ Notes:          [______________________]            │
    │                                                     │
    │         [+ Save & Add Another]   [Save Entry]       │
    └─────────────────────────────────────────────────────┘
    ```
  - **Validation**:
    - [ ] Modal renders all fields
    - [ ] Piece Type dropdown populated
    - [ ] Rate auto-fills on type selection
    - [ ] Total updates live (qty × rate)
    - [ ] Both buttons visible
    - [ ] Layout matches wireframe

- [ ] **4.2** Implement piece type with auto-rate
  - **File**: `apps/agcore-web/src/components/piece-entry/PieceEntryModal.tsx`
  - **Implementation**:
    - Fetch piece types from GET /piece-types
    - On select: fill ratePerPiece with type's defaultRate
    - Allow manual override of rate
  - **Validation**:
    - [ ] Types load in dropdown
    - [ ] Select type → rate fills
    - [ ] Can edit rate manually
    - [ ] Rate persists after type change if edited

- [ ] **4.3** Implement live total calculation
  - **File**: `apps/agcore-web/src/components/piece-entry/PieceEntryModal.tsx`
  - **Implementation**:
    - Computed: total = quantity × ratePerPiece
    - Update on any input change
    - Display as currency: $X.XX
    - Handle NaN/invalid gracefully
  - **Validation**:
    - [ ] 4.5 qty × $2.50 rate = $11.25
    - [ ] 10 qty × $45.00 rate = $450.00
    - [ ] Empty qty shows $0.00
    - [ ] Decimal quantities work

- [ ] **4.4** Implement "Save & Add Another" button
  - **File**: `apps/agcore-web/src/components/piece-entry/PieceEntryModal.tsx`
  - **Implementation**:
    - Saves entry via POST /piece-entries
    - Clears ONLY quantity field
    - Keeps date, type, rate (sticky)
    - Shows success toast with total
    - Focus quantity field
  - **Validation**:
    - [ ] Click → entry saved
    - [ ] Toast shows "Entry saved: $X.XX"
    - [ ] Quantity cleared, others remain
    - [ ] Quantity field focused
    - [ ] Can immediately enter next qty

- [ ] **4.5** Add Piece Entries section to profile
  - **File**: `apps/agcore-web/src/app/AgTime/EmployeeProfile.tsx`
  - **Implementation**:
    - Add "Piece Entries" section below time entries
    - Or use tabs: "Time Entries" | "Piece Entries"
    - Table: Date, Type, Qty, Rate, Total, Action
    - Edit/delete actions
  - **Validation**:
    - [ ] Section/tab visible on profile
    - [ ] Table renders piece entries
    - [ ] Total column shows calculated pay
    - [ ] Edit/delete actions work

---

## Sprint 5: Employee Selection System

**Goal**: Multi-select employees, show action bar

### Frontend Tasks

- [ ] **5.1** Create SelectionContext
  - **File**: `apps/agcore-web/src/app/AgTime/context/SelectionContext.tsx`
  - **Implementation**:
    ```typescript
    interface SelectionState {
      selectedIds: Set<string>;
      selectAll: () => void;
      clearSelection: () => void;
      toggleSelection: (id: string) => void;
      isSelected: (id: string) => boolean;
      selectedCount: number;
      allSelectedAreIn: boolean; // computed from worker data
    }
    ```
  - **Validation**:
    - [ ] Context created and exported
    - [ ] Provider wraps UnitsHours page
    - [ ] toggleSelection adds/removes from Set
    - [ ] clearSelection empties Set
    - [ ] selectedCount reflects Set size

- [ ] **5.2** Add checkbox column to employee table
  - **File**: `apps/agcore-web/src/app/AgTime/UnitsHours.tsx`
  - **Implementation**:
    - Header checkbox: selects all visible
    - Row checkboxes: individual selection
    - Indeterminate state when partial selection
    - Use SelectionContext
  - **Validation**:
    - [ ] Header checkbox visible
    - [ ] Check header → all rows checked
    - [ ] Uncheck one → header indeterminate
    - [ ] Uncheck header → all unchecked
    - [ ] Individual checkboxes toggle

- [ ] **5.3** Wire SelectionActionBar
  - **File**: `apps/agcore-web/src/app/AgTime/UnitsHours.tsx`
  - **Implementation**:
    - Import SelectionActionBar from shared-ui
    - Show when selectedCount > 0
    - Display: "{count} Employees Selected"
    - X button calls clearSelection
    - Primary action based on allSelectedAreIn
  - **Validation**:
    - [ ] Bar hidden when none selected
    - [ ] Bar appears on first selection
    - [ ] Count updates correctly
    - [ ] X clears selection, hides bar

- [ ] **5.4** Implement selection-aware button logic
  - **File**: `apps/agcore-web/src/app/AgTime/UnitsHours.tsx`
  - **Implementation**:
    - If ALL selected workers have status='in': Show "Batch Check-Out"
    - Otherwise (any/all 'out'): Show "Batch Manual Punch"
    - Compute allSelectedAreIn from workers data
  - **Validation**:
    - [ ] Select 3 'in' workers → "Batch Check-Out" shown
    - [ ] Select mix of in/out → "Batch Manual Punch" shown
    - [ ] Select only 'out' → "Batch Manual Punch" shown

- [ ] **5.5** Create "More Actions" dropdown
  - **File**: `apps/agcore-web/src/app/AgTime/UnitsHours.tsx`
  - **Implementation**:
    - Dropdown in SelectionActionBar's moreActions prop
    - Options: Batch Edit, Print Cards, Set Department, Delete (destructive)
    - Each opens appropriate modal or action
  - **Validation**:
    - [ ] Dropdown opens on click
    - [ ] All 4 options visible
    - [ ] Delete styled as destructive (red)
    - [ ] Each option triggers handler (console.log for now)

---

## Sprint 6: Bulk Time Entry Operations

**Goal**: Batch manual punch and batch check-out

### Backend Tasks

- [ ] **6.1** Enhance POST /time-entries/bulk
  - **File**: `backend/src/time-entries/time-entries.controller.ts`
  - **Implementation**:
    ```typescript
    @Post('bulk')
    async createBulk(@Body() dto: BulkTimeEntryDto): Promise<{
      created: number;
      entries: TimeEntry[];
      errors: { assignmentId: string; error: string }[];
    }>
    ```
    - Accept 'primary' as departmentId to use each worker's primary dept
    - Create entries for each assignmentId
    - Sync worker status after each
    - Return partial success with errors
  - **Validation**:
    - [ ] Endpoint accepts array of assignmentIds
    - [ ] Creates entries for all
    - [ ] 'primary' departmentId uses worker's primary
    - [ ] Returns created count and entries
    - [ ] Partial failure returns errors array

- [ ] **6.2** Create POST /time-entries/bulk-checkout
  - **File**: `backend/src/time-entries/time-entries.controller.ts`
  - **Implementation**:
    ```typescript
    @Post('bulk-checkout')
    async bulkCheckout(@Body() dto: BulkCheckoutDto): Promise<{
      updated: number;
      entries: TimeEntry[];
    }>
    ```
    - Find open entries (clock_out IS NULL) for each assignmentId
    - Update clock_out to provided time
    - Apply breakMinutes if provided
    - Sync worker status
  - **Validation**:
    - [ ] Endpoint exists
    - [ ] Finds open entries for workers
    - [ ] Sets clock_out
    - [ ] Worker status changes to 'out'
    - [ ] Returns updated count

- [ ] **6.3** Create POST /time-entries/bulk-edit
  - **File**: `backend/src/time-entries/time-entries.controller.ts`
  - **Implementation**:
    - Accept assignmentIds, date, and partial entry fields
    - Find entries for that date
    - Update specified fields
  - **Validation**:
    - [ ] Endpoint exists
    - [ ] Edits entries for specified date
    - [ ] Only updates provided fields
    - [ ] Returns updated entries

### Frontend Tasks

- [ ] **6.4** Create BatchManualPunchModal
  - **File**: `apps/agcore-web/src/app/AgTime/components/BatchManualPunchModal.tsx`
  - **Implementation**:
    - Title: "Batch Manual Time Entry"
    - Time In/Out with DateTimePicker + presets
    - Deduction dropdown
    - Department: "(Primary)" as first option, then list all
    - Notes input
    - "Create Batch Entry" button
    - Selected employees table at bottom
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ Batch Manual Time Entry                             │
    ├─────────────────────────────────────────────────────┤
    │ Time In:   [📅 Jan 26, 2026 | 06:00 AM 🕒]         │
    │            [Now] [06:00 AM] [07:00 AM]              │
    │                                                     │
    │ Time Out:  [📅 Jan 26, 2026 | 04:00 PM 🕒]         │
    │            [Now] [04:00 PM] [05:00 PM]              │
    │                                                     │
    │ Deduction: [30 min ▼]    Type: [Lunch ▼]           │
    │                                                     │
    │ Department: [(Primary) ▼]                           │
    │                                                     │
    │ Notes:     [________________________________]       │
    │                                                     │
    │                   [Create Batch Entry]              │
    ├─────────────────────────────────────────────────────┤
    │ Selected Employees (3)                              │
    │ Name          │ Department │ Status │ Last Activity │
    │ Abel Wea      │ Kent       │ 🔴 Out │ Jan 25 04:00 │
    │ Aleixo Gusmao │ Gauci      │ 🔴 Out │ Jan 25 03:30 │
    └─────────────────────────────────────────────────────┘
    ```
  - **Validation**:
    - [ ] Modal renders all fields
    - [ ] Shows selected workers in table
    - [ ] Primary option in department dropdown
    - [ ] Submit calls bulk endpoint
    - [ ] Layout matches wireframe

- [ ] **6.5** Create BatchCheckoutModal
  - **File**: `apps/agcore-web/src/app/AgTime/components/BatchCheckoutModal.tsx`
  - **Implementation**:
    - Title: "Batch Check-Out"
    - Time Out only (DateTimePicker + presets)
    - Deduction dropdown
    - "Create Batch Check-Out" button
    - Selected employees table (shows clock-in times)
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ Batch Check-Out                                     │
    ├─────────────────────────────────────────────────────┤
    │ Time Out:  [📅 Jan 26, 2026 | 04:00 PM 🕒]         │
    │            [Now] [05:00 PM] [06:00 PM]              │
    │                                                     │
    │ Deduction: [30 min ▼]    Type: [Lunch ▼]           │
    │                                                     │
    │                   [Create Batch Check-Out]          │
    ├─────────────────────────────────────────────────────┤
    │ Selected Employees (3) - All Clocked In             │
    │ Name          │ Department │ Clocked In            │
    │ Abel Wea      │ Kent       │ 06:00 AM              │
    └─────────────────────────────────────────────────────┘
    ```
  - **Validation**:
    - [ ] Only shows Time Out (no Time In)
    - [ ] Shows clock-in time for each worker
    - [ ] Submit calls bulk-checkout endpoint
    - [ ] Layout matches wireframe

- [ ] **6.6** Wire action buttons to modals
  - **File**: `apps/agcore-web/src/app/AgTime/UnitsHours.tsx`
  - **Implementation**:
    - "Batch Manual Punch" → opens BatchManualPunchModal
    - "Batch Check-Out" → opens BatchCheckoutModal
    - Pass selected workers to modals
  - **Validation**:
    - [ ] Button clicks open correct modals
    - [ ] Selected workers passed correctly
    - [ ] Modal closes on success

- [ ] **6.7** Implement (Primary) department option
  - **File**: `apps/agcore-web/src/app/AgTime/components/BatchManualPunchModal.tsx`
  - **Implementation**:
    - First option: "(Primary)" - each worker uses their primary
    - Send 'primary' string to API
    - Backend resolves to actual department per worker
  - **Validation**:
    - [ ] Primary is first option
    - [ ] Selecting Primary sends 'primary' to API
    - [ ] Created entries have correct departments

- [ ] **6.8** Handle success/error feedback
  - **File**: `apps/agcore-web/src/app/AgTime/components/BatchManualPunchModal.tsx`
  - **Implementation**:
    - Success: toast "3 entries created", clear selection, refresh table
    - Partial: toast with error details for failed workers
    - Full failure: error message in modal
  - **Validation**:
    - [ ] Full success → toast + refresh
    - [ ] Partial → toast shows which failed
    - [ ] Modal closes on success
    - [ ] Selection cleared

---

## Sprint 7: Batch Piece Entry Wizard

**Goal**: Sequential piece entry wizard for multiple workers

### Backend Tasks

- [ ] **7.1** Ensure POST /piece-entries/bulk exists
  - **File**: `backend/src/piece-entries/piece-entries.controller.ts`
  - **Implementation**:
    ```typescript
    @Post('bulk')
    async createBulk(@Body() dto: BulkPieceEntryDto): Promise<{
      created: number;
      entries: PieceEntry[];
      totalPay: number;
    }>
    ```
  - **Validation**:
    - [ ] Endpoint exists
    - [ ] Creates multiple entries
    - [ ] Returns total pay sum

### Frontend Tasks

- [ ] **7.2** Create BatchPieceEntryWizard component
  - **File**: `apps/agcore-web/src/app/AgTime/components/BatchPieceEntryWizard.tsx`
  - **Implementation**:
    - Modal with wizard steps
    - Header: "Piece Entry Wizard | Step X of Y: {Worker Name}"
    - Date picker (sticky across steps)
    - Piece Type dropdown (sticky)
    - Quantity input (auto-focused, clears each step)
    - Rate input (pre-filled, sticky)
    - Department dropdown
    - Notes input
    - [Skip] [Save & Next Employee →] buttons
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ ➔ Piece Entry Wizard | Step 2 of 3: Aleixo Gusmao  │
    ├─────────────────────────────────────────────────────┤
    │ Date:        [Jan 26, 2026 📅] (Sticky)             │
    │                                                     │
    │ Piece Type:  [Blueberry Bins ▼] (Sticky)           │
    │                                                     │
    │ Quantity:    [_____4.5_____] ← AUTO-FOCUSED        │
    │                                                     │
    │ Rate:        [$ 45.00      ] (Pre-filled)          │
    │                                                     │
    │ Department:  [Gauci - Primary ▼]                   │
    │                                                     │
    │ Notes:       [________________________________]     │
    ├─────────────────────────────────────────────────────┤
    │ [Skip]                     [Save & Next Employee ➔] │
    └─────────────────────────────────────────────────────┘
    ```
  - **Validation**:
    - [ ] Modal shows first worker
    - [ ] Step indicator updates
    - [ ] Quantity auto-focused
    - [ ] Sticky values persist
    - [ ] Layout matches wireframe

- [ ] **7.3** Implement wizard state management
  - **File**: `apps/agcore-web/src/app/AgTime/components/BatchPieceEntryWizard.tsx`
  - **Implementation**:
    ```typescript
    const [state, setState] = useState<{
      workers: Worker[];
      currentIndex: number;
      entries: Map<string, PieceEntryDraft>;
      stickyValues: { date: string; pieceTypeId: string; rate: number };
    }>();
    ```
  - **Validation**:
    - [ ] State tracks all workers
    - [ ] currentIndex increments
    - [ ] entries Map stores drafts
    - [ ] Sticky values used for next worker

- [ ] **7.4** Implement Skip functionality
  - **File**: `apps/agcore-web/src/app/AgTime/components/BatchPieceEntryWizard.tsx`
  - **Implementation**:
    - Skip button increments currentIndex
    - No entry saved for skipped worker
    - If last worker, go to review
  - **Validation**:
    - [ ] Skip moves to next worker
    - [ ] Skipped worker not in entries Map
    - [ ] Skip on last → review screen

- [ ] **7.5** Implement "Save & Next" button
  - **File**: `apps/agcore-web/src/app/AgTime/components/BatchPieceEntryWizard.tsx`
  - **Implementation**:
    - Validate quantity > 0
    - Save draft to entries Map
    - Move to next worker
    - Auto-focus quantity
    - If last worker, go to review
  - **Validation**:
    - [ ] Validates quantity
    - [ ] Saves to Map
    - [ ] Next worker shown
    - [ ] Quantity focused

- [ ] **7.6** Create Review & Submit screen
  - **File**: `apps/agcore-web/src/app/AgTime/components/BatchPieceEntryWizard.tsx`
  - **Implementation**:
    - After last worker, show review
    - Table: Employee, Quantity, Rate, Total
    - Skipped workers shown as "(skipped)"
    - Grand total row
    - [← Back to Edit] [Submit All Entries] buttons
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ Review Piece Entries                                │
    ├─────────────────────────────────────────────────────┤
    │ Employee       │ Quantity │ Rate   │ Total         │
    │ Abel Wea       │ 4.5      │ $45.00 │ $202.50       │
    │ Aleixo Gusmao  │ 3.0      │ $45.00 │ $135.00       │
    │ (skipped)      │ -        │ -      │ -             │
    ├─────────────────────────────────────────────────────┤
    │ TOTAL                               │ $337.50       │
    │                                                     │
    │ [← Back to Edit]              [Submit All Entries] │
    └─────────────────────────────────────────────────────┘
    ```
  - **Validation**:
    - [ ] Review shows after last worker
    - [ ] All entries listed
    - [ ] Skipped shown
    - [ ] Total calculated correctly
    - [ ] Back goes to last worker
    - [ ] Layout matches wireframe

- [ ] **7.7** Add progress indicator
  - **File**: `apps/agcore-web/src/app/AgTime/components/BatchPieceEntryWizard.tsx`
  - **Implementation**:
    - Progress bar: filled based on currentIndex/workers.length
    - Text: "Step X of Y: {Worker Name}"
  - **Validation**:
    - [ ] Progress bar visible
    - [ ] Updates on navigation
    - [ ] Shows worker name

---

## Sprint 8: Edit Employee Profile

**Goal**: Full employee edit form

### Backend Tasks

- [ ] **8.1** Create PATCH /workers/:id/profile endpoint
  - **File**: `backend/src/workers/workers.controller.ts`
  - **Implementation**:
    - Accept partial profile updates
    - Validate unique employeeExternalId per org
    - Return updated profile
  - **Validation**:
    - [ ] Endpoint updates provided fields
    - [ ] Rejects duplicate externalId
    - [ ] Returns updated profile

- [ ] **8.2** Create PUT /workers/:id/departments endpoint
  - **File**: `backend/src/workers/workers.controller.ts`
  - **Implementation**:
    - Replace all department memberships
    - Validate exactly one isPrimary=true
    - Cascade delete old, insert new
  - **Validation**:
    - [ ] Replaces all memberships
    - [ ] Enforces one primary
    - [ ] Returns updated memberships

### Frontend Tasks

- [ ] **8.3** Create EditEmployeeProfile.tsx page
  - **File**: `apps/agcore-web/src/app/AgTime/EditEmployeeProfile.tsx`
  - **Implementation**:
    - Breadcrumb: AgTime / {Name} / Edit Profile
    - Sections: Basic Info, Payroll, Security, Notifications
    - Form fields per wireframe
    - Save/Delete buttons
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ ← Back | AgTime / Abel Wea / Edit Profile           │
    ├─────────────────────────────────────────────────────┤
    │ Name:         [Abel Wea_______________] (Required)  │
    │ Org's:        [Gauci Farming         ] (Read-only)  │
    │ Primary Dept: [Kent Paddock        ▼] [Edit Depts]  │
    ├─────────────────────────────────────────────────────┤
    │ ──── Payroll & Integration (Xero/MYOB) ────        │
    │ Employee ID:  [EMP-001_______________] (Required)   │
    │ Job Title:    [Employee            ▼]               │
    │ Base Rate:    [Auto                  ]              │
    ├─────────────────────────────────────────────────────┤
    │ ──── Security & Verification ──────────            │
    │ 4-Digit PIN:  [****] [👁]                          │
    │ Biometric:    [✅ Registered Jan 10] [Reset Face]  │
    │ Geofencing:   ☑ Enforce GPS Safe-Zones             │
    ├─────────────────────────────────────────────────────┤
    │ ──── Notifications & Access ──────────             │
    │ Notifications: ☐ Email admin on Check-In/Out       │
    │ Login Email:   [abel@email.com______]              │
    │ App Access:    [Send Invite]                       │
    │ Permissions:   ☑ Read MyTime  ☐ Write MyTime       │
    ├─────────────────────────────────────────────────────┤
    │ [Delete Employee]                   [Save Profile] │
    └─────────────────────────────────────────────────────┘
    ```
  - **Validation**:
    - [ ] Page renders at /agtime/employees/:id/edit
    - [ ] All sections visible
    - [ ] Form fields populated from API
    - [ ] Layout matches wireframe

- [ ] **8.4** Implement basic info section
  - **File**: `apps/agcore-web/src/app/AgTime/EditEmployeeProfile.tsx`
  - **Implementation**:
    - Name input (required)
    - Primary dept dropdown
    - "Edit Depts" button → opens DepartmentMembershipModal
  - **Validation**:
    - [ ] Name validates required
    - [ ] Dept dropdown populated
    - [ ] Edit Depts opens modal

- [ ] **8.5** Implement payroll section
  - **File**: `apps/agcore-web/src/app/AgTime/EditEmployeeProfile.tsx`
  - **Implementation**:
    - External ID (required, unique validation)
    - Job title dropdown: Employee, Management, External, Admin
    - Base rate: "Auto" or numeric override
  - **Validation**:
    - [ ] External ID validates unique
    - [ ] Job title dropdown works
    - [ ] Rate toggle between Auto and override

- [ ] **8.6** Implement security section
  - **File**: `apps/agcore-web/src/app/AgTime/EditEmployeeProfile.tsx`
  - **Implementation**:
    - PIN: 4 digit input, masked (****), reveal toggle (eye icon)
    - Biometric status display
    - Reset Face button (placeholder action)
    - Geofencing checkbox
  - **Validation**:
    - [ ] PIN masked by default
    - [ ] Eye icon reveals PIN
    - [ ] Biometric status shows correctly
    - [ ] Geofencing saves

- [ ] **8.7** Implement notifications section
  - **File**: `apps/agcore-web/src/app/AgTime/EditEmployeeProfile.tsx`
  - **Implementation**:
    - Checkbox: Email admin on punch (notifyOnPunch)
    - Email input
    - Send Invite button (placeholder)
    - Permissions: Read MyTime, Write MyTime checkboxes
  - **Validation**:
    - [ ] All checkboxes toggle
    - [ ] Email validates format
    - [ ] Send Invite shows toast "Coming soon"

- [ ] **8.8** Create DepartmentMembershipModal
  - **File**: `apps/agcore-web/src/app/AgTime/components/DepartmentMembershipModal.tsx`
  - **Implementation**:
    - Table: Department, Hourly Rate, Member checkbox, Primary radio
    - List all org departments
    - Check Member to add, uncheck to remove
    - Radio for primary (one required)
    - Save calls PUT /workers/:id/departments
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ Department Membership ▶ Abel Wea                    │
    ├─────────────────────────────────────────────────────┤
    │ Department      │ Hourly Rate │ Member │ Primary   │
    │ ────────────────┼─────────────┼────────┼───────────│
    │ Kent Paddock    │ [$25.00   ] │ ☑ ░░░░ │ ◉         │
    │ Gauci Farming   │ [$22.00   ] │ ☐      │ ○         │
    │ Packing Shed    │ [$20.00   ] │ ☐      │ ○         │
    │                                                     │
    │                    [Cancel]    [Save]               │
    └─────────────────────────────────────────────────────┘
    ```
  - **Validation**:
    - [ ] Shows all departments
    - [ ] Can add/remove memberships
    - [ ] Primary radio enforces one
    - [ ] Save updates backend
    - [ ] Layout matches wireframe

- [ ] **8.9** Implement delete employee
  - **File**: `apps/agcore-web/src/app/AgTime/EditEmployeeProfile.tsx`
  - **Implementation**:
    - Confirmation: "Delete {Name}? This cannot be undone."
    - Soft delete: PATCH status='inactive'
    - Navigate to /agtime/hours-units
    - Success toast
  - **Validation**:
    - [ ] Confirmation dialog shows
    - [ ] Cancel closes dialog
    - [ ] Confirm soft-deletes
    - [ ] Worker hidden from list
    - [ ] Navigates after delete

---

## Sprint 9: Create Employee Flow

**Goal**: Create new employee from scratch

### Backend Tasks

- [ ] **9.1** Create POST /workers endpoint
  - **File**: `backend/src/workers/workers.controller.ts`
  - **Implementation**:
    - Required: name, orgId, primaryDepartmentId, employeeExternalId
    - Auto-generate unique PIN
    - Create worker_assignment
    - Create primary department membership
    - Optionally send welcome email
    - Return worker with generatedPinCode
  - **Validation**:
    - [ ] Creates worker_assignment row
    - [ ] Creates membership with isPrimary=true
    - [ ] Returns generated PIN
    - [ ] Rejects duplicate externalId

- [ ] **9.2** Add auto-generate unique PIN helper
  - **File**: `backend/src/workers/workers.service.ts`
  - **Implementation**:
    ```typescript
    async generateUniquePIN(orgId: string): Promise<string> {
      // Generate 4-digit PIN
      // Check uniqueness within org
      // Retry if collision (max 10 attempts)
    }
    ```
  - **Validation**:
    - [ ] Returns 4-digit string
    - [ ] Unique within org
    - [ ] Works with existing PINs

### Frontend Tasks

- [ ] **9.3** Create AddEmployeeDropdown
  - **File**: `apps/agcore-web/src/app/AgTime/components/AddEmployeeDropdown.tsx`
  - **Implementation**:
    - Button: "+ Add Employee" with dropdown arrow
    - Options: Create Employee, Send eForm, Workers Portal
    - Create → /agtime/employees/new
    - Others → placeholder navigation
  - **Wireframe**:
    ```
    [+ Add Employee ▼]
    ├── 👤 Create Employee
    ├── 📱 Send eForm
    └── 🔍 Workers Portal
    ```
  - **Validation**:
    - [ ] Dropdown opens on click
    - [ ] Create navigates correctly
    - [ ] Others navigate or show "coming soon"
    - [ ] Layout matches wireframe

- [ ] **9.4** Create CreateEmployee.tsx page
  - **File**: `apps/agcore-web/src/app/AgTime/CreateEmployee.tsx`
  - **Implementation**:
    - Form with all creation fields
    - Sections: Basic, Payroll, Security, Access
    - PIN shows "Auto-generated on create"
    - Create button submits
    - Cancel returns to list
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ Create New Employee                                 │
    ├─────────────────────────────────────────────────────┤
    │ Name:         [Enter full name...   ] (Required)    │
    │ Primary Org:  [Gauci Farming      ▼]               │
    │ Primary Dept: [Select Department  ▼] (Required)    │
    ├─────────────────────────────────────────────────────┤
    │ ──── Payroll Setup ────                            │
    │ Employee ID:  [e.g. EMP-001       ] (Required)     │
    │ Job Title:    [Select Title     ▼]                 │
    │ Base Rate:    [$0.00              ]                │
    ├─────────────────────────────────────────────────────┤
    │ ──── Security & Onboarding ────                    │
    │ Registration: [📷 Face Scan] [🖨️ Print QR]        │
    │ 4-Digit PIN:  [Auto-generated on create]           │
    │ Geofencing:   ☑ Enable GPS Safe-Zones             │
    ├─────────────────────────────────────────────────────┤
    │ ──── Access ────                                   │
    │ Email:        [employee@email.com ]                │
    │ Permissions:  ☑ Read MyTime  ☐ Write MyTime       │
    │ Onboarding:   ☑ Send Welcome email                │
    ├─────────────────────────────────────────────────────┤
    │ [Cancel]                         [Create Employee] │
    └─────────────────────────────────────────────────────┘
    ```
  - **Validation**:
    - [ ] Page renders at /agtime/employees/new
    - [ ] All form fields present
    - [ ] Cancel navigates back
    - [ ] Layout matches wireframe

- [ ] **9.5** Implement form validation
  - **File**: `apps/agcore-web/src/app/AgTime/CreateEmployee.tsx`
  - **Implementation**:
    - Required: name, primaryDept, employeeExternalId
    - Email format validation if provided
    - Show validation errors inline
    - Disable submit until valid
  - **Validation**:
    - [ ] Submit without name → error shown
    - [ ] Invalid email → error shown
    - [ ] Valid form → button enabled

- [ ] **9.6** Wire navigation flow
  - **File**: `apps/agcore-web/src/main.tsx`
  - **Implementation**:
    - Add route /agtime/employees/new
    - After create success → navigate to /agtime/employees/:newId
    - Pass generated PIN in state for display
  - **Validation**:
    - [ ] Route accessible
    - [ ] Create → redirects to new profile
    - [ ] New profile shows generated PIN toast

---

## Sprint 10: AgTime Dashboard

**Goal**: Main dashboard with stats, quick actions, activity feed

### Backend Tasks

- [ ] **10.1** Create GET /agtime/dashboard-stats endpoint
  - **File**: `backend/src/agtime/agtime.controller.ts` (create module if needed)
  - **Implementation**:
    - Query params: orgId, date (optional, defaults to today)
    - Return: activeWorkers, totalHours, totalPieces, pendingAlerts
  - **Validation**:
    - [ ] Returns correct counts
    - [ ] Respects date filter
    - [ ] activeWorkers = workers with status='in'

- [ ] **10.2** Create GET /agtime/activity-feed endpoint
  - **File**: `backend/src/agtime/agtime.controller.ts`
  - **Implementation**:
    - Return recent time entries with worker info
    - Include verification status
    - Limit param, default 10
    - Sort by clock_in DESC
  - **Validation**:
    - [ ] Returns recent activity
    - [ ] Includes worker name
    - [ ] Sorted newest first

### Frontend Tasks

- [ ] **10.3** Enhance AgTimeDashboard.tsx
  - **File**: `apps/agcore-web/src/app/AgTime/AgTimeDashboard.tsx`
  - **Implementation**:
    - Greeting: "Good Morning/Afternoon, {User}!"
    - Date picker with presets (Today, Yesterday, This Week)
    - Stat cards row
    - Quick action buttons
    - Activity feed table
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ ← Back | 🏠 / AgTime                                │
    ├─────────────────────────────────────────────────────┤
    │ Good Morning, Admin!         [Today ▼] [📅 Jan 27] │
    │ Here's what's happening on the farm today.          │
    │                                                     │
    │ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐        │
    │ │ACTIVE  │ │TOTAL   │ │PIECES  │ │ALERTS  │        │
    │ │WORKERS │ │HOURS   │ │TODAY   │ │        │        │
    │ │  24    │ │ 184.5  │ │82 Bins │ │  5 ⚠️  │        │
    │ └────────┘ └────────┘ └────────┘ └────────┘        │
    ├─────────────────────────────────────────────────────┤
    │ QUICK ACTIONS                                       │
    │ [+ New Punch] [🧺 Piece Entry] [👤 Add] [⎙ Cards] │
    ├─────────────────────────────────────────────────────┤
    │ LIVE ACTIVITY FEED              [View All Activity] │
    │ Time │ Employee      │ Event    │ Verify │ Status  │
    │ 06:15│ Abel Wea      │ Clock-In │ ✓  ✓  │ 🟢      │
    │ 06:10│ Aleixo Gusmao │ Clock-In │ !  ✓  │ ⚠️      │
    └─────────────────────────────────────────────────────┘
    ```
  - **Validation**:
    - [ ] Dashboard renders
    - [ ] Stats populated from API
    - [ ] Date picker changes data
    - [ ] Layout matches wireframe

- [ ] **10.4** Create StatCard component
  - **File**: `apps/agcore-web/src/app/AgTime/components/StatCard.tsx`
  - **Implementation**:
    - Props: icon, label, value, onClick
    - Clickable card navigates (e.g., Active Workers → filtered list)
  - **Validation**:
    - [ ] Card renders icon, label, value
    - [ ] Click triggers onClick
    - [ ] Hover state

- [ ] **10.5** Create QuickActionButtons component
  - **File**: `apps/agcore-web/src/app/AgTime/components/QuickActionButtons.tsx`
  - **Implementation**:
    - + New Punch → ManualTimeEntryModal (global worker picker)
    - Piece Entry → PieceEntryModal (global)
    - Add Worker → /agtime/employees/new
    - Print Cards → placeholder
  - **Validation**:
    - [ ] All 4 buttons render
    - [ ] New Punch opens modal
    - [ ] Add Worker navigates

- [ ] **10.6** Create ActivityFeed component
  - **File**: `apps/agcore-web/src/app/AgTime/components/ActivityFeed.tsx`
  - **Implementation**:
    - Fetch activity feed from API
    - Columns: Time, Employee, Event, Verify, Status
    - Flagged rows highlighted
    - "View All Activity" link → /agtime/hours-units
  - **Validation**:
    - [ ] Feed renders entries
    - [ ] Time formatted nicely
    - [ ] Flagged entries highlighted
    - [ ] Link navigates

- [ ] **10.7** Implement date picker
  - **File**: `apps/agcore-web/src/app/AgTime/AgTimeDashboard.tsx`
  - **Implementation**:
    - Preset buttons: Today, Yesterday, This Week
    - Custom date picker
    - Updates stats and feed for selected date
  - **Validation**:
    - [ ] Today selected by default
    - [ ] Click Yesterday → data changes
    - [ ] Custom date works

---

## Sprint 11: Settings Page

**Goal**: Configure time tracking settings

### Backend Tasks

- [ ] **11.1** Extend org_time_settings table
  - **File**: `db/migrations/20260127_extend_time_settings.sql`
  - **Implementation**: Add columns for date_format, time_format, hours_display, rounding, face_scan_mode, gps_mode, etc.
  - **Validation**:
    - [ ] Migration runs
    - [ ] All columns exist

- [ ] **11.2** Extend settings endpoints
  - **File**: `backend/src/time-entries/time-entries.controller.ts`
  - **Implementation**: Add new fields to GET/PATCH settings
  - **Validation**:
    - [ ] GET returns new fields
    - [ ] PATCH updates new fields

### Frontend Tasks

- [ ] **11.3** Create TimeSettings.tsx page
  - **File**: `apps/agcore-web/src/app/AgTime/TimeSettings.tsx`
  - **Implementation**: Full settings form per wireframe
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ Settings ▶ Time & Attendance                        │
    ├─────────────────────────────────────────────────────┤
    │ ──── General Configuration ────                    │
    │ Attendance Mode: [Time Tracking ▼]                 │
    │ Date Format:     [DD/MM/YYYY ▼]  Time: [12h ▼]    │
    │ Hours Display:   [Decimal ▼]  Rounding: [15 min ▼]│
    ├─────────────────────────────────────────────────────┤
    │ ──── Security & Reliability ────                   │
    │ Face Scan:       (●) Required  ( ) Optional  ( ) Off│
    │                  [Sensitivity: Standard ▼]          │
    │ GPS Geofencing:  ( ) Off  (●) Flag  ( ) Enforce   │
    │                  [Radius: 200m ▼]                   │
    │ Offline Sync:    ☑ Enable AgSync                   │
    ├─────────────────────────────────────────────────────┤
    │ ──── Payroll & Piece Rates ────                    │
    │ Overtime Start:  [7.0 Hours ▼]  Closing: [Mon ▼]  │
    │ Frequency:       [Weekly ▼]                        │
    │                                                     │
    │ Piece Rate Definitions:                             │
    │ ┌──────────┬──────┬────────┬────────┬────────┐    │
    │ │ Name     │ Unit │ Weight │ Rate   │ Action │    │
    │ │ Longan   │ Bin  │ 15.0   │ $45.00 │ ✏️ 🗑️ │    │
    │ │ [+ Add New Piece Rate]                      │    │
    │ └──────────────────────────────────────────────┘   │
    ├─────────────────────────────────────────────────────┤
    │                                   [Save Settings]  │
    └─────────────────────────────────────────────────────┘
    ```
  - **Validation**:
    - [ ] Page renders at /agtime/settings
    - [ ] All sections visible
    - [ ] Save persists changes
    - [ ] Layout matches wireframe

- [ ] **11.4-11.7** Implement settings sections
  - General config, security, payroll sections
  - **Validation**: Each section saves correctly

- [ ] **11.8** Create AddPieceRateModal
  - **File**: `apps/agcore-web/src/app/AgTime/components/AddPieceRateModal.tsx`
  - **Implementation**: Modal for adding new piece rate definitions
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ Add Piece Rate                                      │
    ├─────────────────────────────────────────────────────┤
    │ Name:    [________________]                         │
    │ Unit:    [Bin ▼]                                    │
    │ Weight:  [____.__ kg] (optional)                    │
    │ Rate:    [$ __.__]                                  │
    │                                                     │
    │              [Cancel]         [Save]                │
    └─────────────────────────────────────────────────────┘
    ```
  - **Validation**:
    - [ ] Modal opens from piece rate table
    - [ ] All fields present
    - [ ] Save creates piece type
    - [ ] Layout matches wireframe

---

## Sprint 12: Reports System

**Goal**: Report gallery, preview, export

### Backend Tasks

- [ ] **12.1** Create GET /reports/daily-summary endpoint
  - **Validation**: Returns grouped data with subtotals

- [ ] **12.2** Create GET /reports/activity-log endpoint
  - **Validation**: Returns activity with verification

- [ ] **12.3** Create GET /reports/piece-summary endpoint
  - **Validation**: Aggregates piece data correctly

- [ ] **12.4** Create GET /reports/:type/export endpoint
  - **Validation**: Downloads valid CSV/Excel

### Frontend Tasks

- [ ] **12.5** Create ReportsPage.tsx
  - **File**: `apps/agcore-web/src/app/AgTime/ReportsPage.tsx`
  - **Implementation**: Report gallery with categories, filters, preview/export
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ AgCore Reports          [All Organizations ▼]       │
    ├─────────────────────────────────────────────────────┤
    │ CATEGORIES              FILTERS                     │
    │ ┌──────────────────┐   ┌─────────────────────┐     │
    │ │ 🔍 [Search...]   │   │ Date Range          │     │
    │ │ ⭐ Favorites     │   │ [This Week] [Custom]│     │
    │ │ 🕒 Time          │   │ [01/01] to [07/01]  │     │
    │ │   > Daily Summary│   │                     │     │
    │ │   > Activity Log │   │ Departments         │     │
    │ │ 🧺 Piece Rate    │   │ [All Departments ▼] │     │
    │ │ 📊 Payroll       │   │                     │     │
    │ └──────────────────┘   │ Grouping            │     │
    │                        │ (●) By Department   │     │
    │                        └─────────────────────┘     │
    │                                                     │
    │       [👁️ Preview]           [📥 Download]         │
    └─────────────────────────────────────────────────────┘
    ```
  - **Validation**:
    - [ ] UI renders
    - [ ] Categories work
    - [ ] Layout matches wireframe

- [ ] **12.6-12.9** Report preview, rendering, export, favorites
  - **Validation**: Full reporting flow works

---

## Sprint 13: GPS & Live Map (Frontend Only)

**Goal**: Live field map UI placeholder

- [ ] **13.1-13.8** Create LiveFieldMap.tsx with map integration, geofences, worker pins, clustering, selection panel
  - **Validation**: Map renders, pins show, interactions work

---

## Sprint 14: Biometric Enrollment (Frontend Only)

**Goal**: Face scan enrollment UI placeholder

- [ ] **14.1-14.7** Create BiometricEnrollment.tsx with camera access, step progress, guided instructions, completion flow
  - **File**: `apps/agcore-web/src/app/AgTime/BiometricEnrollment.tsx`
  - **Implementation**: Face scan enrollment with 3-step guided capture
  - **Wireframe**:
    ```
    ┌─────────────────────────────────────────────────────┐
    │ Biometric Enrollment ▶ Abel Wea                     │
    ├─────────────────────────────────────────────────────┤
    │   [ Camera Feed ]                                   │
    │   ┌────────────────────────────────────┐           │
    │   │           /─────────\              │           │
    │   │          |  O     O  |             │           │
    │   │          |    ___    |             │           │
    │   │           \_________/              │           │
    │   └────────────────────────────────────┘           │
    │   Status: 🟡 Waiting for alignment...               │
    ├─────────────────────────────────────────────────────┤
    │ Step 1: Center   Step 2: Left    Step 3: Right     │
    │ [██████ 100%]    [████░░ 40%]    [░░░░░░  0%]     │
    ├─────────────────────────────────────────────────────┤
    │ "Slowly tilt your head to the left..."              │
    │                                                     │
    │ Tips: No sunglasses/hat, well-lit area             │
    ├─────────────────────────────────────────────────────┤
    │ [Cancel]                     [Save Biometric ID]   │
    └─────────────────────────────────────────────────────┘
    ```
  - **Validation**:
    - [ ] Camera prompts for permission
    - [ ] Steps progress through 3 stages
    - [ ] Completion saves biometric_registered_at
    - [ ] Layout matches wireframe

---

## Summary

| Sprint | Goal | Tasks |
|--------|------|-------|
| 0 | Foundation | 12 |
| 1 | Employee List | 10 |
| 2 | Profile Page | 9 |
| 3 | Time Entry CRUD | 8 |
| 4 | Piece Entries | 5 |
| 5 | Selection System | 5 |
| 6 | Bulk Time Ops | 8 |
| 7 | Piece Wizard | 7 |
| 8 | Edit Profile | 9 |
| 9 | Create Employee | 6 |
| 10 | Dashboard | 7 |
| 11 | Settings | 8 |
| 12 | Reports | 9 |
| 13 | Live Map | 8 |
| 14 | Biometrics | 7 |

**Total**: ~118 tasks
