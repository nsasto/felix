# S-0037: Database Writers Implementation

**Phase:** 0 (Local Postgres Setup)  
**Effort:** 6-8 hours  
**Priority:** High  
**Dependencies:** S-0036

---

## Narrative

This specification covers implementing database writer classes that encapsulate all CRUD operations for agents, runs, and artifacts. This provides a clean API for the backend to persist state to PostgreSQL instead of writing to JSON files.

The goal is to create AgentWriter and RunWriter classes with async methods that match the current file-based operations but write to the database instead.

---

## Acceptance Criteria

### Create Writers Module

- [ ] Create **app/backend/database/writers.py**

### AgentWriter Class

- [ ] Implement `AgentWriter` class with methods:
  - `async upsert_agent(agent_id, project_id, name, type, metadata) -> dict`
  - `async update_heartbeat(agent_id) -> None`
  - `async update_status(agent_id, status) -> None`
  - `async get_agent(agent_id) -> dict`
  - `async list_agents(project_id) -> List[dict]`

### RunWriter Class

- [ ] Implement `RunWriter` class with methods:
  - `async create_run(project_id, agent_id, requirement_id, metadata) -> dict`
  - `async update_run_status(run_id, status, error=None) -> None`
  - `async complete_run(run_id, status, error=None) -> None`
  - `async get_run(run_id) -> dict`
  - `async list_runs(project_id, limit=50) -> List[dict]`
  - `async create_artifact(run_id, artifact_type, file_path, metadata) -> dict`

### Error Handling

- [ ] Wrap database operations in try/except blocks
- [ ] Raise meaningful exceptions (AgentNotFound, RunNotFound)
- [ ] Log database errors

### Type Hints

- [ ] Use proper type hints for all parameters and return values
- [ ] Import typing (List, Dict, Optional)

---

## Technical Notes

### AgentWriter Implementation

```python
from typing import List, Dict, Optional
from databases import Database
from datetime import datetime

class AgentWriter:
    def __init__(self, db: Database):
        self.db = db

    async def upsert_agent(
        self,
        agent_id: str,
        project_id: str,
        name: str,
        type: str,
        metadata: dict = None
    ) -> dict:
        """Insert or update agent record"""
        query = """
        INSERT INTO agents (id, project_id, name, type, metadata, created_at, updated_at)
        VALUES (:id, :project_id, :name, :type, :metadata, NOW(), NOW())
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name,
            type = EXCLUDED.type,
            metadata = EXCLUDED.metadata,
            updated_at = NOW()
        RETURNING *
        """
        values = {
            "id": agent_id,
            "project_id": project_id,
            "name": name,
            "type": type,
            "metadata": metadata or {}
        }
        result = await self.db.fetch_one(query, values)
        return dict(result)

    async def update_heartbeat(self, agent_id: str) -> None:
        """Update agent heartbeat timestamp"""
        query = """
        UPDATE agents
        SET heartbeat_at = NOW(), updated_at = NOW()
        WHERE id = :agent_id
        """
        await self.db.execute(query, {"agent_id": agent_id})

    async def update_status(self, agent_id: str, status: str) -> None:
        """Update agent status"""
        query = """
        UPDATE agents
        SET status = :status, updated_at = NOW()
        WHERE id = :agent_id
        """
        await self.db.execute(query, {"agent_id": agent_id, "status": status})

    async def get_agent(self, agent_id: str) -> Optional[dict]:
        """Get single agent by ID"""
        query = "SELECT * FROM agents WHERE id = :agent_id"
        result = await self.db.fetch_one(query, {"agent_id": agent_id})
        return dict(result) if result else None

    async def list_agents(self, project_id: str) -> List[dict]:
        """List all agents for a project"""
        query = """
        SELECT * FROM agents
        WHERE project_id = :project_id
        ORDER BY created_at DESC
        """
        results = await self.db.fetch_all(query, {"project_id": project_id})
        return [dict(row) for row in results]
```

### RunWriter Implementation

