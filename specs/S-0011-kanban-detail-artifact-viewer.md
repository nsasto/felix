# S-0011: Kanban Detail Run Artifacts Viewer

## Narrative

As a developer reviewing requirement work history, I need a unified view that shows both the requirement context and the complete run history with artifacts, so I can quickly understand what the requirement is, see all past runs, and dive into specific run details without juggling multiple windows.

**This is a REDESIGN of the existing RequirementDetailSlideOut component.** The current implementation uses a 6-tab layout (Metadata, Report, Output Log, Plan Snapshot, Specification, History) where all tabs are at the same hierarchy level. This design is confusing because it conflates requirement-level information with run-level artifacts.

**Problem with Current Design**:

- Metadata, Specification are requirement-level (always relevant)
- Report, Output Log, Plan Snapshot are run-level (only relevant for a specific run)
- History tab lets you select runs, but it's unclear how that affects the artifact tabs
- No clear visual hierarchy between "selecting a run" and "viewing that run's artifacts"

**New Design Principle**: Requirement-level information (spec, metadata) is always relevant. Run-level artifacts (report, logs, plan) are only relevant when reviewing a specific run. These are separate concerns and should be presented separately with clear visual hierarchy.

## Acceptance Criteria

### Layout & Navigation

- [x] Slide-out displays exactly 2 top-level tabs: "Overview" and "Run History"
- [x] Default tab on open: "Overview" always (consistent entry point)
- [x] ESC key closes slide-out
- [x] Slide-out width remains 60vw (min 500px, max 800px)
- [x] Slide-out animates in from right side
- [x] Backdrop dims and closes on click
- [x] Clicking a requirement card in kanban opens slide-out

### Tab 1: Overview

- [x] Tab labeled "Overview" with 📋 icon
- [x] Single scrollable column containing two sections:
  - **Metadata section** (top): status badge, priority badge, last updated timestamp, labels as tags, dependency list with clickable requirement IDs
  - **Specification section** (below): Full markdown-rendered spec from specs/ directory
- [x] Metadata section uses existing RequirementDetailSlideOut styling
- [x] Specification renders with same markdown styling as RunArtifactViewer spec tab

### Tab 2: Run History (Master-Detail Split)

- [x] Tab labeled "Run History" with 🕐 icon
- [x] Split layout: left master list (~40% width), right detail panel (~60% width)
- [x] Master list (left side):
  - [x] Shows all runs filtered to current requirement ID only
  - [x] Each list item displays: run ID, timestamp, status badge, exit code
  - [x] Sorted by timestamp descending (newest first)
  - [x] Currently selected run is highlighted
  - [x] Clicking a run loads its artifacts in detail panel
  - [x] Scrollable if list exceeds viewport height
- [x] Detail panel (right side):
  - [x] When no run selected: Shows placeholder "Select a run to view artifacts"
  - [x] When run selected: Shows 3 sub-tabs: "Report", "Output Log", "Plan"
  - [x] Report sub-tab: Renders report.md markdown
  - [x] Output Log sub-tab: Renders output.log in monospace with ANSI color support
  - [x] Plan sub-tab: Renders plan-{requirement_id}.md markdown
  - [x] Sub-tabs use same horizontal tab bar style as RunArtifactViewer
  - [x] Default sub-tab: Report (when run is selected)
  - [x] **Reuses existing RunArtifactViewer artifact tabs** (Report, Output, Plan) - just renders them in the detail panel instead of standalone

### Component Reuse

- [x] Reuses RunArtifactViewer's markdown and log rendering functions
- [x] Reuses existing metadata display components from RequirementDetailSlideOut
- [x] Does not duplicate artifact fetching logic

### Data Flow

- [x] On mount, fetch requirement spec from specs/ directory
- [x] When "Run History" tab opens, fetch filtered run history: GET /api/projects/{project_id}/runs?requirement_id={req_id}
- [x] When user selects a run from master list, fetch that run's artifacts (report, output, plan)
- [x] Artifacts load asynchronously with loading states

