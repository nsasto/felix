# S-0029: Connect Live Polling Badge to Heartbeat Checks

## Narrative

As a Felix user monitoring local agents, I need the Live Polling badge indicator to accurately reflect when heartbeat checks are actively occurring so that I have visual confirmation that agent liveness monitoring is working in real-time.

## Acceptance Criteria

### Heartbeat Check Functionality

- [ ] Live polling mode actively polls GET /api/agents endpoint at regular intervals
- [ ] Polling interval is 5 seconds to match agent heartbeat frequency
- [ ] Backend check_agent_liveness function evaluates heartbeat staleness on each poll
- [ ] Agent status automatically updates to "inactive" when last_heartbeat exceeds 10 seconds
- [ ] Agent status automatically updates to "active" when fresh heartbeat received
- [ ] Heartbeat checking starts immediately when live mode is enabled
- [ ] Heartbeat checking stops cleanly when manual mode is selected

### Visual Feedback

- [ ] Green dot icon throbs with slow pulsing animation when heartbeat checks are actively running
- [ ] Throbbing animation syncs with actual heartbeat check intervals
- [ ] Throbbing animation is smooth and subtle (2-second cycle, opacity fade between 100% and 60%)
- [ ] Static green dot displays when live polling is enabled but polling hasn't started
- [ ] Grey static dot displays when manual polling mode is active

### Mode-Specific Behavior

- [ ] Local mode: heartbeat checks poll backend API at 5-second intervals
- [ ] Remote mode behavior: reserved for future implementation (different from local mode)
- [ ] Mode detection: system correctly identifies local vs remote operational context
- [ ] Switching from manual to live mode immediately starts heartbeat polling
- [ ] Switching from live to manual mode immediately stops heartbeat polling
- [ ] In manual mode, the refresh button will manually fire the hearbeat poll

### Edge Cases

- [ ] Animation handles rapid mode switching without visual glitches
- [ ] Backend unavailability doesn't cause polling to crash or stop
- [ ] Multiple rapid heartbeat responses don't cause animation stutter
- [ ] Page refresh preserves polling mode state and resumes heartbeat checks
- [ ] Agent disconnect detected within 15 seconds (10s timeout + 5s check interval)

## Technical Notes

**Current State:** S-0023 implemented the polling mode toggle with a pulsing badge, but heartbeat checking is not actually running. The animation is cosmetic only.

**Gap:** Need to implement the actual heartbeat polling mechanism that calls GET /api/agents at regular intervals and updates agent status based on heartbeat staleness.

**Local vs Remote:** In local mode, the frontend polls GET /api/agents which triggers backend liveness checks (check_agent_liveness function). Remote mode will use a different mechanism (WebSocket, push notifications, or different polling strategy) to be defined in a future specification.

**Heartbeat System:** Agents send heartbeats every 5 seconds to POST /api/agents/{id}/heartbeat. Backend marks agents inactive if last_heartbeat is >10 seconds old. GET /api/agents automatically updates status based on heartbeat staleness via the update_agent_statuses function.

**Don't assume not implemented:** The backend heartbeat system and check_agent_liveness logic already exists in app/backend/routers/agents.py. Only the frontend polling mechanism needs to be connected.

## Dependencies

- S-0023 (Agent Dashboard Polling Mode Toggle) - provides the polling mode infrastructure and badge UI
- S-0013 (Agent Settings & Registry) - provides the heartbeat system and liveness checking backend logic

## Non-Goals

- Defining remote mode heartbeat behavior (future spec)
- Changing heartbeat intervals or timeouts (keep 5s heartbeat, 10s timeout)
- Modifying agent registration or heartbeat API contracts
- Implementing WebSocket-based heartbeat updates

## Validation Criteria

### Functional Validation

- [ ] Manual verification: Start an agent, observe status becomes "active" in UI
- [ ] Manual verification: Stop agent heartbeat, status becomes "inactive" within 15 seconds
- [ ] Manual verification: Agent status updates occur during live polling
- [ ] Manual verification: No status updates occur in manual mode (requires manual refresh)

### Visual Validation

- [ ] Badge displays smooth throbbing animation in live mode (observe 2-second cycle)
- [ ] Animation stops when switching to manual mode
- [ ] Animation reflects actual heartbeat check activity

### Technical Validation

- [ ] Browser DevTools Network tab shows GET /api/agents requests every 5 seconds in live mode
- [ ] Browser DevTools Network tab shows no automatic requests in manual mode
- [ ] Browser DevTools Console shows no errors during heartbeat polling
- [ ] Backend logs show successful liveness checks when GET /api/agents is called