```python
class RunWriter:
    def __init__(self, db: Database):
        self.db = db

    async def create_run(
        self,
        project_id: str,
        agent_id: str,
        requirement_id: Optional[str] = None,
        metadata: dict = None
    ) -> dict:
        """Create a new run"""
        query = """
        INSERT INTO runs (project_id, agent_id, requirement_id, status, metadata)
        VALUES (:project_id, :agent_id, :requirement_id, 'pending', :metadata)
        RETURNING *
        """
        values = {
            "project_id": project_id,
            "agent_id": agent_id,
            "requirement_id": requirement_id,
            "metadata": metadata or {}
        }
        result = await self.db.fetch_one(query, values)
        return dict(result)

    async def update_run_status(
        self,
        run_id: str,
        status: str,
        error: Optional[str] = None
    ) -> None:
        """Update run status"""
        query = """
        UPDATE runs
        SET status = :status,
            error = :error,
            started_at = CASE WHEN :status = 'running' AND started_at IS NULL THEN NOW() ELSE started_at END
        WHERE id = :run_id
        """
        await self.db.execute(query, {"run_id": run_id, "status": status, "error": error})

    async def complete_run(
        self,
        run_id: str,
        status: str,  # 'completed' or 'failed'
        error: Optional[str] = None
    ) -> None:
        """Mark run as complete"""
        query = """
        UPDATE runs
        SET status = :status,
            completed_at = NOW(),
            error = :error
        WHERE id = :run_id
        """
        await self.db.execute(query, {"run_id": run_id, "status": status, "error": error})

    async def get_run(self, run_id: str) -> Optional[dict]:
        """Get single run by ID"""
        query = "SELECT * FROM runs WHERE id = :run_id"
        result = await self.db.fetch_one(query, {"run_id": run_id})
        return dict(result) if result else None

    async def list_runs(
        self,
        project_id: str,
        limit: int = 50
    ) -> List[dict]:
        """List recent runs for a project"""
        query = """
        SELECT r.*, a.name as agent_name, req.title as requirement_title
        FROM runs r
        LEFT JOIN agents a ON r.agent_id = a.id
        LEFT JOIN requirements req ON r.requirement_id = req.id
        WHERE r.project_id = :project_id
        ORDER BY r.created_at DESC
        LIMIT :limit
        """
        results = await self.db.fetch_all(query, {"project_id": project_id, "limit": limit})
        return [dict(row) for row in results]

    async def create_artifact(
        self,
        run_id: str,
        artifact_type: str,
        file_path: str,
        metadata: dict = None
    ) -> dict:
        """Create a run artifact record"""
        query = """
        INSERT INTO run_artifacts (run_id, artifact_type, file_path, metadata, created_at)
        VALUES (:run_id, :artifact_type, :file_path, :metadata, NOW())
        RETURNING *
        """
        values = {
            "run_id": run_id,
            "artifact_type": artifact_type,
            "file_path": file_path,
            "metadata": metadata or {}
        }
        result = await self.db.fetch_one(query, values)
        return dict(result)
```

### Error Handling

```python
class AgentNotFoundError(Exception):
    pass

class RunNotFoundError(Exception):
    pass

# In AgentWriter.get_agent()
result = await self.db.fetch_one(query, {"agent_id": agent_id})
if not result:
    raise AgentNotFoundError(f"Agent {agent_id} not found")
return dict(result)
```

---

## Dependencies

**Depends On:**

- S-0036: Backend Database Integration Layer

**Blocks:**

- S-0038: Agent Registration and Heartbeat API

---

## Validation Criteria

### File Creation

- [ ] File exists: **app/backend/database/writers.py**
- [ ] File imports without errors: `cd app/backend && python -c "from database.writers import AgentWriter, RunWriter"`

### AgentWriter Verification

- [ ] Test upsert_agent:

```python
from database.db import database, startup
from database.writers import AgentWriter
import asyncio

async def test():
    await startup()
    writer = AgentWriter(database)
    agent = await writer.upsert_agent(
        agent_id="test-agent-1",
        project_id="00000000-0000-0000-0000-000000000001",
        name="Test Agent",
        type="ralph"
    )
    print(agent)

asyncio.run(test())
```

- [ ] Test update_heartbeat: Agent heartbeat_at timestamp updates
- [ ] Test update_status: Agent status changes to 'running'
- [ ] Test list_agents: Returns list with 1 agent

### RunWriter Verification

- [ ] Test create_run:

```python
async def test():
    await startup()
    writer = RunWriter(database)
    run = await writer.create_run(
        project_id="00000000-0000-0000-0000-000000000001",
        agent_id="test-agent-1"
    )
    print(run)
    assert run["status"] == "pending"

asyncio.run(test())
```

- [ ] Test update_run_status: Run status changes to 'running', started_at set
- [ ] Test complete_run: Run status changes to 'completed', completed_at set
- [ ] Test list_runs: Returns list with 1 run
- [ ] Test create_artifact: Artifact record created with run_id reference

### Database Verification

- [ ] Verify agent in database: `psql -U postgres -d felix -c "SELECT * FROM agents;"`
- [ ] Verify run in database: `psql -U postgres -d felix -c "SELECT * FROM runs;"`
- [ ] Verify artifact in database: `psql -U postgres -d felix -c "SELECT * FROM run_artifacts;"`

---

## Rollback Strategy

If issues arise:

1. Delete database/writers.py
2. Revert any router changes that use writers
3. Continue using file-based operations temporarily

---

## Notes

- Writers encapsulate all database operations - no raw SQL in routers
- Use `databases` library for async database operations (not SQLAlchemy ORM yet)
- JSONB columns (metadata) accept Python dicts, automatically converted to JSON
- UUID columns accept string UUIDs
- TIMESTAMPTZ columns use Python datetime objects
- Writers should be instantiated per-request with `Depends(get_db)`
- Type hints improve IDE autocomplete and catch errors early
- Error handling prevents cryptic database errors from bubbling up
- Writers are stateless - safe to create new instance per request
