# S-0023: Agent Dashboard Polling Mode Toggle

## Narrative

As a Felix user monitoring agents, I need the ability to toggle between automatic live polling and manual refresh mode so that I can reduce unnecessary network traffic and have control over when agent status updates occur.

## Acceptance Criteria

### Core Functionality

- [ ] Polling mode badge is visible on Agent Dashboard
- [ ] Badge displays "Live Polling Active" in green with pulsing icon when in live mode
- [ ] Badge displays "Manual Polling Mode" in grey with static icon when in manual mode
- [ ] Clicking the badge toggles between live and manual modes
- [ ] Live mode automatically polls agent heartbeats at regular intervals (current: every 5 seconds)
- [ ] Manual mode pauses automatic polling
- [ ] Manual mode responds to refresh button clicks for on-demand updates
- [ ] Polling mode preference persists across browser page refreshes
- [ ] Default state is Live Polling Mode for new users

### Visual Design

- [ ] Badge appears as a clickable label (it's current look is good)
- [ ] Green color for Live mode (theme green)
- [ ] Grey color for Manual mode (theme muted)
- [ ] Pulsing dot/circle icon animation in Live mode (2-second cycle)
- [ ] Static dot icon in Manual mode (no animation)
- [ ] Smooth visual transitions when toggling modes
- [ ] Hover state indicates badge is clickable
- [ ] Pulsing animation is subtle (opacity range: 100% to 60%)

### Edge Cases

- [ ] Mode preference loads correctly on initial page load
- [ ] Mode preference persists after browser restart
- [ ] Switching modes while polling is in progress handles gracefully
- [ ] Manual refresh button works regardless of polling mode
- [ ] Toggling rapidly between modes doesn't cause issues

## Technical Notes

### Architecture

**Component Changes:**

- Update **AgentDashboard** component to include polling mode state management
- Add polling mode toggle badge UI element
- Implement conditional polling logic based on mode
- Add localStorage persistence for mode preference

**State Management:**

- Add polling mode state: `'live'` or `'manual'`
- Load mode preference from localStorage on component mount
- Save mode preference to localStorage when changed
- Conditionally control polling interval based on current mode

**Styling:**

- Create CSS keyframe animation for pulsing effect (smooth fade in/out) - use existing if we have
- Add hover states for clickability indication
- Implement smooth color transitions between states

### API Changes

None - this is a frontend-only feature.

### Data Model

**localStorage:**

- Key: `felix_agent_polling_mode`
- Value: `'live'` | `'manual'`
- Type: string

## Dependencies

None

## Validation Criteria

### Visual Validation

- [ ] Badge appears with correct colors and labels in both modes
- [ ] Pulsing animation works smoothly in live mode (2s cycle)
- [ ] No animation present in manual mode
- [ ] Hover state displays correctly

### Functional Validation

- [ ] Clicking badge successfully toggles between modes
- [ ] Live mode polls automatically (verify in browser network tab - requests every 5s)
- [ ] Manual mode does not poll automatically (no automatic network requests)
- [ ] Refresh button triggers heartbeat check in manual mode
- [ ] Mode preference persists after browser page refresh
- [ ] Mode preference persists after browser restart

### Technical Validation

- [ ] Browser DevTools: Verify `felix_agent_polling_mode` key exists in localStorage
- [ ] Browser DevTools: Verify localStorage value changes when toggling modes
- [ ] Browser DevTools: Verify correct value ('live' or 'manual') stored

## Notes

- Consider adding tooltip on hover: "Click to toggle polling mode"
- Future enhancement: Could add keyboard shortcut (e.g., 'L' for live toggle)
- Future enhancement: Could extend similar toggle to other auto-refreshing components (runs, requirements)
- Animation should be non-distracting and accessible
