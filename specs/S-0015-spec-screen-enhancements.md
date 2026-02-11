# S-0015: Spec Screen Enhancements

## Narrative

As a Felix user working with multiple specifications, I need an improved spec list view with search capabilities, fixed action buttons, and safety indicators from S-0006, so that I can quickly find specs, easily create new ones, and be warned before editing specs that are actively being planned or have drifted from their implementation plans.

Currently, the spec list has no search functionality, the "New Spec" button scrolls out of view with long spec lists, and there are no visual indicators for specs with in-progress requirements or spec/plan drift. This makes it difficult to navigate large projects, awkward to create new specs, and risky to edit specs without knowing their current state.

This enhancement brings three improvements:

1. **Fixed "New Spec" button** at the bottom of the spec list (always visible like the refresh button on projects screen)
2. **Search bar** to filter specs by ID, title, Tags, or status
3. **S-0006 Safety Indicators** showing in-progress status, spec/plan drift, and manual reset controls

## Acceptance Criteria

### Fixed "New Spec" Button

- [ ] "New Spec" button moves from top of spec list to bottom
- [ ] Button stays fixed at bottom of spec list panel (always visible when scrolling)
- [ ] Button styling matches the fixed "Refresh Projects" button from projects screen
- [ ] Button shows "+" icon and "New Spec" label
- [ ] Clicking button opens new spec modal (existing functionality preserved)
- [ ] Button position is consistent with other fixed action buttons in app

### Search Bar

