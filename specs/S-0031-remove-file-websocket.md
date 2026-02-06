# S-0031: Remove File-Based WebSocket Infrastructure

**Phase:** -1 (Legacy Code Cleanup)  
**Effort:** 4-6 hours  
**Priority:** Critical  
**Dependencies:** None

---

## Narrative

This specification covers the removal of the file-based WebSocket infrastructure that currently watches the filesystem for changes and broadcasts updates to the frontend. This is the first step in the cleanup phase and will remove approximately 800 lines of legacy code.

The key files to remove are:

- `app/backend/routers/websocket.py` (537 lines) - ConnectionManager and filesystem watching
- `app/frontend/src/hooks/useProjectWebSocket.ts` (289 lines) - React WebSocket hook

The console streaming WebSocket (`/api/agents/{agent_id}/console` in `agents.py`) must be preserved as it will continue to be used for real-time log streaming.

---

## Acceptance Criteria

- [ ] Delete **app/backend/routers/websocket.py** entirely (537 lines removed)
- [ ] Delete **app/frontend/src/hooks/useProjectWebSocket.ts** entirely (289 lines removed)
- [ ] Remove router registration from **app/backend/main.py** (line importing and including websocket router)
- [ ] Verify console streaming WebSocket in **app/backend/routers/agents.py** (lines 791-1002) is untouched
- [ ] Verify LiveConsolePanel in **app/frontend/src/Main.tsx** (lines 777-1219) still references console WebSocket
- [ ] Application starts without import errors
- [ ] Console streaming still works when testing with a running agent

---

## Technical Notes

### Files to Delete

**Backend:**

```
app/backend/routers/websocket.py
```

**Frontend:**

```
app/frontend/src/hooks/useProjectWebSocket.ts
```

### Files to Modify

**app/backend/main.py:**

- Remove: `from routers import websocket`
- Remove: `app.include_router(websocket.router)`

**Verify Preservation:**

- **app/backend/routers/agents.py** lines 791-1002 (console WebSocket endpoint)
- **app/frontend/src/Main.tsx** lines 777-1219 (LiveConsolePanel component)

### Console Streaming Pattern

The console streaming WebSocket follows a different pattern:

```python
@router.websocket("/agents/{agent_id}/console")
async def console_websocket(websocket: WebSocket, agent_id: str):
    # Real-time log file tailing
    # This stays - we need it for Phase 1
```

This endpoint streams log files from `runs/{run_id}/output.log` and is NOT related to the file-based state watching we're removing.

---

## Dependencies

**Depends On:** None (first spec in cleanup phase)

**Blocks:**

- S-0032: Remove Backend File Operations
- S-0033: Remove Frontend Polling Mechanisms

---

## Validation Criteria

### Backend Verification

- [ ] Start backend: `cd app/backend && python main.py` (exit code 0, no import errors)
- [ ] No references to `websocket.router` in **main.py**
- [ ] File **app/backend/routers/websocket.py** does not exist
- [ ] Console endpoint exists: `curl http://localhost:8080/docs` and verify `/api/agents/{agent_id}/console` is listed

### Frontend Verification

- [ ] File **app/frontend/src/hooks/useProjectWebSocket.ts** does not exist
- [ ] No imports of `useProjectWebSocket` in frontend code: `grep -r "useProjectWebSocket" app/frontend/src/`
- [ ] Frontend builds: `cd app/frontend && npm run build` (exit code 0)

### Integration Test

- [ ] Start backend
- [ ] Start an agent via felix-agent.ps1
- [ ] Open frontend console panel
- [ ] Verify logs stream in real-time
- [ ] Verify no WebSocket connection to old `/ws/project/{project_id}` endpoint

---

## Rollback Strategy

If issues arise:

1. Revert commit: `git revert HEAD`
2. Restore deleted files from git history
3. Re-register websocket router in main.py

**Backup Branch:** Create `backup/pre-cleanup` branch before starting cleanup phase

---

## Notes

- This is a pure deletion spec - no new code is written
- The distinction between "file-watching WebSocket" (delete) and "console-streaming WebSocket" (preserve) is critical
- After this spec, the frontend will lose real-time state updates temporarily (acceptable - Phase 1 restores them)
- Console streaming for live logs continues to work
