# S-0038: Agent Registration and Heartbeat API

**Phase:** 0 (Local Postgres Setup)  
**Effort:** 4-6 hours  
**Priority:** High  
**Dependencies:** S-0037

---

## Narrative

This specification covers implementing REST API endpoints for agent registration, heartbeat, and status management. These endpoints allow felix-agent.ps1 to register itself with the backend, maintain heartbeat, and update status. This replaces the file-based agent tracking with database-backed API calls.

---

## Acceptance Criteria

### API Endpoints

- [ ] `POST /api/agents/register` - Register a new agent or update existing
- [ ] `POST /api/agents/{agent_id}/heartbeat` - Update agent heartbeat timestamp
- [ ] `POST /api/agents/{agent_id}/status` - Update agent status
- [ ] `GET /api/agents` - List all agents for current project
- [ ] `GET /api/agents/{agent_id}` - Get single agent details

### Request/Response Models

- [ ] Create Pydantic models in **app/backend/models.py**:
  - `AgentRegisterRequest`
  - `AgentStatusUpdate`
  - `AgentResponse`
  - `AgentListResponse`

### Router Implementation

- [ ] Update **app/backend/routers/agents.py** to use database writers
- [ ] Add dependency injection for `get_db()` and `get_current_user()`
- [ ] Return proper HTTP status codes (200, 201, 404, 500)

### Error Handling

- [ ] Handle agent not found (404)
- [ ] Handle database errors (500)
- [ ] Validate request bodies with Pydantic

---

## Technical Notes

### Pydantic Models (models.py)

```python
from pydantic import BaseModel, Field
from typing import Optional, Dict, Any
from datetime import datetime

class AgentRegisterRequest(BaseModel):
    agent_id: str = Field(..., description="Unique agent identifier")
    name: str = Field(..., description="Agent name")
    type: str = Field(default="ralph", description="Agent type")
    metadata: Optional[Dict[str, Any]] = Field(default_factory=dict)

class AgentStatusUpdate(BaseModel):
    status: str = Field(..., description="New status: idle, running, stopped, error")

class AgentResponse(BaseModel):
    id: str
    project_id: str
    name: str
    type: str
    status: str
    heartbeat_at: Optional[datetime]
    metadata: Dict[str, Any]
    created_at: datetime
    updated_at: datetime

class AgentListResponse(BaseModel):
    agents: list[AgentResponse]
    count: int
```

### Router Implementation (routers/agents.py)

```python
from fastapi import APIRouter, Depends, HTTPException
from database.db import get_db
from database.writers import AgentWriter
from auth import get_current_user
from models import AgentRegisterRequest, AgentStatusUpdate, AgentResponse, AgentListResponse
from typing import List

router = APIRouter(prefix="/api/agents", tags=["agents"])

@router.post("/register", response_model=AgentResponse, status_code=201)
async def register_agent(
    request: AgentRegisterRequest,
    db = Depends(get_db),
    user: dict = Depends(get_current_user)
):
    """Register a new agent or update existing agent"""
    writer = AgentWriter(db)

    # Use dev project ID from user context
    project_id = user.get("project_id", "00000000-0000-0000-0000-000000000001")

    agent = await writer.upsert_agent(
        agent_id=request.agent_id,
        project_id=project_id,
        name=request.name,
        type=request.type,
        metadata=request.metadata
    )

    return AgentResponse(**agent)

@router.post("/{agent_id}/heartbeat", status_code=200)
async def update_heartbeat(
    agent_id: str,
    db = Depends(get_db),
    user: dict = Depends(get_current_user)
):
    """Update agent heartbeat timestamp"""
    writer = AgentWriter(db)

    # Verify agent exists
    agent = await writer.get_agent(agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail=f"Agent {agent_id} not found")

    await writer.update_heartbeat(agent_id)
    return {"status": "ok", "agent_id": agent_id}

@router.post("/{agent_id}/status", status_code=200)
async def update_status(
    agent_id: str,
    request: AgentStatusUpdate,
    db = Depends(get_db),
    user: dict = Depends(get_current_user)
):
    """Update agent status"""
    writer = AgentWriter(db)

    # Verify agent exists
    agent = await writer.get_agent(agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail=f"Agent {agent_id} not found")

    # Validate status
    valid_statuses = ["idle", "running", "stopped", "error"]
    if request.status not in valid_statuses:
        raise HTTPException(status_code=400, detail=f"Invalid status. Must be one of: {valid_statuses}")

    await writer.update_status(agent_id, request.status)
    return {"status": "ok", "agent_id": agent_id, "new_status": request.status}

@router.get("/", response_model=AgentListResponse)
async def list_agents(
    db = Depends(get_db),
    user: dict = Depends(get_current_user)
):
    """List all agents for current project"""
    writer = AgentWriter(db)

    project_id = user.get("project_id", "00000000-0000-0000-0000-000000000001")
    agents = await writer.list_agents(project_id)

    return AgentListResponse(
        agents=[AgentResponse(**agent) for agent in agents],
        count=len(agents)
    )

@router.get("/{agent_id}", response_model=AgentResponse)
async def get_agent(
    agent_id: str,
    db = Depends(get_db),
    user: dict = Depends(get_current_user)
):
    """Get single agent details"""
    writer = AgentWriter(db)

    agent = await writer.get_agent(agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail=f"Agent {agent_id} not found")

    return AgentResponse(**agent)
```

