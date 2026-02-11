# S-0025: Compact Kanban Cards

## Narrative

As a Felix user working with many requirements, I need a compact view option for kanban cards so that I can see more requirements at once and get a better overview of the project status without excessive scrolling.

## Summary

Add a toggle switch in the kanban toolbar that allows users to switch between normal and compact views of requirement cards. Compact mode reduces card height and removes non-essential elements while maintaining readability and key information.

## Acceptance Criteria

### Toolbar Toggle Control

- [ ] Add "Compact View" toggle switch in the kanban filter bar (next to "Show Done" toggle)
- [ ] Toggle uses clean checkbox styling consistent with existing "Show Done" toggle
- [ ] Toggle state persists in browser localStorage for user preference
- [ ] Toggle label shows "Compact View" with optional icon (grid or compress icon)
- [ ] Smooth transition animation (300ms) when switching between modes

### Compact Card Design

- [ ] Card height reduced from current ~140px to ~80px maximum
- [ ] Title limited to single line with text truncation (ellipsis)
- [ ] Priority badge remains visible but smaller (reduced from current size)
- [ ] Status indicator (ID badge) remains visible with same styling
- [ ] In-progress pulse indicator remains for active requirements

### Compact Card Content Prioritization

- [ ] **Always Visible:** Requirement ID, title (truncated), priority badge
- [ ] **Always Visible:** Active indicator for in-progress requirements
- [ ] **Conditionally Visible:** Dependency warnings (reduced to icon + count only)
- [ ] **Hidden in Compact:** Tags section completely removed
- [ ] **Hidden in Compact:** Plan timestamp indicators removed
- [ ] **Hidden in Compact:** "Updated" date removed
- [ ] **Hidden in Compact:** Footer section with "View Spec" button removed

### Interactive Elements

- [ ] Cards remain fully clickable to open detail slide-out
- [ ] Drag and drop functionality works identically in both modes
- [ ] Hover effects remain with appropriate scaling for compact size
- [ ] Dependency tooltip still appears when hovering over warning icon

### Responsive Behavior

- [ ] Column width remains the same (320px) to maintain grid layout
- [ ] More cards visible per column due to reduced height
- [ ] Empty state indicators scale appropriately for compact mode
- [ ] Sticky drop zones work identically in compact mode

### Visual Design Specifications

- [ ] **Normal Card:** ~140px height, full content visible
- [ ] **Compact Card:** ~80px height, content prioritized as specified
- [ ] **Title:** Single line, 14px → 13px font size in compact mode
- [ ] **Priority Badge:** Maintains current styling but 10% smaller
- [ ] **Dependency Warning:** Icon (⚠️) + count number, no text description
- [ ] **Padding:** Reduced from 16px to 12px in compact mode

## Technical Notes

### Implementation Approach

- Add `isCompactView` state to RequirementsKanban component
- Use conditional CSS classes or styled-components for card sizing
- Implement localStorage persistence using `useEffect` hooks
- Add smooth CSS transitions for height changes during mode switching

### Component Changes

- **RequirementsKanban.tsx:** Add compact view toggle and state management
- **Card rendering logic:** Conditional content display based on compact mode
- **CSS classes:** Add `.kanban-card-compact` styling variants
- **localStorage key:** `felix-kanban-compact-view` for persistence

### Performance Considerations

- Compact mode should improve performance by reducing DOM elements per card
- Transition animations should use `transform` and `opacity` for smooth 60fps
- No additional API calls required - purely frontend feature

### Accessibility

- Toggle control properly labeled for screen readers
- Compact cards maintain adequate touch targets (minimum 44px height)
- Keyboard navigation and focus states preserved in compact mode
- Color contrast maintained for all visible elements

## Dependencies

None

## Validation Criteria

- [ ] Toggle switch appears in filter bar and functions correctly
- [ ] Compact mode reduces card height to ~80px while maintaining readability
- [ ] Essential information (ID, title, priority, active status) remains visible
- [ ] Non-essential elements (Tags, timestamps, footer) are hidden in compact mode
- [ ] Dependency warnings show as icon + count in compact mode
- [ ] User preference persists across browser sessions
- [ ] Smooth 300ms transition animation when switching modes
- [ ] All interactive functionality (click, drag, hover) works in both modes
- [ ] No performance regressions when switching between modes
- [ ] Responsive behavior maintained across different screen sizes

