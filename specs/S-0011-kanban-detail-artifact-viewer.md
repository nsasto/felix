# S-0011: Kanban Detail Run Artifacts Viewer

## Narrative

As a developer reviewing requirement work history, I need a unified view that shows both the requirement metadata and the complete run artifacts in one place, so I can quickly understand the requirement context, see what work was done, and review all outputs without switching between multiple panels or views.

Currently, the RequirementDetailSlideOut has limited functionality showing only metadata and a basic history list. The RunArtifactViewer component exists separately and provides rich artifact viewing (Report, Output Log, Plan Snapshot, Specification). This spec unifies these components to provide a comprehensive requirement detail experience.

## Acceptance Criteria

### Component Integration

- [ ] RequirementDetailSlideOut integrates or extends RunArtifactViewer component
- [ ] Slide-out displays 6 tabs total: Metadata, Report, Output Log, Plan Snapshot, Specification, History
- [ ] All tabs render in the same toolbar style as current RunArtifactViewer (horizontal tabs with icons)
- [ ] Clicking a requirement card in kanban opens slide-out with appropriate tab selected

### Metadata Tab

- [ ] First tab labeled "Metadata" with 📋 icon
- [ ] Displays requirement status badge (draft/planned/in_progress/complete/blocked)
- [ ] Displays priority badge (critical/high/medium/low)
- [ ] Shows last updated timestamp
- [ ] Lists all requirement labels as tags
- [ ] Shows dependency list linking to other requirement IDs
- [ ] Uses existing styling from RequirementDetailSlideOut metadata section

### Run Artifact Tabs (Report, Output Log, Plan Snapshot, Specification)

- [ ] Report tab shows latest run report markdown rendered
- [ ] Output Log tab shows latest run console output in monospace
- [ ] Plan Snapshot tab shows the plan-{requirement_id}.md from latest run
- [ ] Specification tab shows the requirement spec from specs/ directory
- [ ] All four tabs reuse RunArtifactViewer rendering logic
- [ ] Tabs pull from requirement.last_run_id when available

### History Tab

- [ ] Last tab labeled "History" with 🕐 icon
- [ ] Shows run history filtered to current requirement ID only
- [ ] Displays list of all runs with status, timestamp, PID
- [ ] Each history entry shows: run ID, started/ended timestamps, status badge, exit code
- [ ] Clicking a history entry loads that run's artifacts in the artifact tabs
- [ ] Currently selected run is highlighted/indicated in history list

### Behavior & Navigation

- [ ] Default tab on open: Metadata if no last_run_id, Report if last_run_id exists
- [ ] ESC key closes slide-out
- [ ] Left/Right arrow keys navigate between tabs
- [ ] Slide-out width remains 60vw (min 500px, max 800px)
- [ ] Slide-out animates in from right side
- [ ] Backdrop dims and closes on click

## Technical Notes

**Component Architecture:** The cleanest approach is to compose RunArtifactViewer within RequirementDetailSlideOut rather than extend it. RequirementDetailSlideOut should:

1. Render its own header and close button
2. Render a custom tab bar with all 6 tabs
3. For Metadata and History tabs, render inline content
4. For artifact tabs, delegate content rendering to RunArtifactViewer's content rendering logic (extract the markdown/log rendering into a reusable function)

**Data Flow:**

- RequirementDetailSlideOut receives `requirement` prop with `last_run_id`
- On mount, if `last_run_id` exists, fetch that run's artifacts
- History tab fetches filtered run history: `GET /api/projects/{project_id}/runs?requirement_id={req_id}`
- When user clicks different run in history, update currently viewed run and reload artifact tabs

**Don't assume not implemented:** RunArtifactViewer already exists with proper tab rendering. Check if its internal rendering functions can be extracted/reused before duplicating code.

## Dependencies

- S-0003 (Frontend Observer UI) - requires React components and styling system
- S-0010 (Kanban Card Detail) - current slide-out implementation to refactor

## Non-Goals

- Editing specs inline (separate requirement)
- Creating new runs from slide-out (use AgentControls)
- Comparing multiple runs side-by-side (future enhancement)
- Real-time run output streaming (separate requirement)

## Validation Criteria

- [ ] Backend endpoint supports requirement filtering: `GET /api/projects/{project_id}/runs?requirement_id=S-0011` returns only matching runs
- [ ] Frontend renders all 6 tabs: manual verification in browser
- [ ] Tab navigation with arrow keys: press Left/Right in slide-out
- [ ] History filtering works: view history tab and verify only runs for current requirement appear
