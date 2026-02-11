# S-0041: Console Streaming WebSocket

**Phase:** 1 (Core Orchestration)  
**Effort:** 4-6 hours  
**Priority:** Medium  
**Dependencies:** S-0040

---

## Narrative

This specification covers implementing the console streaming WebSocket endpoint that tails log files from `runs/{run_id}/output.log` and streams new content to connected frontend clients in real-time. This WebSocket was preserved during Phase -1 cleanup and now needs to be integrated with the new database-backed run tracking.

---

## Acceptance Criteria

### WebSocket Endpoint

- [ ] Verify endpoint exists: `@router.websocket("/api/agents/{agent_id}/console")`
- [ ] Accept optional query parameter: `run_id`
- [ ] Tail log file: `runs/{run_id}/output.log`
- [ ] Stream new log lines to connected clients
- [ ] Handle file not found gracefully
- [ ] Handle multiple concurrent connections

### Log File Tailing

- [ ] Use async file watching (aiofiles)
- [ ] Start from end of file (or beginning if `from_start=true` query param)
- [ ] Send new lines as they're written
- [ ] Handle log file rotation

### Error Handling

- [ ] Log file not found → send error message to client
- [ ] Connection timeout → cleanup properly
- [ ] File I/O errors → log and notify client

---

## Technical Notes

### Console WebSocket Endpoint

```python
import aiofiles
import asyncio
from pathlib import Path

@router.websocket("/{agent_id}/console")
async def console_websocket(
    websocket: WebSocket,
    agent_id: str,
    run_id: str = None,
    from_start: bool = False
):
    """
    Stream console output from agent run log file.

    Query parameters:
    - run_id: Run ID to stream logs for (required)
    - from_start: If true, stream from beginning of file (default: false, stream from end)
    """
    await websocket.accept()

    if not run_id:
        await websocket.send_json({"error": "run_id query parameter is required"})
        await websocket.close()
        return

    log_path = Path(f"runs/{run_id}/output.log")

    if not log_path.exists():
        await websocket.send_json({"error": f"Log file not found: {log_path}"})
        await websocket.close()
        return

    try:
        async with aiofiles.open(log_path, mode='r') as f:
            # Start from end of file unless from_start=true
            if not from_start:
                await f.seek(0, 2)  # Seek to end

            # Tail file and stream new lines
            while True:
                line = await f.readline()
                if line:
                    await websocket.send_text(line)
                else:
                    # No new data, wait a bit before checking again
                    await asyncio.sleep(0.1)

    except WebSocketDisconnect:
        logger.info(f"Client disconnected from console stream for run {run_id}")
    except Exception as e:
        logger.error(f"Error streaming console for run {run_id}: {e}")
        await websocket.send_json({"error": str(e)})
    finally:
        await websocket.close()
```

### Frontend Integration

The frontend's LiveConsolePanel component (preserved in Main.tsx lines 777-1219) will connect to this WebSocket:

```typescript
// Frontend connection (existing code)
const ws = new WebSocket(
  `ws://localhost:8080/api/agents/${agentId}/console?run_id=${runId}`,
);

ws.onmessage = (event) => {
  setConsoleOutput((prev) => prev + event.data);
};
```

---

## Dependencies

**Depends On:**

- S-0040: Run Control API Endpoints

**Blocks:**

- S-0042: Frontend API Client and Dashboard

---

## Validation Criteria

### Backend Verification

- [ ] Backend starts: `cd app/backend && python main.py`
- [ ] API docs show console WebSocket: Open `http://localhost:8080/docs`

### Log File Creation

```bash
# Create test log file
mkdir -p runs/test-run-1
echo "Line 1: Agent starting..." > runs/test-run-1/output.log
echo "Line 2: Processing requirement..." >> runs/test-run-1/output.log
```

### WebSocket Connection Test

**Test with wscat:**

```bash
# Connect to console stream
wscat -c "ws://localhost:8080/api/agents/test-agent-1/console?run_id=test-run-1"

# Should receive existing log lines

# In another terminal, append to log file:
echo "Line 3: New log entry" >> runs/test-run-1/output.log

# Should see new line streamed to wscat immediately
```

### Frontend Integration Test

- [ ] Start backend
- [ ] Start frontend: `cd app/frontend && npm run dev`
- [ ] Create a run via API
- [ ] Open frontend console panel
- [ ] Verify logs stream in real-time

### Error Handling Test

**Missing log file:**

```bash
wscat -c "ws://localhost:8080/api/agents/test-agent-1/console?run_id=nonexistent"
```

Expected: `{"error": "Log file not found: runs/nonexistent/output.log"}`

**Missing run_id parameter:**

```bash
wscat -c "ws://localhost:8080/api/agents/test-agent-1/console"
```

Expected: `{"error": "run_id query parameter is required"}`

---

## Rollback Strategy

If issues arise:

1. Revert console WebSocket endpoint changes
2. Restore original implementation from Phase -1 backup
3. Log errors and investigate

---

## Notes

- This endpoint was preserved during Phase -1 cleanup (S-0031)
- Console WebSocket is unidirectional: backend → frontend
- Control WebSocket is bidirectional: backend ↔ agent
- Log files are written by agents to `runs/{run_id}/output.log`
- Frontend LiveConsolePanel component connects to this endpoint
- Supports streaming from beginning or end of file
- Uses async file I/O for performance
- Can handle multiple clients streaming same log file
- 100ms poll interval balances responsiveness and CPU usage

