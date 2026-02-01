# S-0033: Remove Frontend Polling Mechanisms

**Phase:** -1 (Legacy Code Cleanup)  
**Effort:** 4-5 hours  
**Priority:** Critical  
**Dependencies:** S-0031

---

## Narrative

This specification covers removing all polling mechanisms in the frontend that repeatedly fetch project state, agent status, and requirements. This includes removing polling intervals from React components while preserving the LiveConsolePanel which will continue to stream console output via WebSocket.

The goal is to clean up approximately 300-350 lines of polling code and prepare the frontend for event-driven state management via Supabase Realtime in Phase 3.

---

## Acceptance Criteria

### In app/frontend/src/Main.tsx

- [ ] Remove state polling interval (lines ~1482-1740)
- [ ] Remove `useEffect` hooks that set up `setInterval` for state fetching
- [ ] Remove `loadProjectState()` function if it polls
- [ ] Remove `loadAgents()` function if it polls
- [ ] Remove `loadRequirements()` function if it polls
- [ ] Preserve LiveConsolePanel component (lines 777-1219)
- [ ] Preserve console WebSocket connection logic

### In app/frontend/src/components/AgentControl.tsx

- [ ] Remove polling interval (lines ~71-93)
- [ ] Remove `useEffect` hook with `setInterval` for agent status
- [ ] Replace polling with static state (temporary until Phase 1)
- [ ] Keep agent control buttons (START/STOP/PAUSE) but disable them temporarily

### In app/frontend/src/components/ProjectOverview.tsx

- [ ] Remove any polling for project metadata
- [ ] Remove `useEffect` hooks with intervals
- [ ] Replace with static or mocked data until Phase 1

### In app/frontend/src/components/RequirementsList.tsx

- [ ] Remove polling for requirements
- [ ] Replace with empty state or mocked data until Phase 1

---

## Technical Notes

### Files to Modify

```
app/frontend/src/Main.tsx                       (~260 lines removed)
app/frontend/src/components/AgentControl.tsx    (~25 lines removed)
app/frontend/src/components/ProjectOverview.tsx (~30 lines removed)
app/frontend/src/components/RequirementsList.tsx (~20 lines removed)
```

### Polling Patterns to Remove

**Pattern 1: setInterval in useEffect**

```typescript
useEffect(() => {
  const interval = setInterval(() => {
    loadProjectState();
  }, 2000);
  return () => clearInterval(interval);
}, []);
```

**Pattern 2: Recursive setTimeout**

```typescript
const pollAgentStatus = async () => {
  await fetchAgentStatus();
  setTimeout(pollAgentStatus, 3000);
};
```

**Pattern 3: useQuery with refetchInterval**

```typescript
const { data } = useQuery("agents", fetchAgents, {
  refetchInterval: 2000,
});
```

### Preserve These Patterns

**Console WebSocket (LiveConsolePanel):**

```typescript
// Keep this - real-time console streaming stays
useEffect(() => {
  const ws = new WebSocket(`ws://localhost:8080/api/agents/${agentId}/console`);
  ws.onmessage = (event) => {
    setConsoleOutput((prev) => prev + event.data);
  };
  return () => ws.close();
}, [agentId]);
```

### Temporary Static Behavior

After this spec, the frontend will show:

- **Agent Dashboard:** "Migrating to database - agent status unavailable"
- **Requirements List:** Empty list or last known state
- **Project Overview:** Static metadata
- **Console Panel:** Still streaming logs via WebSocket (preserved)

---

## Dependencies

**Depends On:**

- S-0031: Remove File-Based WebSocket Infrastructure (ensures no WebSocket connections to removed endpoints)

**Blocks:**

- S-0034: Cleanup Verification and Documentation

---

## Validation Criteria

### Code Verification

- [ ] No `setInterval` in Main.tsx: `grep -n "setInterval" app/frontend/src/Main.tsx`
- [ ] No `setTimeout` polling in AgentControl.tsx: `grep -n "setTimeout" app/frontend/src/components/AgentControl.tsx`
- [ ] No `refetchInterval` in useQuery calls: `grep -rn "refetchInterval" app/frontend/src/`
- [ ] LiveConsolePanel still has WebSocket: `grep -n "WebSocket" app/frontend/src/Main.tsx` (should find lines in LiveConsolePanel)

### Build Verification

- [ ] Frontend builds without errors: `cd app/frontend && npm run build` (exit code 0)
- [ ] No TypeScript errors: `cd app/frontend && npx tsc --noEmit` (exit code 0)
- [ ] No linting errors: `cd app/frontend && npm run lint` (exit code 0)

### Runtime Verification

- [ ] Frontend starts: `cd app/frontend && npm run dev` (exit code 0)
- [ ] No console errors on page load
- [ ] Console panel connects to WebSocket (verify in browser DevTools Network tab)
- [ ] Console panel streams logs from a running agent
- [ ] No polling network requests visible (check Network tab - no repeated /api/agents or /api/projects calls)

### Browser DevTools Check

- [ ] Open browser DevTools → Network tab
- [ ] Load frontend application
- [ ] Wait 30 seconds
- [ ] Verify NO repeated HTTP requests to:
  - `/api/projects/{id}/state`
  - `/api/agents`
  - `/api/requirements`
- [ ] Verify WebSocket connection to `/api/agents/{id}/console` exists (if agent running)

---

## Rollback Strategy

If issues arise:

1. Revert commit: `git revert HEAD`
2. Restore polling code from git history
3. Re-test frontend with backend

**Note:** After this spec, the frontend will have reduced functionality until Phase 1 (API-based updates) and Phase 3 (Realtime subscriptions) are implemented. This is expected and acceptable.

---

## Notes

- This is primarily a deletion spec with minimal new code (static placeholders)
- Console streaming WebSocket is preserved (critical for developer experience)
- Frontend will appear "frozen" for agent status until Phase 1 implements proper API endpoints
- Users can still view console logs in real-time (most important feature during development)
- Total cleanup: ~335 lines removed across 4 files
- Phase 1 will restore dynamic updates via API + temporary polling
- Phase 3 will restore real-time updates via Supabase Realtime subscriptions
