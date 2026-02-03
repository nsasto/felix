# S-0012: Done Status for Requirements

## Narrative

As a project manager using Felix, I need to distinguish between requirements that are "complete" (all implementation and validation passed) and those that are truly "done" (accepted, reviewed, and ready for production), so I can track work that's finished but pending review separately from work that's fully accepted.

The "complete" status means Felix validated the requirement successfully. The "done" status is a human decision indicating the work has been reviewed, accepted, and is truly finished. This status can only be set manually by users, never by the agent.

Since done requirements aren't actively worked on, they should be hidden by default to reduce visual clutter on the kanban board, but available via a filter toggle for reference and auditing.

## Acceptance Criteria

### Data Model & Backend

- [ ] Add 'done' as valid status in backend requirement status enum/type
- [ ] Backend validates 'done' as acceptable status when updating requirements
- [ ] Existing requirements with status 'complete', 'blocked', 'planned', etc. remain valid
- [ ] No changes to felix-agent.ps1 (agent never sets status to 'done')

### Frontend Types & Schema

- [ ] Add 'done' to RequirementStatus type in types.ts
- [ ] Update status type definitions throughout frontend codebase
- [ ] Ensure 'done' status is recognized by all status-dependent UI components

### Kanban Column

- [ ] Add "Done" column to kanban board with appropriate styling
- [ ] Done column positioned after "Complete" column (rightmost)
- [ ] Done column shows count of done requirements
- [ ] Requirements can be dragged to/from Done column
- [ ] Done status badge color: purple/indigo (distinguishable from complete's green)
- [ ] Done column styling: `bg-purple-500/10 border-purple-500/20 text-purple-400`

### Filter Toggle

- [ ] Add checkbox control above kanban columns labeled "Show Done"
- [ ] Checkbox positioned in filter/control area (near existing filters if any)
- [ ] Checkbox default state: unchecked (done column hidden)
- [ ] When checked: Done column visible, requirements draggable to/from it
- [ ] When unchecked: Done column hidden, done requirements not shown
- [ ] Filter state persists in component state (doesn't need localStorage)
- [ ] Smooth show/hide animation for done column

### Status Transitions

- [ ] Users can manually set requirement to 'done' from any status via kanban drag-drop
- [ ] RequirementDetailSlideOut shows 'done' status badge with purple/indigo styling
- [ ] Done requirements can be moved back to 'complete' or other statuses if needed
- [ ] Status change updates ..felix/requirements.json via backend API

### UI Consistency

- [ ] Done status badge appears consistently across all components:
  - Kanban cards
  - RequirementDetailSlideOut metadata section
  - Any status dropdown or selector
- [ ] Done status has distinct visual identity (purple/indigo theme)
- [ ] Tooltips/help text explain: "Done = reviewed and accepted, ready for production"

## Technical Notes

**Status Enum Changes**:

- Backend: Update RequirementStatus enum in `app/backend/main.py`
- Frontend: Update `RequirementStatus` type in `app/frontend/types.ts`
- Add: `'done'` to valid status values

**Column Configuration**:

```typescript
// Add to COLUMNS array in RequirementsKanban.tsx
{
  status: 'done',
  label: 'Done',
  color: 'bg-purple-500',
  bgColor: 'bg-purple-500/10',
  borderColor: 'border-purple-500/20'
}
```

**Filter State**:

```typescript
// Add to RequirementsKanban component state
const [showDone, setShowDone] = useState(false);

// Filter columns
const visibleColumns = COLUMNS.filter(
  (col) => showDone || col.status !== "done",
);
```

**Agent Script Note**: No changes to `felix-agent.ps1`. The agent uses validation success to set status to "complete". Done is a human-only designation.

## Dependencies

- S-0003 (Frontend Observer UI) - requires kanban board and status management
- S-0002 (Backend API) - requires requirement update endpoint

## Non-Goals

- Agent automatically setting status to 'done' (never - this is human-only)
- Approval workflows or review processes (just a status flag)
- Permissions/role-based access for who can set done (out of scope)
- Archiving or hiding done requirements from other views (just kanban)
- Multiple "done" states (accepted, deployed, etc.) - one done status only

## Validation Criteria

- [ ] Backend accepts done status: `curl -X PATCH http://localhost:8080/api/projects/default/requirements/S-0001 -H "Content-Type: application/json" -d "{\"status\":\"done\"}"` (status 200)
- [x] Done column hidden by default: Manual verification - open kanban, verify Done column not visible
- [x] Show Done checkbox works: Manual verification - check "Show Done", verify column appears
- [x] Drag to done works: Manual verification - drag complete requirement to Done column, verify status updates
- [x] Done badge appears purple: Manual verification - open requirement detail, verify done status badge is purple/indigo


