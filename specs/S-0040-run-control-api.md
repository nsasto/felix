# S-0040: Run Control API Endpoints

**Phase:** 1 (Core Orchestration)  
**Effort:** 6-8 hours  
**Priority:** High  
**Dependencies:** S-0039

---

## Narrative

This specification covers implementing REST API endpoints for creating and controlling runs. The backend will create run records in the database and send control commands to agents via the control WebSocket. This provides the orchestration layer for starting, stopping, and tracking agent runs.

---

## Acceptance Criteria

### API Endpoints

- [ ] `POST /api/agents/runs` - Create run and send START command to agent
- [ ] `POST /api/agents/runs/{run_id}/stop` - Send STOP command to agent
- [ ] `GET /api/agents/runs` - List recent runs for current project
- [ ] `GET /api/agents/runs/{run_id}` - Get single run details

### Request/Response Models

- [ ] Add to **app/backend/models.py**:
  - `RunCreateRequest`
  - `RunResponse`
  - `RunListResponse`

### Router Implementation

- [ ] Update **app/backend/routers/agents.py** with run endpoints
- [ ] Use `RunWriter` for database operations
- [ ] Use `control_manager` to send commands to agents
- [ ] Return proper HTTP status codes

### Error Handling

- [ ] Handle agent not connected (503 Service Unavailable)
- [ ] Handle run not found (404)
- [ ] Handle invalid agent_id (404)

---

## Technical Notes

### Pydantic Models

```python
from typing import Optional
from datetime import datetime

class RunCreateRequest(BaseModel):
    agent_id: str = Field(..., description="Agent to run")
    requirement_id: Optional[str] = Field(None, description="Requirement to work on")
    metadata: Optional[Dict[str, Any]] = Field(default_factory=dict)

class RunResponse(BaseModel):
    id: str
    project_id: str
    agent_id: str
    requirement_id: Optional[str]
    status: str
    started_at: Optional[datetime]
    completed_at: Optional[datetime]
    error: Optional[str]
    metadata: Dict[str, Any]
    # Joined fields
    agent_name: Optional[str]
    requirement_title: Optional[str]

class RunListResponse(BaseModel):
    runs: list[RunResponse]
    count: int
```

### Router Implementation

```python
from database.writers import RunWriter
from websocket.control import control_manager

@router.post("/runs", response_model=RunResponse, status_code=201)
async def create_run(
    request: RunCreateRequest,
    db = Depends(get_db),
    user: dict = Depends(get_current_user)
):
    """Create a new run and send START command to agent"""
    agent_writer = AgentWriter(db)
    run_writer = RunWriter(db)

    # Verify agent exists
    agent = await agent_writer.get_agent(request.agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail=f"Agent {request.agent_id} not found")

    # Verify agent is connected
    if not control_manager.is_connected(request.agent_id):
        raise HTTPException(status_code=503, detail=f"Agent {request.agent_id} not connected")

    # Create run in database
    project_id = user.get("project_id", "00000000-0000-0000-0000-000000000001")
    run = await run_writer.create_run(
        project_id=project_id,
        agent_id=request.agent_id,
        requirement_id=request.requirement_id,
        metadata=request.metadata
    )

    # Send START command to agent via WebSocket
    command = {
        "type": "command",
        "command": "START",
        "run_id": run["id"],
        "requirement_id": request.requirement_id,
        "metadata": request.metadata
    }
    await control_manager.send_command(request.agent_id, command)

    # Update run status to 'running'
    await run_writer.update_run_status(run["id"], "running")

    return RunResponse(**run, agent_name=agent["name"])

@router.post("/runs/{run_id}/stop", status_code=200)
async def stop_run(
    run_id: str,
    db = Depends(get_db),
    user: dict = Depends(get_current_user)
):
    """Send STOP command to agent"""
    run_writer = RunWriter(db)

    # Verify run exists
    run = await run_writer.get_run(run_id)
    if not run:
        raise HTTPException(status_code=404, detail=f"Run {run_id} not found")

    agent_id = run["agent_id"]

    # Verify agent is connected
    if not control_manager.is_connected(agent_id):
        raise HTTPException(status_code=503, detail=f"Agent {agent_id} not connected")

    # Send STOP command to agent
    command = {
        "type": "command",
        "command": "STOP",
        "run_id": run_id
    }
    await control_manager.send_command(agent_id, command)

    return {"status": "ok", "run_id": run_id, "command": "STOP"}

@router.get("/runs", response_model=RunListResponse)
async def list_runs(
    limit: int = 50,
    db = Depends(get_db),
    user: dict = Depends(get_current_user)
):
    """List recent runs for current project"""
    run_writer = RunWriter(db)

    project_id = user.get("project_id", "00000000-0000-0000-0000-000000000001")
    runs = await run_writer.list_runs(project_id, limit)

    return RunListResponse(
        runs=[RunResponse(**run) for run in runs],
        count=len(runs)
    )

@router.get("/runs/{run_id}", response_model=RunResponse)
async def get_run(
    run_id: str,
    db = Depends(get_db),
    user: dict = Depends(get_current_user)
):
    """Get single run details"""
    run_writer = RunWriter(db)

    run = await run_writer.get_run(run_id)
    if not run:
        raise HTTPException(status_code=404, detail=f"Run {run_id} not found")

    return RunResponse(**run)
```

---

## Dependencies

**Depends On:**

- S-0039: Control WebSocket Infrastructure

**Blocks:**

- S-0041: Console Streaming WebSocket

---

## Validation Criteria

### Backend Verification

- [ ] Backend starts: `cd app/backend && python main.py`
- [ ] API docs show run endpoints: Open `http://localhost:8080/docs`

### Endpoint Testing

**1. Connect agent to control WebSocket:**

```bash
wscat -c ws://localhost:8080/api/agents/test-agent-1/control
```

**2. Create run:**

```bash
curl -X POST http://localhost:8080/api/agents/runs \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "test-agent-1", "requirement_id": null}'
```

Expected: 201 status, RunResponse JSON, agent receives START command in WebSocket

**3. List runs:**

```bash
curl http://localhost:8080/api/agents/runs
```

Expected: 200 status, `{"runs": [...], "count": 1}`

**4. Get run:**

```bash
curl http://localhost:8080/api/agents/runs/{run_id}
```

Expected: 200 status, RunResponse JSON

**5. Stop run:**

```bash
curl -X POST http://localhost:8080/api/agents/runs/{run_id}/stop
```

Expected: 200 status, agent receives STOP command in WebSocket

**6. Error case - agent not connected:**

```bash
# Disconnect agent, then create run
curl -X POST http://localhost:8080/api/agents/runs \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "test-agent-1"}'
```

Expected: 503 status, `{"detail": "Agent test-agent-1 not connected"}`

### Database Verification

- [ ] Verify run in database: `psql -U postgres -d felix -c "SELECT * FROM runs;"`
- [ ] Verify run status is 'running' after create
- [ ] Verify run has started_at timestamp

---

## Rollback Strategy

If issues arise:

1. Remove run endpoints from routers/agents.py
2. Revert RunWriter changes if any
3. Continue using Phase 0 state

---

## Notes

- Runs can only be created for connected agents
- START command is sent immediately when run is created
- STOP command is sent when stop endpoint is called
- Run status is tracked in database (pending → running → completed/failed)
- Agent is responsible for updating run status via control WebSocket
- Frontend will poll these endpoints in S-0042 (Phase 1)
- Phase 3 will replace polling with Supabase Realtime subscriptions