### Update main.py

```python
from routers import agents

app.include_router(agents.router)
```

---

## Dependencies

**Depends On:**

- S-0037: Database Writers Implementation

**Blocks:**

- S-0039: Control WebSocket Infrastructure (Phase 1)

---

## Validation Criteria

### File Creation

- [ ] File exists: **app/backend/models.py**
- [ ] Models import without errors: `cd app/backend && python -c "from models import AgentRegisterRequest"`

### Backend Verification

- [ ] Backend starts: `cd app/backend && python main.py` (exit code 0)
- [ ] API docs show agent endpoints: Open `http://localhost:8080/docs`, verify `/api/agents/register`, `/api/agents/{agent_id}/heartbeat`, etc.

### Endpoint Testing (curl)

**Register Agent:**

```bash
curl -X POST http://localhost:8080/api/agents/register \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "test-agent-1", "name": "Test Agent", "type": "ralph"}'
```

Expected: 201 status, AgentResponse JSON

**Update Heartbeat:**

```bash
curl -X POST http://localhost:8080/api/agents/test-agent-1/heartbeat
```

Expected: 200 status, `{"status": "ok", "agent_id": "test-agent-1"}`

**Update Status:**

```bash
curl -X POST http://localhost:8080/api/agents/test-agent-1/status \
  -H "Content-Type: application/json" \
  -d '{"status": "running"}'
```

Expected: 200 status, `{"status": "ok", "agent_id": "test-agent-1", "new_status": "running"}`

**List Agents:**

```bash
curl http://localhost:8080/api/agents
```

Expected: 200 status, `{"agents": [...], "count": 1}`

**Get Agent:**

```bash
curl http://localhost:8080/api/agents/test-agent-1
```

Expected: 200 status, AgentResponse JSON

**Get Nonexistent Agent:**

```bash
curl http://localhost:8080/api/agents/nonexistent
```

Expected: 404 status, `{"detail": "Agent nonexistent not found"}`

### Database Verification

- [ ] Verify agent in database: `psql -U postgres -d felix -c "SELECT * FROM agents WHERE id = 'test-agent-1';"`
- [ ] Verify heartbeat timestamp updated: Check `heartbeat_at` column
- [ ] Verify status updated: Check `status` column

---

## Rollback Strategy

If issues arise:

1. Remove agent endpoints from routers/agents.py
2. Revert main.py router registration
3. Delete models.py if created

---

## Notes

- All endpoints require authentication via `Depends(get_current_user)`
- In AUTH_MODE=disabled, all agents belong to dev project
- Phase 2 will add proper multi-tenant isolation via RLS
- Heartbeat endpoint should be called every 30-60 seconds by agent
- Status endpoint is called when agent starts/stops/errors
- Console streaming WebSocket endpoint remains in agents.py (preserved from S-0031)
- These endpoints replace file-based agent tracking (agents.json)
- Frontend will call these endpoints in Phase 1 (S-0042)