- [ ] Search bar appears above spec list, below "Specifications" header
- [ ] Search input has placeholder text: "Search specs..."
- [ ] Search filters specs by requirement ID (e.g., "S-0015")
- [ ] Search filters specs by title (case-insensitive partial match)
- [ ] Search filters specs by status (planned, in_progress, complete, etc.)
- [ ] Search filters specs by Tags (if requirement has matching label)
- [ ] Search updates results in real-time as user types
- [ ] Search shows count of filtered results: "3 / 15 specs"
- [ ] Empty search shows all specs (default state)
- [ ] No results state shows message: "No specs match your search"
- [ ] Clear button (X) appears in search input when text is entered
- [ ] Search state persists when navigating between specs (doesn't reset on spec select)

### S-0006 Safety Indicators

- [ ] Each spec card in list shows status badge for underlying requirement
- [ ] In-progress requirements show yellow "IN PROGRESS" badge
- [ ] Warning icon (⚠️) appears on spec cards when spec has drifted from plan
- [ ] Drift indicator shows when spec modified_at > plan generated_at
- [ ] Hovering drift indicator shows tooltip: "Spec modified after plan generated"
- [ ] Active agent indicator shows when agent is currently running on requirement
- [ ] Active agent indicator uses pulse animation (same as AgentControls)
- [ ] Clicking spec card with in_progress status shows pre-edit warning modal
- [ ] Pre-edit warning modal has three options: Cancel, Reset Plan, Continue Editing
- [ ] "Reset Plan" button marks requirement as planned and clears plan file
- [ ] "Continue Editing" allows editing despite warning (as per S-0006)
- [ ] "Cancel" closes modal and returns to spec list without opening editor
- [ ] Manual "Reset Plan" button appears on drift indicator when hovering
- [ ] Reset plan action requires confirmation dialog
- [ ] Confirmation shows: "This will mark S-XXXX as 'planned' and clear its plan. Continue?"
- [ ] Reset plan updates requirement status in ..felix/requirements.json
- [ ] Visual indicators use consistent styling with S-0006 implementation

## Technical Notes

### Architecture

This enhancement modifies the existing SpecsEditor component without breaking current functionality:

1. **Search Implementation**: Add state for search query, filter specs array before rendering, show filtered count
2. **Fixed Button**: Move "New Spec" button from top of list to bottom with fixed positioning (similar to projects refresh button)
3. **Safety Indicators**: Integrate existing S-0006 logic (useRequirementStatus hook) into spec list items

### Component Structure

```typescript
// SpecsEditor.tsx enhancements
interface SpecsEditorProps {
  projectId: string;
  initialSpecFilename?: string;
  onSelectSpec?: (filename: string) => void;
}

// New state for search
const [searchQuery, setSearchQuery] = useState("");

// Filtered specs based on search
const filteredSpecs = useMemo(() => {
  if (!searchQuery.trim()) return specs;

  const query = searchQuery.toLowerCase();
  return specs.filter((spec) => {
    // Match on requirement ID, title, status, Tags
    const req = requirements.find((r) => r.spec_path.includes(spec.filename));
    if (!req) return false;

    return (
      req.id.toLowerCase().includes(query) ||
      req.title.toLowerCase().includes(query) ||
      req.status.toLowerCase().includes(query) ||
      req.Tags.some((l) => l.toLowerCase().includes(query))
    );
  });
}, [specs, searchQuery, requirements]);

// Requirement status hook for safety indicators
const requirementStatus = useRequirementStatus(projectId, selectedFilename);
```

### Search Bar Layout

```tsx
<div className="p-3 space-y-2">
  <div className="relative">
    <input
      type="text"
      placeholder="Search specs..."
      value={searchQuery}
      onChange={(e) => setSearchQuery(e.target.value)}
      className="w-full px-3 py-2 text-xs theme-bg-elevated theme-border rounded-lg"
    />
    {searchQuery && (
      <button
        onClick={() => setSearchQuery("")}
        className="absolute right-2 top-2"
      >
        <IconX className="w-4 h-4" />
      </button>
    )}
  </div>
  <div className="text-[9px] text-slate-500 font-mono">
    {filteredSpecs.length} / {specs.length} specs
  </div>
</div>
```

### Fixed Button Layout

```tsx
{
  /* Spec List - Scrollable */
}
<div className="flex-1 overflow-y-auto custom-scrollbar">
  {/* Spec cards here */}
</div>;

{
  /* Fixed New Spec Button - Always visible */
}
<div className="border-t theme-border p-3">
  <button
    onClick={handleCreateSpec}
    className="w-full flex items-center justify-center gap-2 px-4 py-2 
               bg-felix-500 hover:bg-felix-600 text-white rounded-lg
               text-xs font-semibold transition-colors"
  >
    <IconPlus className="w-4 h-4" />
    <span>New Spec</span>
  </button>
</div>;
```

### Safety Indicator Card Enhancement

```tsx
<div
  key={spec.filename}
  onClick={() => handleSpecClick(spec.filename)}
  className={`relative spec-card ${selectedFilename === spec.filename ? "selected" : ""}`}
>
  {/* Existing spec card content */}
  <div className="spec-header">
    <span className="spec-id">{requirement.id}</span>

    {/* Status badge */}
    <span className={`status-badge ${requirement.status}`}>
      {requirement.status}
    </span>

    {/* Drift indicator */}
    {hasDrift && (
      <div
        className="drift-indicator"
        title="Spec modified after plan generated"
      >
        ⚠️
        <button
          onClick={(e) => {
            e.stopPropagation();
            handleResetPlan(requirement.id);
          }}
        >
          Reset Plan
        </button>
      </div>
    )}

    {/* Active agent indicator */}
    {isAgentActive && <div className="active-agent-indicator pulse">🤖</div>}
  </div>

  <div className="spec-title">{requirement.title}</div>
</div>
```

### API Integration

**Existing Endpoints (no changes needed):**

- `GET /api/projects/:id/specs` - list specs
- `GET /api/projects/:id/requirements` - get requirements.json
- `GET /api/projects/:id/requirement/:reqId/status` - check status (S-0006)
- `PUT /api/projects/:id/requirements` - update requirements.json (for reset plan)

**Data Flow:**

1. Load specs and requirements on mount
2. Match specs to requirements by spec_path
3. For each spec card, check requirement status using S-0006 hook
4. Show indicators based on status response (in_progress, drift, active_agent)
5. On "Reset Plan", update requirement status to "planned" via requirements API

### Drift Detection Logic

```typescript
// Check if spec has drifted from plan
const hasDrift = (
  requirement: Requirement,
  runHistory: RunHistoryEntry[],
): boolean => {
  if (
    requirement.status !== "in_progress" &&
    requirement.status !== "planned"
  ) {
    return false;
  }

  const latestRun = runHistory.find((r) => r.requirement_id === requirement.id);
  if (!latestRun || !latestRun.plan_generated_at) {
    return false;
  }

  // Compare spec modified time with plan generation time
  const specModified = new Date(requirement.updated_at);
  const planGenerated = new Date(latestRun.plan_generated_at);

  return specModified > planGenerated;
};
```

### Reset Plan Action

```typescript
const handleResetPlan = async (requirementId: string) => {
  const confirmed = confirm(
    `This will mark ${requirementId} as 'planned' and clear its plan. Continue?`,
  );

  if (!confirmed) return;

  try {
    // Update requirement status to planned
    const requirements = await felixApi.getRequirements(projectId);
    const updated = requirements.requirements.map((r) =>
      r.id === requirementId ? { ...r, status: "planned" } : r,
    );

    await felixApi.updateRequirements(projectId, updated);

    // Optionally: Delete plan file via backend
    // await felixApi.deletePlanFile(projectId, requirementId);

    // Refresh UI
    await loadRequirements();
  } catch (err) {
    console.error("Failed to reset plan:", err);
    alert("Failed to reset plan. See console for details.");
  }
};
```

### Styling Consistency

All new UI elements should match existing Felix design system:

- Search bar: theme-bg-elevated, theme-border, rounded-lg
- Fixed button: bg-felix-500, hover:bg-felix-600
- Status badges: Use existing badge colors (yellow for in_progress, etc.)
- Drift indicator: Amber/yellow warning color (⚠️)
- Active agent: Pulse animation from AgentControls
- Tooltips: Dark background with light text, small font

## Dependencies

- S-0003 (Frontend Observer UI) - provides SpecsEditor component
- S-0006 (Spec Edit Safety) - provides status checking, warning modals, reset plan logic
- S-0002 (Backend API) - requires specs and requirements endpoints

## Non-Goals

- Advanced search with operators (AND/OR) or regex patterns
- Saved search queries or search history
- Filtering by multiple criteria simultaneously (e.g., "status:in_progress AND label:frontend")
- Sorting specs by different fields (ID, title, status)
- Bulk actions on filtered specs (e.g., "mark all as planned")
- Keyboard navigation through search results
- Search highlighting in spec content (only searches metadata)

## Validation Criteria

- [ ] Fixed button: Open specs screen, scroll down, verify "New Spec" button stays visible
- [ ] Search works: Type "S-0015" in search bar, verify only S-0015 appears in list
- [ ] Search by title: Type "frontend" in search, verify matching specs appear
- [ ] Search by status: Type "in_progress" in search, verify only in-progress specs appear
- [ ] Search count: Verify "X / Y specs" shows correct filtered and total counts
- [ ] Clear search: Click X button in search bar, verify search clears and all specs shown
- [ ] Drift indicator: Modify a spec with existing plan, verify ⚠️ appears on card
- [ ] Drift tooltip: Hover drift indicator, verify tooltip shows "Spec modified after plan generated"
- [ ] In-progress warning: Click spec card with in_progress status, verify warning modal appears
- [ ] Reset plan works: Click "Reset Plan" on drift indicator, confirm dialog, verify status changes to "planned"
- [ ] Active agent indicator: Start agent on requirement, verify 🤖 pulse animation appears
- [ ] No results state: Search for nonexistent term, verify "No specs match your search" message
- [ ] Button styling: Verify "New Spec" button matches projects screen "Refresh" button style



