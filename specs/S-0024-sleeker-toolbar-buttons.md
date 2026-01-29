# S-0024: Sleeker Toolbar Buttons for Agent Orchestration

## Narrative

As a Felix user managing agents, I need the Start/Stop buttons in the Agent Orchestration toolbar to use the same clean button styling as the Specs Editor so that the UI feels consistent and professional across all screens.

## Acceptance Criteria

### Button Styling

- [ ] Start button uses clean pill-shaped styling similar to Specs Editor buttons
- [ ] Stop button uses same styling but with red color scheme for danger actions
- [ ] Both buttons show icons instead of emoji (▶️ and ⏹️ replaced with clean SVG icons)
- [ ] Buttons have proper hover, active, and disabled states
- [ ] Loading states show spinner and text like "Starting..." or "Stopping..."

### Dropdown Menus

- [ ] Start dropdown (requirement selection) uses clean dark styling with rounded corners
- [ ] Stop dropdown (graceful vs force) uses same menu styling
- [ ] Menu items have proper hover states
- [ ] Menus align properly with their trigger buttons

### Secondary Buttons

- [ ] Settings and Refresh buttons use minimal icon-only styling
- [ ] All buttons maintain existing functionality
- [ ] Consistent spacing and alignment across the toolbar

## Technical Notes

### Styling Approach

- Use existing CSS variables and theme tokens from Specs Editor
- Replace emoji icons with clean SVG icons
- Apply consistent button heights, border radius, and spacing
- Use same transition durations and easing functions

### Component Updates

- Update DashboardToolbar component in AgentDashboard.tsx
- Maintain all existing click handlers and dropdown logic
- No backend changes required

## Dependencies

None

## Validation Criteria

- [ ] Visual comparison shows consistent styling with Specs Editor toolbar
- [ ] All button states (hover, active, disabled, loading) work correctly
- [ ] Start and Stop functionality remains unchanged
- [ ] Dropdown menus open/close properly with clean styling
- [ ] No regressions in agent control functionality