## Technical Notes

**Migration from Existing Implementation**:

The existing RequirementDetailSlideOut has a 6-tab implementation. This needs to be **replaced** (not extended) with the new 2-tab design:

**Remove:**

- Separate Metadata tab (merge into Overview)
- Separate Specification tab (merge into Overview)
- Separate Report/Output Log/Plan Snapshot tabs at top level (move into Run History detail panel as sub-tabs)
- Any logic that switches artifact tabs based on History tab selection

**Keep/Refactor:**

- Slide-out container, animations, backdrop (no changes needed)
- Tab bar component (reduce from 6 to 2 tabs)
- Metadata rendering components (move into Overview tab)
- Spec rendering (move into Overview tab)
- **Artifact tabs from RunArtifactViewer** (Report, Output, Plan) - these should render in the detail panel when a run is selected. The RunArtifactViewer's artifact display logic is already implemented and should be reused, just nested in the new master-detail layout.

**New Components Needed:**

- Master-detail split layout container
- Run list item component with selection state
- Detail panel wrapper with conditional rendering (empty state vs. RunArtifactViewer
- Detail panel with conditional rendering (empty state vs. artifact tabs)

**Component Architecture**:

```
RequirementDetailSlideOut
├── SlideOutHeader (title, close button)
├── TabBar (Overview, Run History)
└── TabContent
    ├── OverviewTab
    │   ├── MetadataSection (status, priority, labels, deps)
    │   └── SpecificationSection (rendered markdown)
    └── RunHistoryTab
        ├── MasterList (run list, ~40% width)
        │   └── RunListItem[] (clickable)
        └── DetailPanel (~60% width)
            ├── EmptyState (when no selection)
            └── RunArtifactTabs (when run selected)
                ├── ReportTab      ← Reuse from existing RunArtifactViewer
                ├── OutputLogTab   ← Reuse from existing RunArtifactViewer
                └── PlanTab        ← Reuse from existing RunArtifactViewer
```

**Implementation Strategy**:

- The detail panel should render the existing RunArtifactViewer component (or its tab content components) directly
- Pass selected run's artifacts to RunArtifactViewer via props
- No need to reimplement markdown rendering, log viewing, or artifact loading - these already exist
- Focus effort on the master-detail layout and run list UI

**Styling Notes**:

- Master-detail split uses CSS flexbox or grid
- Vertical divider between master/detail with subtle border
- Master list items have hover state and selected state (background highlight)
- Detail panel sub-tabs are smaller/nested style (not same hierarchy as top-level tabs)

**Extract Reusable Components**: Before implementing, check if RunArtifactViewer's markdown/log rendering can be extracted into:

- `MarkdownRenderer.tsx`
- `LogViewer.tsx`
- `ArtifactLoader.tsx` (handles loading states and errors)

## Dependencies

- S-0003 (Frontend Observer UI) - requires React components and styling system
- S-0010 (Kanban Card Detail) - current slide-out implementation to refactor
- S-0002 (Backend API) - requires runs endpoint with requirement_id filtering

## Non-Goals

- Editing specs or metadata inline (separate requirement)
- Creating new runs from slide-out (use AgentControls in main toolbar)
- Comparing multiple runs side-by-side (future enhancement)
- Real-time run output streaming (separate requirement)
- Keyboard navigation between runs in master list (can be added later)

## Validation Criteria

- [ ] Backend endpoint supports requirement filtering: `curl -s http://localhost:8080/api/projects/default/runs?requirement_id=S-0011` (status 200)
- [x] Frontend renders 2 top-level tabs: Manual verification - open slide-out, verify Overview and Run History tabs
- [x] Master-detail layout works: Manual verification - click runs in list, verify artifacts load in detail panel
- [x] Overview tab shows spec and metadata: Manual verification - check both sections render correctly
