# S-0010: Kanban Card Detail Slide-Out

## Narrative

As a developer using Felix, I need to view detailed information about a requirement when I click on its kanban card, so that I can quickly access the full specification, acceptance criteria, and work history without leaving the kanban board view.

## Acceptance Criteria

### Slide-Out Panel

- [ ] Clicking a kanban card opens a slide-out panel from the right side of the screen
- [ ] Slide-out overlays the kanban board with a semi-transparent backdrop
- [ ] Clicking the backdrop or close button (X) dismisses the slide-out
- [ ] Slide-out has smooth animation (slide in from right, slide out to right)
- [ ] Slide-out width is 60% of viewport (max 800px, min 500px)
- [ ] Slide-out is scrollable when content exceeds viewport height

### Tab Navigation

- [ ] Slide-out header shows requirement ID and title
- [ ] Two tabs are available: "Requirements" and "History"
- [ ] "Requirements" tab is selected by default
- [ ] Tab selection is indicated with visual styling (active/inactive states)
- [ ] Clicking a tab switches the content panel below
- [ ] Tab switching is instant (no loading delay)

### Requirements Tab

- [ ] Displays the full spec file content from `specs/{requirement.spec_path}`
- [ ] Renders markdown with proper formatting (headings, lists, code blocks, etc.)
- [ ] Shows requirement metadata at top: status, priority, Tags, dependencies
- [ ] Status badge uses color coding (planned=blue, in_progress=yellow, complete=green, blocked=red)
- [ ] Acceptance criteria checkboxes are read-only (not editable in slide-out)
- [ ] "Edit Spec" button opens spec editor view (same as clicking spec in sidebar)
- [ ] "View Plan" button navigates to current plan file (if exists)

### History Tab

- [ ] Displays chronological timeline of work on this requirement
- [ ] Shows all runs from `runs/*/` directories that reference this requirement ID
- [ ] Each history entry shows: date/time, iteration count, outcome, and summary
- [ ] Expandable sections for each run to view full logs and diffs
- [ ] Most recent entries appear at the top (reverse chronological)
- [ ] Empty state message when no history exists: "No work history yet"
- [ ] Links to view full run directory contents

### Keyboard Navigation

- [ ] ESC key closes the slide-out
- [ ] Arrow keys (left/right) switch between tabs
- [ ] Tab key navigates focusable elements within slide-out
- [ ] Focus is trapped within slide-out when open (doesn't jump to background)

### Responsive Design

- [ ] On small screens (<768px), slide-out becomes full-screen modal
- [ ] Mobile: swipe right gesture dismisses slide-out
- [ ] Slide-out scrolls independently from kanban board

## Technical Notes

### Architecture

**Component Structure:**

- `RequirementDetailSlideOut.tsx` - Main slide-out container component
- `RequirementsTab.tsx` - Spec content display with markdown rendering
- `HistoryTab.tsx` - Work history timeline component
- `TabNavigation.tsx` - Reusable tab switcher component

**State Management:**

- Selected requirement ID stored in parent state (KanbanBoard.tsx)
- Slide-out visibility controlled by presence of selected requirement
- Tab selection is local state within slide-out component

**Data Flow:**

1. User clicks kanban card → sets `selectedRequirementId` in parent
2. Slide-out fetches spec content via API: `GET /api/specs/{spec_path}`
3. History tab fetches run logs via API: `GET /api/runs?requirement_id={id}`
4. Markdown rendering uses existing markdown parser/renderer

### API Changes

**New Endpoints Needed:**

```
GET /api/requirements/{id}/spec
  - Returns full spec file content
  - Response: { content: string, path: string, last_modified: string }

GET /api/requirements/{id}/history
  - Returns work history for requirement
  - Response: [
      {
        run_id: string,
        timestamp: string,
        iteration_count: number,
        outcome: string,
        plan_path: string | null,
        diff_path: string | null,
        report_summary: string
      }
    ]
```

**Existing Endpoints to Use:**

- `GET /api/requirements` - Already exists for requirement metadata
- `GET /api/specs/{path}` - May already exist for spec content

### Data Model

No database changes needed. Uses existing file system structure:

- Specs from `specs/*.md`
- Run history from `runs/*/` directories
- Plan files from `runs/*/plan-{id}.md`

### UI/UX Patterns

**Slide-Out Animation:**

```css
.slide-out {
  transform: translateX(100%);
  transition: transform 300ms ease-out;
}

.slide-out.open {
  transform: translateX(0);
}
```

**Backdrop:**

- Dark overlay with 50% opacity
- Click handler to close slide-out
- Fade in/out animation synchronized with slide-out

**Tab Styling:**

- Follow existing Felix tab patterns from Settings screen
- Active tab: border-bottom, bold text
- Inactive tab: gray text, hover effect

## Dependencies

- S-0003 (Frontend Observer UI) - Complete, provides kanban board structure
- S-0002 (Backend API Server) - Complete, may need new endpoints added
- Markdown rendering library (likely already in frontend dependencies)

## Validation Criteria

- [x] Manual verification - Clicking kanban card opens slide-out from right
- [x] Manual verification - Slide-out shows requirement ID and title in header
- [x] Manual verification - Two tabs visible: Requirements and History
- [x] Manual verification - Requirements tab displays full spec with markdown formatting
- [x] Manual verification - Status badge shows correct color for requirement state
- [x] Manual verification - History tab shows chronological work timeline
- [x] Manual verification - ESC key closes slide-out
- [x] Manual verification - Clicking backdrop closes slide-out
- [x] Manual verification - Tab switching works correctly
- [x] Manual verification - Slide-out scrolls independently when content is long

## Non-Goals

- Editing spec content directly in slide-out (use spec editor for that)
- Inline plan editing from slide-out
- Real-time updates to history (refresh required)
- Comparing multiple requirements side-by-side
- Exporting requirement details to external formats

