# Felix Cloud Migration Plan - Concrete Implementation Steps

## Overview

This document provides step-by-step implementation instructions for migrating Felix from file-based storage to cloud-native database architecture. The approach is incremental and pragmatic: start with local Postgres, validate orchestration, then layer on Supabase features.

**Philosophy**:

- Schema matches Supabase from day one (mechanical migration later)
- Core orchestration first, cloud features second
- Each phase is additive (no rewrites)
- Always shippable at the end of each phase

**Timeline**: 4-5 weeks total (includes cleanup phase)

---

## Phase -1: Legacy Code Cleanup (1 day)

**Goal**: Remove file-based state management, polling mechanisms, and dead weight before starting cloud migration. Start from a clean slate.

**Why This Matters**:

- ~1,700 lines of legacy code identified
- Prevents confusion between old/new patterns
- Forces commitment to cloud approach (no fallback to old patterns)
- Reduces merge conflicts during migration
- Makes Phase 0 implementation cleaner

### Step 1: Delete Files Entirely

**1. Delete `app/backend/routers/websocket.py` (537 lines)**:

```powershell
# Remove file watching WebSocket infrastructure
git rm app\backend\routers\websocket.py
```

**What it did**: Watched felix/state.json, requirements.json, and runs/ directory using filesystem watcher (watchfiles library), sent changes via WebSocket.

**Why delete**: In cloud architecture, state comes from database subscriptions (Supabase Realtime), not filesystem watching.

**Note**: Console streaming WebSocket in agents.py is preserved - only state watching is removed.

**2. Delete `app/frontend/src/hooks/useProjectWebSocket.ts`**:

```powershell
git rm app\frontend\src\hooks\useProjectWebSocket.ts
```

**What it did**: React hook for WebSocket state updates (connected to the deleted websocket.py)

**Why delete**: Will be replaced with Supabase Realtime hooks in Phase 3

### Step 2: Remove Backend File Operations

**1. Clean up `app/backend/routers/agents.py`**:

Remove agent registry file operations (lines 164-228):

```powershell
# Open file and delete these sections:
# - Line 168: _get_agents_file_path() function
# - Line 191: _load_agents_registry() function
# - Line 217: _save_agents_registry() function
# - Lines 164-228: All file-based agent registry logic
```

**CRITICAL - Keep**:

- Request/Response models (lines 1-104)
- Console streaming WebSocket endpoint (lines 791-1002) - **THIS MUST STAY!**
- All other API endpoints

**2. Clean up `app/backend/routers/agent_config.py`**:

Remove file operations (lines 75-117):

```powershell
# Delete these functions:
# - Line 78: _get_agents_config_path()
# - Line 88: _load_agents_config()
# - Line 116: _save_agents_config()
```

**Keep**:

- Models (lines 22-74)
- API endpoints (lines 189-end) - will convert to database access in Phase 0

**3. Clean up `app/backend/routers/routes.py`**:

Remove runs directory scanning (lines 513-567):

```powershell
# Delete: Lines 534-567 that scan runs/ directory on disk
# Delete comment on line 534: "# Read existing runs from runs/ directory"
```

Remove artifact reading from disk (lines 671-742):

```powershell
# Delete: Lines 676-710 that read artifacts from runs/ directory
# Delete: Line 699 containing Path(f"runs/{run_id}/{artifact_name}")
```

**Keep**:

- In-memory agent process tracking (lines 66-74) - still needed for local subprocess management
- Start/Stop agent endpoints (lines 237-396) - will modify to use cloud API later

**4. Clean up `app/backend/storage.py`**:

Remove state.json and requirements.json direct reads:

```powershell
# Search for and remove:
# - Any code reading "felix/state.json" directly
# - Line 124: requirements.json path construction
# - Direct file operations on state/requirements files
```

**Keep**:

- Specs reading/writing (stays on filesystem for now)
- README operations
- Project path utilities

**5. Clean up `app/backend/projects.py`**:

Remove requirement status reading (lines 124-145):

```powershell
# Delete:
# - Line 124: req_file = project_path / "felix" / "requirements.json"
# - Line 125: if not req_file.exists(): return None
# - Lines 127-145: Logic reading requirements.json for status
```

**Keep**:

- Project registration (lines 1-100)
- ~/.felix/projects.json operations
- get_felix_home(), load_projects(), save_projects()

**6. Clean up `app/backend/main.py`**:

Remove agent migration logic (lines 39-150):

```powershell
# Delete:
# - Lines 39-93: Check for agents.json, migrate from config.json
# - Lines 95-150: Create default agent in agents.json
```

**Keep**:

- Imports, logging setup (lines 1-35)
- CORS configuration (lines 207-230)
- Router registration (lines 207-230)

**7. Remove websocket router registration from `app/backend/main.py`**:

```python
# DELETE these lines:
from app.backend.routers import websocket
app.include_router(websocket.router)
```

### Step 3: Remove Frontend Polling

**1. Clean up `app/frontend/src/Main.tsx`**:

Remove polling state and intervals (lines 1482-1740):

```typescript
// DELETE these sections:
// Lines 1482-1527: Polling mode types and storage functions
// Lines 1554-1585: Polling state (pollingMode, isPollingActive, debounce)
// Lines 1705-1732: Agent polling interval (5 seconds)
// Lines 1734-1738: Requirements polling interval (10 seconds)
// Lines 1597-1608: togglePollingMode function
// Lines 105-124 in Toolbar: Polling mode toggle UI
```

**CRITICAL - Keep**:

- Lines 777-1219: LiveConsolePanel component (console WebSocket - **THIS MUST STAY!**)
- Lines 1610-1685: fetchAgents, fetchRequirements functions (convert to single fetch, no polling)
- Agent list display, toolbar controls
- All other UI components

**2. Clean up `app/frontend/src/components/AgentControl.tsx`**:

Remove status polling (lines 71-93):

```typescript
// DELETE:
// Lines 71-93: useEffect that polls status every 5 seconds
// Line 73: const interval = setInterval(() => {
//   if (status?.running) fetchStatus()
// }, 5000)
```

**Keep**:

- Agent control UI (start/stop buttons)
- Single status fetch on component mount
- All other control logic

### Step 4: Search & Destroy Patterns

Run these searches and remove all matches:

**1. File path patterns**:

```powershell
# Search for these patterns in backend:
grep -r "felix.*state\.json" app/backend/
grep -r "felix.*requirements\.json" app/backend/
grep -r "felix.*agents\.json" app/backend/
grep -r '"runs/"' app/backend/routers/

# Manually remove all matches that construct these file paths
```

**2. Polling patterns**:

```powershell
# Search in frontend:
grep -r "setInterval.*fetch" app/frontend/src/
grep -r "setTimeout.*fetch" app/frontend/src/

# Remove all polling intervals for state updates
# EXCEPTION: Keep intervals related to console streaming
```

**3. File watching patterns**:

```powershell
# Search in backend:
grep -r "watchfiles" app/backend/
grep -r "awatch" app/backend/

# Remove all filesystem watching imports and usage
```

**4. Unused imports after cleanup**:

```powershell
# Backend - check for orphaned imports:
# - watchfiles, awatch
# - Path operations for state.json/requirements.json

# Frontend - check for orphaned imports:
# - useProjectWebSocket hook references
```

### Step 5: Update Tests

**1. Update `app/backend/tests/test_routes.py`**:

```powershell
# Remove:
# - Lines 6, 36-75: agents.json file operation tests
# - Lines 176-444: File-based agent registry tests
```

**2. Update `app/frontend/src/__tests__/Main.test.tsx`** (if exists):

```typescript
// Remove:
// Lines 224-925: Polling mechanism tests (if present)
```

### Step 6: Verification Checklist

Run these checks to ensure clean removal:

```powershell
# 1. Search for file-based state patterns
grep -r "state\.json" app/backend/ app/frontend/src/
# Expected: 0 results

# 2. Search for requirements.json direct access
grep -r "requirements\.json" app/backend/ app/frontend/src/
# Expected: 0 results (CLI usage is OK)

# 3. Search for agents.json
grep -r "agents\.json" app/backend/ app/frontend/src/
# Expected: 0 results

# 4. Search for polling intervals
grep -r "setInterval" app/frontend/src/
# Expected: Only console streaming, no state polling

# 5. Search for file watching
grep -r "watchfiles" app/backend/
# Expected: 0 results

# 6. Verify console streaming PRESERVED
grep -n "console.*websocket" app/backend/routers/agents.py
# Expected: Lines 791-1002 present (console streaming endpoint)

# 7. Verify console panel PRESERVED
grep -n "LiveConsolePanel" app/frontend/src/Main.tsx
# Expected: Lines 777-1219 present (console panel component)

# 8. Check for runs/ directory references
grep -r 'runs/' app/backend/routers/
# Expected: Only in artifact serving, not scanning
```

### Step 7: Test Backend Still Runs

```powershell
cd app\backend
python main.py

# Should start without errors
# Note: Some endpoints will return 404 (expected - removed features)
# Console streaming endpoint should still work

# Test health endpoint
curl http://localhost:8080/health
# Expected: {"status":"healthy"}

# Test console streaming still exists
curl http://localhost:8080/api/agents/test-agent/console
# Expected: WebSocket upgrade (or 404 if no agent running)
```

### Step 8: Test Frontend Still Builds

```powershell
cd app\frontend
npm run build

# Should build successfully
# Note: Some components will show warnings (expected - removed features)
# Console panel should still be present in build
```

### Step 9: Commit Cleanup

```powershell
# Stage all changes
git add -A

# Review changes before committing
git status
git diff --staged

# Commit with descriptive message
git commit -m "Phase -1: Remove legacy file-based state management

- Delete websocket.py (file watching infrastructure, 537 lines)
- Delete useProjectWebSocket.ts (state WebSocket hook)
- Remove polling from Main.tsx and AgentControl.tsx (~260 lines)
- Remove file operations from agents.py, agent_config.py, routes.py (~400 lines)
- Remove state.json/requirements.json/agents.json direct access
- Remove runs/ directory scanning logic
- PRESERVE: Console streaming WebSocket (agents.py:791-1002)
- PRESERVE: LiveConsolePanel UI (Main.tsx:777-1219)

Prepares codebase for cloud migration with clean slate.
Total: ~1,700 lines removed, critical console features preserved."

# Create backup branch before continuing
git branch backup/pre-cloud-migration
git tag phase-minus-1-complete

# Verify backup created
git branch --list backup/*
```

### Step 10: Documentation Update

Update README or comments to reflect removed features:

```markdown
# Removed in Phase -1 (Cloud Migration Prep):

- ❌ File-based state management (state.json, requirements.json, agents.json)
- ❌ Filesystem watching for state updates
- ❌ Frontend polling for agent/requirement updates
- ❌ Runs directory scanning for history

# Preserved Features:

- ✅ Console streaming WebSocket (real-time logs)
- ✅ Console panel UI component
- ✅ Agent control endpoints (start/stop)
- ✅ Spec file operations (still filesystem-based)
```

### Phase -1 Success Criteria

**Must Pass All**:

- ✅ No references to felix/state.json in backend/frontend
- ✅ No references to felix/requirements.json in backend/frontend (except CLI)
- ✅ No references to felix/agents.json in backend/frontend
- ✅ No polling intervals for state updates in frontend
- ✅ No filesystem watching (watchfiles) in backend
- ✅ Console streaming WebSocket preserved (agents.py lines 791-1002)
- ✅ LiveConsolePanel UI preserved (Main.tsx lines 777-1219)
- ✅ Backend starts without import/syntax errors
- ✅ Frontend builds successfully
- ✅ All changes committed to git with descriptive message
- ✅ Backup branch created (backup/pre-cloud-migration)
- ✅ Git tag created (phase-minus-1-complete)

**Estimated Time**: 4-6 hours

**Next Step**: Proceed to Phase 0 with clean codebase - no file-based state, no polling, only database operations.

---

## Phase 0: Local Postgres Setup (2-3 days)

**Goal**: Replace file-based storage with local Postgres, prove orchestration works, skip cloud complexity.

### Day 1: Database Setup

**1. Create Felix database**:

```powershell
# Connect to your existing Postgres installation
psql -U postgres

# In psql:
CREATE DATABASE felix;
\c felix

# Verify connection
\dt
\q
```

**2. Create migrations directory**:

```powershell
cd c:\dev\Felix
mkdir app\backend\migrations
```

**3. Create initial migration file** (`app/backend/migrations/001_initial_schema.sql`):

```sql
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Organizations table (seed with dev org)
CREATE TABLE organizations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  is_personal BOOLEAN DEFAULT FALSE,
  plan TEXT NOT NULL DEFAULT 'free',
  agent_limit INTEGER DEFAULT 1,
  storage_limit_gb INTEGER DEFAULT 5,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Projects table
CREATE TABLE projects (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  slug TEXT NOT NULL,
  description TEXT,
  root_path TEXT NOT NULL,
  config JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID,
  UNIQUE(organization_id, slug)
);

CREATE INDEX idx_projects_org ON projects(organization_id);

-- Agents table
CREATE TABLE agents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  agent_id TEXT NOT NULL,
  agent_type TEXT NOT NULL DEFAULT 'local',
  display_name TEXT,
  status TEXT NOT NULL DEFAULT 'idle',
  mode TEXT,
  current_requirement_id TEXT,
  registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_heartbeat TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at TIMESTAMPTZ,
  stopped_at TIMESTAMPTZ,
  version TEXT,
  host TEXT,
  environment JSONB,
  UNIQUE(project_id, agent_id)
);

CREATE INDEX idx_agents_project ON agents(project_id);
CREATE INDEX idx_agents_status ON agents(status);
CREATE INDEX idx_agents_heartbeat ON agents(last_heartbeat);

-- Agent states table (historical tracking)
CREATE TABLE agent_states (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  agent_id UUID NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  status TEXT NOT NULL,
  mode TEXT,
  current_requirement_id TEXT,
  iteration_count INTEGER DEFAULT 0,
  backpressure_count INTEGER DEFAULT 0,
  error_message TEXT,
  error_type TEXT,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  duration_ms INTEGER,
  metadata JSONB
);

CREATE INDEX idx_agent_states_agent ON agent_states(agent_id, timestamp DESC);
CREATE INDEX idx_agent_states_project ON agent_states(project_id, timestamp DESC);

-- Runs table
CREATE TABLE runs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  agent_id UUID REFERENCES agents(id) ON DELETE SET NULL,
  run_id TEXT NOT NULL,
  requirement_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'running',
  mode TEXT NOT NULL,
  iteration_count INTEGER DEFAULT 0,
  backpressure_count INTEGER DEFAULT 0,
  validation_failures INTEGER DEFAULT 0,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  duration_ms INTEGER,
  exit_code INTEGER,
  error_message TEXT,
  metadata JSONB,
  UNIQUE(project_id, run_id)
);

CREATE INDEX idx_runs_project ON runs(project_id, started_at DESC);
CREATE INDEX idx_runs_requirement ON runs(requirement_id);
CREATE INDEX idx_runs_agent ON runs(agent_id);
CREATE INDEX idx_runs_status ON runs(status);

-- Run artifacts table
CREATE TABLE run_artifacts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  artifact_type TEXT NOT NULL,
  file_name TEXT NOT NULL,
  file_path TEXT NOT NULL,
  storage_path TEXT,
  storage_bucket TEXT DEFAULT 'run-artifacts',
  content_type TEXT,
  size_bytes BIGINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  metadata JSONB
);

CREATE INDEX idx_artifacts_run ON run_artifacts(run_id, created_at DESC);
CREATE INDEX idx_artifacts_project ON run_artifacts(project_id, created_at DESC);
CREATE INDEX idx_artifacts_type ON run_artifacts(artifact_type);

-- Requirements table
CREATE TABLE requirements (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  requirement_id TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'planned',
  priority INTEGER DEFAULT 0,
  depends_on TEXT[],
  blocks TEXT[],
  acceptance_criteria JSONB,
  validation_status TEXT,
  last_validated_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  tags TEXT[],
  metadata JSONB,
  UNIQUE(project_id, requirement_id)
);

CREATE INDEX idx_requirements_project ON requirements(project_id, priority DESC);
CREATE INDEX idx_requirements_status ON requirements(status);
CREATE INDEX idx_requirements_tags ON requirements USING GIN(tags);

-- Seed dev organization and project
INSERT INTO organizations (id, name, slug, is_personal, plan)
VALUES (
  'dev-org-001'::uuid,
  'Development Workspace',
  'dev-workspace',
  true,
  'free'
);

INSERT INTO projects (id, organization_id, name, slug, root_path, created_by)
VALUES (
  'dev-project-001'::uuid,
  'dev-org-001'::uuid,
  'Felix Development',
  'felix-dev',
  'C:\dev\Felix',
  'dev-user-001'::uuid
);
```

**4. Apply migration**:

```powershell
psql -U postgres -d felix -f app\backend\migrations\001_initial_schema.sql

# Verify tables created
psql -U postgres -d felix -c "\dt"
```

**5. Test queries**:

```powershell
# Connect to database
psql -U postgres -d felix

# Verify seed data
SELECT * FROM organizations;
SELECT * FROM projects;

# Exit
\q
```

### Day 2: Backend Database Integration

**1. Install dependencies**:

```powershell
cd app\backend
.\.venv\Scripts\Activate.ps1

pip install asyncpg sqlalchemy[asyncio] python-dotenv
pip freeze > requirements.txt
```

**2. Create database configuration** (`app/backend/config.py`):

```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Database
    DATABASE_URL: str = "postgresql://postgres:postgres@localhost:5432/felix"

    # Auth mode (disabled for Phase 0)
    AUTH_MODE: str = "disabled"

    # Dev identity (Phase 0 only)
    DEV_USER_ID: str = "dev-user-001"
    DEV_ORG_ID: str = "dev-org-001"
    DEV_PROJECT_ID: str = "dev-project-001"

    class Config:
        env_file = ".env"

settings = Settings()
```

**3. Create database client** (`app/backend/database/db.py`):

```python
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.backend.config import settings

# Create async engine
engine = create_async_engine(
    settings.DATABASE_URL.replace('postgresql://', 'postgresql+asyncpg://'),
    echo=True,  # Set to False in production
    pool_pre_ping=True
)

# Create session factory
AsyncSessionLocal = sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False
)

async def get_db():
    """Dependency for FastAPI routes"""
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()

async def init_db():
    """Initialize database connection (call on startup)"""
    async with engine.begin() as conn:
        # Test connection
        await conn.execute("SELECT 1")
```

**4. Create dev identity middleware** (`app/backend/auth.py`):

```python
from fastapi import Request
from app.backend.config import settings

class DevIdentity:
    """Phase 0: Dev mode identity - no real auth"""

    def __init__(self):
        self.user_id = settings.DEV_USER_ID
        self.org_id = settings.DEV_ORG_ID
        self.project_id = settings.DEV_PROJECT_ID

async def get_current_user(request: Request = None) -> str:
    """Get current user ID (dev mode returns fixed ID)"""
    if settings.AUTH_MODE == "disabled":
        return settings.DEV_USER_ID
    # TODO: Phase 2 - implement JWT validation
    raise NotImplementedError("Auth not implemented yet")

async def get_current_org(request: Request = None) -> str:
    """Get current organization ID (dev mode returns fixed ID)"""
    if settings.AUTH_MODE == "disabled":
        return settings.DEV_ORG_ID
    # TODO: Phase 2 - implement from JWT claims
    raise NotImplementedError("Auth not implemented yet")
```

**5. Create database writers** (`app/backend/database/writers.py`):

```python
from typing import Dict, Any, Optional
from datetime import datetime
from sqlalchemy.ext.asyncio import AsyncSession

class AgentWriter:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def upsert_agent(
        self,
        project_id: str,
        user_id: str,
        agent_id: str,
        status: str,
        agent_type: str = "local",
        metadata: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Register or update agent"""
        query = """
        INSERT INTO agents (
            project_id, user_id, agent_id, agent_type, status,
            registered_at, last_heartbeat, environment
        ) VALUES (
            :project_id, :user_id, :agent_id, :agent_type, :status,
            :now, :now, :environment
        )
        ON CONFLICT (project_id, agent_id)
        DO UPDATE SET
            status = EXCLUDED.status,
            last_heartbeat = EXCLUDED.last_heartbeat,
            environment = EXCLUDED.environment
        RETURNING *
        """

        result = await self.session.execute(
            query,
            {
                "project_id": project_id,
                "user_id": user_id,
                "agent_id": agent_id,
                "agent_type": agent_type,
                "status": status,
                "now": datetime.utcnow(),
                "environment": metadata or {}
            }
        )

        return dict(result.fetchone()._mapping)

    async def update_heartbeat(self, agent_id: str, project_id: str) -> None:
        """Update agent last_heartbeat timestamp"""
        query = """
        UPDATE agents
        SET last_heartbeat = :now
        WHERE agent_id = :agent_id AND project_id = :project_id
        """

        await self.session.execute(
            query,
            {"agent_id": agent_id, "project_id": project_id, "now": datetime.utcnow()}
        )

    async def update_status(
        self,
        agent_id: str,
        project_id: str,
        status: str,
        mode: Optional[str] = None,
        current_requirement_id: Optional[str] = None
    ) -> None:
        """Update agent status and current state"""
        query = """
        UPDATE agents
        SET
            status = :status,
            mode = COALESCE(:mode, mode),
            current_requirement_id = COALESCE(:requirement_id, current_requirement_id),
            last_heartbeat = :now
        WHERE agent_id = :agent_id AND project_id = :project_id
        """

        await self.session.execute(
            query,
            {
                "agent_id": agent_id,
                "project_id": project_id,
                "status": status,
                "mode": mode,
                "requirement_id": current_requirement_id,
                "now": datetime.utcnow()
            }
        )

class RunWriter:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def create_run(
        self,
        project_id: str,
        user_id: str,
        run_id: str,
        requirement_id: str,
        mode: str,
        agent_id: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Create new run record"""
        query = """
        INSERT INTO runs (
            project_id, user_id, agent_id, run_id, requirement_id,
            status, mode, started_at, metadata
        ) VALUES (
            :project_id, :user_id, :agent_id, :run_id, :requirement_id,
            'running', :mode, :now, :metadata
        )
        RETURNING *
        """

        result = await self.session.execute(
            query,
            {
                "project_id": project_id,
                "user_id": user_id,
                "agent_id": agent_id,
                "run_id": run_id,
                "requirement_id": requirement_id,
                "mode": mode,
                "now": datetime.utcnow(),
                "metadata": metadata or {}
            }
        )

        return dict(result.fetchone()._mapping)

    async def update_run_status(
        self,
        run_id: str,
        project_id: str,
        status: str,
        exit_code: Optional[int] = None,
        error_message: Optional[str] = None
    ) -> None:
        """Update run status and completion data"""
        completed_at = datetime.utcnow() if status in ["completed", "failed", "blocked"] else None

        query = """
        UPDATE runs
        SET
            status = :status,
            completed_at = COALESCE(:completed_at, completed_at),
            exit_code = COALESCE(:exit_code, exit_code),
            error_message = COALESCE(:error_message, error_message)
        WHERE run_id = :run_id AND project_id = :project_id
        """

        await self.session.execute(
            query,
            {
                "run_id": run_id,
                "project_id": project_id,
                "status": status,
                "completed_at": completed_at,
                "exit_code": exit_code,
                "error_message": error_message
            }
        )

    async def create_artifact(
        self,
        run_id: str,
        project_id: str,
        user_id: str,
        artifact_type: str,
        file_name: str,
        file_path: str,
        metadata: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Create run artifact record"""
        query = """
        INSERT INTO run_artifacts (
            run_id, project_id, user_id, artifact_type,
            file_name, file_path, created_at, metadata
        ) VALUES (
            :run_id, :project_id, :user_id, :artifact_type,
            :file_name, :file_path, :now, :metadata
        )
        RETURNING *
        """

        result = await self.session.execute(
            query,
            {
                "run_id": run_id,
                "project_id": project_id,
                "user_id": user_id,
                "artifact_type": artifact_type,
                "file_name": file_name,
                "file_path": file_path,
                "now": datetime.utcnow(),
                "metadata": metadata or {}
            }
        )

        return dict(result.fetchone()._mapping)
```

**6. Create `.env` file** (`app/backend/.env`):

```bash
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/felix
AUTH_MODE=disabled
DEV_USER_ID=dev-user-001
DEV_ORG_ID=dev-org-001
DEV_PROJECT_ID=dev-project-001
```

**7. Update main.py to initialize database**:

```python
from fastapi import FastAPI
from app.backend.database.db import init_db
from app.backend.config import settings

app = FastAPI()

@app.on_event("startup")
async def startup_event():
    """Initialize database connection on startup"""
    await init_db()
    print("✅ Database connected")

@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "auth_mode": settings.AUTH_MODE,
        "phase": "0"
    }
```

**8. Test database connection**:

```powershell
cd app\backend
python main.py

# In another terminal:
curl http://localhost:8080/health
# Should return: {"status":"healthy","auth_mode":"disabled","phase":"0"}
```

### Day 3: Agent Registration & Heartbeat

**1. Create agent endpoints** (`app/backend/routers/agents.py`):

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional, Dict, Any
from datetime import datetime
from app.backend.database.db import get_db
from app.backend.database.writers import AgentWriter, RunWriter
from app.backend.auth import get_current_user
from app.backend.config import settings

router = APIRouter(prefix="/api/agents", tags=["agents"])

@router.post("/register")
async def register_agent(
    agent_id: str,
    agent_type: str = "local",
    metadata: Optional[Dict[str, Any]] = None,
    user_id: str = Depends(get_current_user),
    session: AsyncSession = Depends(get_db)
):
    """Register agent with backend"""
    writer = AgentWriter(session)

    agent = await writer.upsert_agent(
        project_id=settings.DEV_PROJECT_ID,
        user_id=user_id,
        agent_id=agent_id,
        status="registered",
        agent_type=agent_type,
        metadata=metadata
    )

    return {
        "status": "registered",
        "agent": agent
    }

@router.post("/{agent_id}/heartbeat")
async def agent_heartbeat(
    agent_id: str,
    session: AsyncSession = Depends(get_db)
):
    """Update agent heartbeat timestamp"""
    writer = AgentWriter(session)

    await writer.update_heartbeat(
        agent_id=agent_id,
        project_id=settings.DEV_PROJECT_ID
    )

    return {"status": "ok", "timestamp": datetime.utcnow().isoformat()}

@router.post("/{agent_id}/status")
async def update_agent_status(
    agent_id: str,
    status: str,
    mode: Optional[str] = None,
    current_requirement_id: Optional[str] = None,
    session: AsyncSession = Depends(get_db)
):
    """Update agent status"""
    writer = AgentWriter(session)

    await writer.update_status(
        agent_id=agent_id,
        project_id=settings.DEV_PROJECT_ID,
        status=status,
        mode=mode,
        current_requirement_id=current_requirement_id
    )

    return {"status": "updated"}

@router.get("/")
async def list_agents(
    session: AsyncSession = Depends(get_db)
):
    """List all agents for current project"""
    result = await session.execute(
        "SELECT * FROM agents WHERE project_id = :project_id ORDER BY registered_at DESC",
        {"project_id": settings.DEV_PROJECT_ID}
    )

    agents = [dict(row._mapping) for row in result.fetchall()]
    return {"agents": agents}
```

**2. Register router in main.py**:

```python
from app.backend.routers import agents

app.include_router(agents.router)
```

**3. Test agent registration**:

```powershell
# Register an agent
curl -X POST "http://localhost:8080/api/agents/register?agent_id=test-agent-001&agent_type=local"

# Send heartbeat
curl -X POST "http://localhost:8080/api/agents/test-agent-001/heartbeat"

# List agents
curl http://localhost:8080/api/agents/

# Verify in database
psql -U postgres -d felix -c "SELECT agent_id, status, last_heartbeat FROM agents;"
```

**Phase 0 Success Criteria**:

- ✅ Postgres database created and seeded
- ✅ Backend connects to database
- ✅ Agent registration works
- ✅ Heartbeats update database
- ✅ Can query agents from database

---

## Phase 1: Core Orchestration (3-4 days)

**Goal**: Implement full agent control flow - tray registers, backend sends commands, runs are tracked.

### Day 4: Control WebSocket

**1. Create WebSocket manager** (`app/backend/websocket/control.py`):

```python
from fastapi import WebSocket, WebSocketDisconnect
from typing import Dict
import json

class ControlConnectionManager:
    """Manages control WebSocket connections per agent"""

    def __init__(self):
        self.active_connections: Dict[str, WebSocket] = {}

    async def connect(self, agent_id: str, websocket: WebSocket):
        """Connect agent control WebSocket"""
        await websocket.accept()
        self.active_connections[agent_id] = websocket
        print(f"✅ Control WebSocket connected: {agent_id}")

    def disconnect(self, agent_id: str):
        """Disconnect agent"""
        if agent_id in self.active_connections:
            del self.active_connections[agent_id]
            print(f"❌ Control WebSocket disconnected: {agent_id}")

    async def send_command(self, agent_id: str, command: dict):
        """Send command to specific agent"""
        if agent_id in self.active_connections:
            try:
                await self.active_connections[agent_id].send_json(command)
                return True
            except Exception as e:
                print(f"❌ Failed to send command to {agent_id}: {e}")
                self.disconnect(agent_id)
                return False
        return False

    def is_connected(self, agent_id: str) -> bool:
        """Check if agent is connected"""
        return agent_id in self.active_connections

control_manager = ControlConnectionManager()
```

**2. Add control WebSocket endpoint to agents router**:

```python
from fastapi import WebSocket, WebSocketDisconnect
from app.backend.websocket.control import control_manager

@router.websocket("/{agent_id}/control")
async def agent_control_websocket(
    websocket: WebSocket,
    agent_id: str
):
    """Control WebSocket for agent commands"""
    await control_manager.connect(agent_id, websocket)

    try:
        while True:
            # Keep connection alive and receive status updates
            data = await websocket.receive_json()

            # Agent can send status updates through control WS
            if data.get("type") == "status":
                print(f"Agent {agent_id} status: {data}")
                # Could update database here

    except WebSocketDisconnect:
        control_manager.disconnect(agent_id)
    except Exception as e:
        print(f"Control WebSocket error: {e}")
        control_manager.disconnect(agent_id)
```

**3. Add run control endpoints**:

```python
@router.post("/runs")
async def create_run(
    requirement_id: str,
    mode: str = "auto",
    user_id: str = Depends(get_current_user),
    session: AsyncSession = Depends(get_db)
):
    """Create new run and assign to available agent"""
    # Find available agent
    result = await session.execute(
        "SELECT agent_id FROM agents WHERE project_id = :project_id AND status = 'idle' LIMIT 1",
        {"project_id": settings.DEV_PROJECT_ID}
    )
    agent_row = result.fetchone()

    if not agent_row:
        raise HTTPException(503, "No agents available")

    agent_id = agent_row[0]

    # Create run
    writer = RunWriter(session)
    run_id = datetime.utcnow().strftime("%Y-%m-%dT%H-%M-%S")

    run = await writer.create_run(
        project_id=settings.DEV_PROJECT_ID,
        user_id=user_id,
        run_id=run_id,
        requirement_id=requirement_id,
        mode=mode,
        agent_id=agent_id
    )

    # Send START command to agent
    command = {
        "type": "START",
        "run_id": run_id,
        "requirement_id": requirement_id,
        "mode": mode
    }

    sent = await control_manager.send_command(agent_id, command)

    if not sent:
        raise HTTPException(503, f"Failed to send command to agent {agent_id}")

    return {"run": run, "command_sent": True}

@router.post("/runs/{run_id}/stop")
async def stop_run(
    run_id: str,
    session: AsyncSession = Depends(get_db)
):
    """Stop running run"""
    # Get agent for this run
    result = await session.execute(
        "SELECT agent_id FROM runs WHERE run_id = :run_id",
        {"run_id": run_id}
    )
    row = result.fetchone()

    if not row:
        raise HTTPException(404, "Run not found")

    agent_id = row[0]

    # Send STOP command
    command = {
        "type": "STOP",
        "run_id": run_id
    }

    sent = await control_manager.send_command(agent_id, command)

    return {"command_sent": sent}

@router.get("/runs")
async def list_runs(
    session: AsyncSession = Depends(get_db),
    limit: int = 50
):
    """List recent runs"""
    result = await session.execute(
        """
        SELECT r.*, a.agent_id, a.display_name
        FROM runs r
        LEFT JOIN agents a ON r.agent_id = a.id
        WHERE r.project_id = :project_id
        ORDER BY r.started_at DESC
        LIMIT :limit
        """,
        {"project_id": settings.DEV_PROJECT_ID, "limit": limit}
    )

    runs = [dict(row._mapping) for row in result.fetchall()]
    return {"runs": runs}

@router.get("/runs/{run_id}")
async def get_run(
    run_id: str,
    session: AsyncSession = Depends(get_db)
):
    """Get run details"""
    result = await session.execute(
        "SELECT * FROM runs WHERE run_id = :run_id",
        {"run_id": run_id}
    )

    row = result.fetchone()
    if not row:
        raise HTTPException(404, "Run not found")

    return {"run": dict(row._mapping)}
```

**4. Test control flow**:

```powershell
# Terminal 1: Start backend
cd app\backend
python main.py

# Terminal 2: Simulate agent control connection (using wscat)
npm install -g wscat
wscat -c ws://localhost:8080/api/agents/test-agent-001/control

# Terminal 3: Create a run
curl -X POST "http://localhost:8080/api/agents/runs?requirement_id=S-0001&mode=auto"

# Terminal 2 should receive:
# {"type":"START","run_id":"2026-02-01T14-30-00","requirement_id":"S-0001","mode":"auto"}
```

### Day 5-6: Console Streaming WebSocket

**1. Add console streaming endpoint** (`app/backend/routers/agents.py`):

```python
import asyncio
import os
from pathlib import Path

@router.websocket("/{agent_id}/console")
async def agent_console_stream(
    websocket: WebSocket,
    agent_id: str,
    run_id: Optional[str] = None
):
    """Stream console output from agent's run"""
    await websocket.accept()

    # If no run_id, find latest run for this agent
    if not run_id:
        # Query database for latest run
        pass

    # Tail output.log file
    log_path = Path(f"runs/{run_id}/output.log")

    if not log_path.exists():
        await websocket.send_json({
            "type": "error",
            "message": f"Log file not found: {log_path}"
        })
        await websocket.close()
        return

    try:
        last_position = 0

        while True:
            # Read new content
            if log_path.exists():
                with open(log_path, 'r') as f:
                    f.seek(last_position)
                    new_content = f.read()
                    last_position = f.tell()

                    if new_content:
                        await websocket.send_json({
                            "type": "output",
                            "content": new_content
                        })

            # Wait before next check
            await asyncio.sleep(0.5)

    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"Console streaming error: {e}")
```

### Day 7: Frontend Integration

**1. Create API client** (`app/frontend/src/api/client.ts`):

```typescript
const API_URL = "http://localhost:8080/api";

export async function registerAgent(agentId: string, metadata?: any) {
  const response = await fetch(
    `${API_URL}/agents/register?agent_id=${agentId}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
    },
  );
  return response.json();
}

export async function listAgents() {
  const response = await fetch(`${API_URL}/agents/`);
  return response.json();
}

export async function createRun(requirementId: string, mode: string = "auto") {
  const response = await fetch(
    `${API_URL}/agents/runs?requirement_id=${requirementId}&mode=${mode}`,
    {
      method: "POST",
    },
  );
  return response.json();
}

export async function listRuns() {
  const response = await fetch(`${API_URL}/agents/runs`);
  return response.json();
}
```

**2. Create agent dashboard component** (`app/frontend/src/components/AgentDashboard.tsx`):

```typescript
import { useEffect, useState } from 'react';
import { listAgents, listRuns } from '../api/client';

export function AgentDashboard() {
  const [agents, setAgents] = useState([]);
  const [runs, setRuns] = useState([]);

  useEffect(() => {
    // Poll for updates (Phase 0 - no realtime yet)
    const interval = setInterval(async () => {
      const agentsData = await listAgents();
      const runsData = await listRuns();

      setAgents(agentsData.agents);
      setRuns(runsData.runs);
    }, 2000);

    return () => clearInterval(interval);
  }, []);

  return (
    <div>
      <h1>Felix Dashboard (Phase 1)</h1>

      <section>
        <h2>Agents ({agents.length})</h2>
        {agents.map(agent => (
          <div key={agent.agent_id}>
            <strong>{agent.agent_id}</strong>: {agent.status}
            <small> (heartbeat: {new Date(agent.last_heartbeat).toLocaleTimeString()})</small>
          </div>
        ))}
      </section>

      <section>
        <h2>Recent Runs</h2>
        {runs.map(run => (
          <div key={run.run_id}>
            <strong>{run.requirement_id}</strong> - {run.status}
            <small> ({run.mode} mode)</small>
          </div>
        ))}
      </section>
    </div>
  );
}
```

**Phase 1 Success Criteria**:

- ✅ Tray can register agent via API
- ✅ Tray opens control WebSocket
- ✅ Backend can send START/STOP commands
- ✅ Runs are created in database
- ✅ Console streaming works
- ✅ Frontend shows agents and runs

---

## Phase 2: Supabase Migration (3-4 days)

**Goal**: Move from local Postgres to Supabase, add auth and RLS.

### Day 8: Supabase Setup

**1. Create Supabase project**:

- Go to https://supabase.com
- Create new project: "felix-production"
- Wait for provisioning (~2 minutes)
- Note down:
  - Project URL: `https://xxxxx.supabase.co`
  - Anon key
  - Service role key
  - Database password

**2. Apply migrations to Supabase**:

```powershell
# Connect to Supabase Postgres
psql "postgresql://postgres:[YOUR-DB-PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres"

# In psql, run migration
\i app/backend/migrations/001_initial_schema.sql

# Verify
\dt

\q
```

**3. Update backend configuration** (`app/backend/.env`):

```bash
# Supabase
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGc...
SUPABASE_SERVICE_KEY=eyJhbGc...

# Database (use Supabase Postgres)
DATABASE_URL=postgresql://postgres:[YOUR-DB-PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres

# Auth (still disabled for testing migration)
AUTH_MODE=disabled
DEV_USER_ID=dev-user-001
DEV_ORG_ID=dev-org-001
DEV_PROJECT_ID=dev-project-001
```

**4. Update config.py**:

```python
class Settings(BaseSettings):
    # Supabase
    SUPABASE_URL: str
    SUPABASE_ANON_KEY: str
    SUPABASE_SERVICE_KEY: str

    # Database
    DATABASE_URL: str

    # Auth
    AUTH_MODE: str = "disabled"
    DEV_USER_ID: str = "dev-user-001"
    DEV_ORG_ID: str = "dev-org-001"
    DEV_PROJECT_ID: str = "dev-project-001"
```

**5. Test connection**:

```powershell
cd app\backend
python main.py

# Should connect to Supabase Postgres now
curl http://localhost:8080/health

# Test agent registration still works
curl -X POST "http://localhost:8080/api/agents/register?agent_id=supabase-test-001"
```

### Day 9-10: Enable Auth + RLS

**1. Create RLS policies migration** (`app/backend/migrations/002_enable_rls.sql`):

```sql
-- Helper function to check organization membership
CREATE OR REPLACE FUNCTION is_org_member(org_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM organization_members
    WHERE organization_id = org_id
    AND user_id = auth.uid()
  );
$$ LANGUAGE sql SECURITY DEFINER;

-- Helper function to check organization role
CREATE OR REPLACE FUNCTION has_org_role(org_id UUID, required_role TEXT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM organization_members
    WHERE organization_id = org_id
    AND user_id = auth.uid()
    AND (
      CASE required_role
        WHEN 'viewer' THEN role IN ('viewer', 'member', 'admin', 'owner')
        WHEN 'member' THEN role IN ('member', 'admin', 'owner')
        WHEN 'admin' THEN role IN ('admin', 'owner')
        WHEN 'owner' THEN role = 'owner'
      END
    )
  );
$$ LANGUAGE sql SECURITY DEFINER;

-- Enable RLS on all tables
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_states ENABLE ROW LEVEL SECURITY;
ALTER TABLE runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE run_artifacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE requirements ENABLE ROW LEVEL SECURITY;

-- Organizations policies
CREATE POLICY "Users can view organizations they belong to"
  ON organizations FOR SELECT
  USING (is_org_member(id));

CREATE POLICY "Only owners can update organizations"
  ON organizations FOR UPDATE
  USING (has_org_role(id, 'owner'));

-- Projects policies
CREATE POLICY "Users can view projects in their organizations"
  ON projects FOR SELECT
  USING (is_org_member(organization_id));

CREATE POLICY "Members can create projects"
  ON projects FOR INSERT
  WITH CHECK (has_org_role(organization_id, 'member'));

-- Agents policies
CREATE POLICY "Users can view agents in their organization's projects"
  ON agents FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = agents.project_id
      AND is_org_member(projects.organization_id)
    )
  );

CREATE POLICY "Users can insert agents in their organization's projects"
  ON agents FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = project_id
      AND is_org_member(projects.organization_id)
    )
  );

CREATE POLICY "Users can update agents in their organization's projects"
  ON agents FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = agents.project_id
      AND is_org_member(projects.organization_id)
    )
  );

-- Runs policies
CREATE POLICY "Users can view runs in their organization's projects"
  ON runs FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = runs.project_id
      AND is_org_member(projects.organization_id)
    )
  );

CREATE POLICY "Users can insert runs in their organization's projects"
  ON runs FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = project_id
      AND is_org_member(projects.organization_id)
    )
  );

-- Similar policies for agent_states, run_artifacts, requirements...
-- (Copy full RLS section from CLOUD_MIGRATION.md)
```

**2. Apply RLS migration**:

```powershell
psql "postgresql://postgres:[PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres" -f app\backend\migrations\002_enable_rls.sql
```

**3. Create organization members table and seed data**:

```sql
-- In Supabase SQL Editor
CREATE TABLE organization_members (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'member',
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  invited_by UUID REFERENCES auth.users(id),
  UNIQUE(organization_id, user_id)
);

-- Seed dev user membership
INSERT INTO organization_members (organization_id, user_id, role)
VALUES ('dev-org-001'::uuid, 'dev-user-001'::uuid, 'owner');
```

**4. Update auth.py for JWT validation**:

```python
from fastapi import Request, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError
from app.backend.config import settings

security = HTTPBearer()

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> str:
    """Get current user ID from JWT token"""
    if settings.AUTH_MODE == "disabled":
        return settings.DEV_USER_ID

    token = credentials.credentials

    try:
        # Decode JWT - Supabase uses the anon key as secret
        payload = jwt.decode(
            token,
            settings.SUPABASE_JWT_SECRET,  # Get from Supabase settings
            algorithms=["HS256"],
            options={"verify_aud": False}
        )

        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(401, "Invalid token: no user ID")

        return user_id

    except JWTError as e:
        raise HTTPException(401, f"Invalid token: {e}")
```

**5. Install JWT library**:

```powershell
pip install python-jose[cryptography]
pip freeze > requirements.txt
```

**6. Enable auth**:

```bash
# In .env
AUTH_MODE=enabled
```

**7. Test with Supabase Auth**:

```typescript
// Frontend: Sign up test user
import { createClient } from "@supabase/supabase-js";

const supabase = createClient("https://xxxxx.supabase.co", "your-anon-key");

const { data, error } = await supabase.auth.signUp({
  email: "test@felix.dev",
  password: "testpass123",
});

// Get session token
const {
  data: { session },
} = await supabase.auth.getSession();

// Use in API calls
fetch("/api/agents/", {
  headers: {
    Authorization: `Bearer ${session.access_token}`,
  },
});
```

### Day 11: Personal Organization Auto-Creation

**1. Create trigger migration** (`app/backend/migrations/003_personal_org_trigger.sql`):

```sql
-- Trigger function to create personal organization on user signup
CREATE OR REPLACE FUNCTION create_personal_organization()
RETURNS TRIGGER AS $$
DECLARE
  new_org_id UUID;
BEGIN
  -- Create personal organization
  INSERT INTO organizations (name, slug, is_personal, plan)
  VALUES (
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)) || '''s Workspace',
    'personal-' || NEW.id,
    TRUE,
    'free'
  )
  RETURNING id INTO new_org_id;

  -- Make user the owner
  INSERT INTO organization_members (organization_id, user_id, role)
  VALUES (new_org_id, NEW.id, 'owner');

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on auth.users table
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION create_personal_organization();
```

**2. Apply trigger migration**:

```powershell
psql "postgresql://postgres:[PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres" -f app\backend\migrations\003_personal_org_trigger.sql
```

**3. Test personal org creation**:

```typescript
// Sign up new user
const { data, error } = await supabase.auth.signUp({
  email: "newuser@felix.dev",
  password: "password123",
});

// Check personal org was created
const { data: orgs } = await supabase
  .from("organizations")
  .select("*")
  .eq("is_personal", true);

console.log("Personal org:", orgs[0]);
// Should show: { name: "newuser's Workspace", slug: "personal-xxxxx", is_personal: true }
```

**Phase 2 Success Criteria**:

- ✅ Connected to Supabase Postgres
- ✅ Auth enabled with JWT validation
- ✅ RLS policies enforced
- ✅ Personal organization auto-created on signup
- ✅ Multi-user isolation working
- ✅ Test with 2+ users - data properly isolated

---

## Phase 3: Realtime Subscriptions (3-4 days)

**Goal**: Replace polling with Supabase Realtime subscriptions.

### Day 12-13: Frontend Realtime Hooks

**1. Install Supabase client**:

```powershell
cd app\frontend
npm install @supabase/supabase-js
```

**2. Create Supabase client** (`app/frontend/src/lib/supabase.ts`):

```typescript
import { createClient } from "@supabase/supabase-js";

export const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY,
);
```

**3. Create Realtime hook** (`app/frontend/src/hooks/useSupabaseRealtime.ts`):

```typescript
import { useEffect, useState } from "react";
import { RealtimeChannel } from "@supabase/supabase-js";
import { supabase } from "../lib/supabase";

interface UseSupabaseRealtimeOptions {
  projectId: string;
  table: "agents" | "runs" | "requirements";
  onInsert?: (record: any) => void;
  onUpdate?: (record: any) => void;
  onDelete?: (record: any) => void;
}

export function useSupabaseRealtime({
  projectId,
  table,
  onInsert,
  onUpdate,
  onDelete,
}: UseSupabaseRealtimeOptions) {
  const [channel, setChannel] = useState<RealtimeChannel | null>(null);
  const [status, setStatus] = useState<
    "connecting" | "connected" | "disconnected"
  >("connecting");

  useEffect(() => {
    const realtimeChannel = supabase
      .channel(`${table}:${projectId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: table,
          filter: `project_id=eq.${projectId}`,
        },
        (payload) => {
          console.log(`[${table}] INSERT:`, payload.new);
          onInsert?.(payload.new);
        },
      )
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: table,
          filter: `project_id=eq.${projectId}`,
        },
        (payload) => {
          console.log(`[${table}] UPDATE:`, payload.new);
          onUpdate?.(payload.new);
        },
      )
      .on(
        "postgres_changes",
        {
          event: "DELETE",
          schema: "public",
          table: table,
          filter: `project_id=eq.${projectId}`,
        },
        (payload) => {
          console.log(`[${table}] DELETE:`, payload.old);
          onDelete?.(payload.old);
        },
      )
      .subscribe((status) => {
        console.log(`[${table}] Subscription status:`, status);
        if (status === "SUBSCRIBED") {
          setStatus("connected");
        } else if (status === "CLOSED") {
          setStatus("disconnected");
        }
      });

    setChannel(realtimeChannel);

    return () => {
      realtimeChannel.unsubscribe();
    };
  }, [projectId, table]);

  return { status, channel };
}
```

**4. Create project state hook** (`app/frontend/src/hooks/useProjectState.ts`):

```typescript
import { useState } from "react";
import { useSupabaseRealtime } from "./useSupabaseRealtime";

interface ProjectState {
  agents: any[];
  runs: any[];
  requirements: any[];
}

export function useProjectState(projectId: string) {
  const [state, setState] = useState<ProjectState>({
    agents: [],
    runs: [],
    requirements: [],
  });

  // Subscribe to agents
  const { status: agentStatus } = useSupabaseRealtime({
    projectId,
    table: "agents",
    onInsert: (agent) => {
      setState((prev) => ({
        ...prev,
        agents: [...prev.agents, agent],
      }));
    },
    onUpdate: (agent) => {
      setState((prev) => ({
        ...prev,
        agents: prev.agents.map((a) => (a.id === agent.id ? agent : a)),
      }));
    },
    onDelete: (agent) => {
      setState((prev) => ({
        ...prev,
        agents: prev.agents.filter((a) => a.id !== agent.id),
      }));
    },
  });

  // Subscribe to runs
  const { status: runStatus } = useSupabaseRealtime({
    projectId,
    table: "runs",
    onInsert: (run) => {
      setState((prev) => ({
        ...prev,
        runs: [run, ...prev.runs],
      }));
    },
    onUpdate: (run) => {
      setState((prev) => ({
        ...prev,
        runs: prev.runs.map((r) => (r.id === run.id ? run : r)),
      }));
    },
  });

  return {
    state,
    isConnected: agentStatus === "connected" && runStatus === "connected",
  };
}
```

**5. Update AgentDashboard to use Realtime**:

```typescript
import { useProjectState } from '../hooks/useProjectState';

export function AgentDashboard({ projectId }: { projectId: string }) {
  const { state, isConnected } = useProjectState(projectId);

  // Remove polling - now using Realtime

  return (
    <div>
      <h1>Felix Dashboard (Realtime)</h1>
      <div className="status">
        {isConnected ? '🟢 Connected' : '🔴 Disconnected'}
      </div>

      <section>
        <h2>Agents ({state.agents.length})</h2>
        {state.agents.map(agent => (
          <div key={agent.id}>
            <strong>{agent.agent_id}</strong>: {agent.status}
          </div>
        ))}
      </section>

      <section>
        <h2>Recent Runs ({state.runs.length})</h2>
        {state.runs.map(run => (
          <div key={run.id}>
            <strong>{run.requirement_id}</strong> - {run.status}
          </div>
        ))}
      </section>
    </div>
  );
}
```

### Day 14: Organization Context

**1. Create organization context** (`app/frontend/src/contexts/OrganizationContext.tsx`):

```typescript
import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { supabase } from '../lib/supabase';

interface Organization {
  id: string;
  name: string;
  slug: string;
  is_personal: boolean;
  plan: string;
}

interface OrganizationContextType {
  organizations: Organization[];
  currentOrganization: Organization | null;
  switchOrganization: (orgId: string) => void;
  loading: boolean;
}

const OrganizationContext = createContext<OrganizationContextType | null>(null);

export function OrganizationProvider({ children }: { children: ReactNode }) {
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [currentOrganization, setCurrentOrganization] = useState<Organization | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadOrganizations();
  }, []);

  async function loadOrganizations() {
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
      setLoading(false);
      return;
    }

    const { data, error } = await supabase
      .from('organization_members')
      .select('*, organizations(*)')
      .eq('user_id', user.id);

    if (!error && data) {
      const orgs = data.map(m => m.organizations);
      setOrganizations(orgs);

      // Default to personal org or first org
      const personal = orgs.find(o => o.is_personal);
      const savedOrgId = localStorage.getItem('currentOrganizationId');
      const savedOrg = savedOrgId ? orgs.find(o => o.id === savedOrgId) : null;

      setCurrentOrganization(savedOrg || personal || orgs[0]);
    }

    setLoading(false);
  }

  function switchOrganization(orgId: string) {
    const org = organizations.find(o => o.id === orgId);
    if (org) {
      setCurrentOrganization(org);
      localStorage.setItem('currentOrganizationId', orgId);
    }
  }

  return (
    <OrganizationContext.Provider value={{
      organizations,
      currentOrganization,
      switchOrganization,
      loading
    }}>
      {children}
    </OrganizationContext.Provider>
  );
}

export function useOrganization() {
  const context = useContext(OrganizationContext);
  if (!context) {
    throw new Error('useOrganization must be used within OrganizationProvider');
  }
  return context;
}
```

**2. Add organization switcher** (`app/frontend/src/components/OrganizationSwitcher.tsx`):

```typescript
import { useOrganization } from '../contexts/OrganizationContext';

export function OrganizationSwitcher() {
  const { organizations, currentOrganization, switchOrganization } = useOrganization();

  if (organizations.length <= 1) {
    return null; // Don't show if only one org
  }

  return (
    <select
      value={currentOrganization?.id}
      onChange={(e) => switchOrganization(e.target.value)}
      className="org-switcher"
    >
      {organizations.map(org => (
        <option key={org.id} value={org.id}>
          {org.is_personal ? '👤 ' : '👥 '}
          {org.name}
        </option>
      ))}
    </select>
  );
}
```

**3. Wire up in App**:

```typescript
import { OrganizationProvider } from './contexts/OrganizationContext';
import { OrganizationSwitcher } from './components/OrganizationSwitcher';
import { AgentDashboard } from './components/AgentDashboard';

function App() {
  return (
    <OrganizationProvider>
      <div className="app">
        <header>
          <h1>Felix</h1>
          <OrganizationSwitcher />
        </header>
        <AgentDashboard projectId="dev-project-001" />
      </div>
    </OrganizationProvider>
  );
}
```

**Phase 3 Success Criteria**:

- ✅ No polling - all updates via Realtime
- ✅ Multiple users see same updates instantly
- ✅ Organization switching works
- ✅ Console streaming still uses WebSocket
- ✅ Sub-500ms update latency
- ✅ Open 2 browsers, verify realtime sync

---

## Phase 4: Production Hardening (3-4 days)

**Goal**: Deploy to production, migrate data, add monitoring.

### Day 15: Data Migration

**1. Create migration script** (`scripts/migrate_file_data.py`):

```python
#!/usr/bin/env python3
"""Migrate existing file-based data to Supabase"""

import asyncio
import json
from pathlib import Path
from datetime import datetime
from app.backend.database.db import AsyncSessionLocal
from app.backend.database.writers import RunWriter
from app.backend.config import settings

async def migrate_runs():
    """Migrate runs/ directory to database"""
    runs_dir = Path("runs")

    if not runs_dir.exists():
        print("No runs directory found")
        return

    async with AsyncSessionLocal() as session:
        writer = RunWriter(session)
        migrated = 0

        for run_dir in runs_dir.iterdir():
            if not run_dir.is_dir():
                continue

            run_id = run_dir.name

            # Read state.json
            state_file = run_dir / "state.json"
            if not state_file.exists():
                print(f"⚠️  Skipping {run_id} - no state.json")
                continue

            try:
                state = json.loads(state_file.read_text())

                # Create run in database
                await writer.create_run(
                    project_id=settings.DEV_PROJECT_ID,
                    user_id=settings.DEV_USER_ID,
                    run_id=run_id,
                    requirement_id=state.get("requirement_id", "unknown"),
                    mode=state.get("mode", "auto"),
                    metadata=state
                )

                migrated += 1
                print(f"✅ Migrated: {run_id}")

            except Exception as e:
                print(f"❌ Failed to migrate {run_id}: {e}")

        await session.commit()
        print(f"\n✅ Migration complete: {migrated} runs migrated")

if __name__ == "__main__":
    asyncio.run(migrate_runs())
```

**2. Run migration**:

```powershell
cd c:\dev\Felix
python scripts\migrate_file_data.py
```

**3. Verify migration**:

```powershell
psql "postgresql://postgres:[PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres" -c "SELECT COUNT(*) FROM runs;"
```

### Day 16: Monitoring & Logging

**1. Add structured logging** (`app/backend/logging_config.py`):

```python
import logging
import sys

def setup_logging():
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.StreamHandler(sys.stdout)
        ]
    )

logger = logging.getLogger("felix")
```

**2. Add health checks with database connectivity**:

```python
from sqlalchemy import text

@app.get("/health")
async def health(session: AsyncSession = Depends(get_db)):
    """Health check with database connectivity"""
    try:
        await session.execute(text("SELECT 1"))

        return {
            "status": "healthy",
            "database": "connected",
            "auth_mode": settings.AUTH_MODE,
            "phase": "4-production"
        }
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return {
            "status": "unhealthy",
            "database": "disconnected",
            "error": str(e)
        }
```

**3. Add metrics endpoint**:

```python
@router.get("/metrics")
async def metrics(session: AsyncSession = Depends(get_db)):
    """System metrics"""
    # Count agents
    agent_result = await session.execute(
        "SELECT COUNT(*) FROM agents WHERE project_id = :project_id",
        {"project_id": settings.DEV_PROJECT_ID}
    )
    agent_count = agent_result.scalar()

    # Count active runs
    run_result = await session.execute(
        "SELECT COUNT(*) FROM runs WHERE project_id = :project_id AND status = 'running'",
        {"project_id": settings.DEV_PROJECT_ID}
    )
    active_runs = run_result.scalar()

    return {
        "agents": {
            "total": agent_count
        },
        "runs": {
            "active": active_runs
        }
    }
```

### Day 17: Deployment

**1. Create Dockerfile** (`app/backend/Dockerfile`):

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY . .

# Expose port
EXPOSE 8080

# Run application
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
```

**2. Build and test locally**:

```powershell
cd app\backend
docker build -t felix-backend .
docker run -p 8080:8080 --env-file .env felix-backend
```

**3. Deploy to hosting platform** (example: Railway):

```powershell
# Install Railway CLI
npm install -g @railway/cli

# Login
railway login

# Create project
railway init

# Deploy
railway up
```

**4. Deploy frontend to Vercel**:

```powershell
cd app\frontend

# Install Vercel CLI
npm install -g vercel

# Deploy
vercel --prod
```

### Day 18: Testing & Validation

**Testing Checklist**:

```powershell
# 1. Test agent registration
curl -X POST https://api.felix.app/api/agents/register?agent_id=prod-agent-001 `
  -H "Authorization: Bearer YOUR_JWT_TOKEN"

# 2. Test RLS isolation
# - Sign up 2 users in Supabase
# - Create agent as user A
# - Try to list agents as user B
# - Should only see user B's agents

# 3. Test Realtime subscriptions
# - Open dashboard in 2 browser windows (different users)
# - Create agent in one window
# - Verify update appears in other window within 500ms

# 4. Test organization switching
# - Create team organization
# - Invite another user
# - Switch between personal and team org
# - Verify data isolation works

# 5. Load test
# Start 10 concurrent agents
# Monitor:
# - Database connections (should stay < 20)
# - Realtime subscribers (should handle 100+)
# - Response times (p95 < 200ms)

# 6. Failover test
# - Disconnect from Supabase
# - Verify graceful error handling
# - Reconnect and verify recovery
```

**Phase 4 Success Criteria**:

- ✅ All file data migrated to database
- ✅ Backend deployed to production
- ✅ Frontend deployed to production
- ✅ Monitoring and logging active
- ✅ Multi-user isolation verified
- ✅ Load testing passed (10+ concurrent agents)
- ✅ Failover scenarios tested

---

## Rollback Procedures

### Phase 0 Rollback

```powershell
# Drop database
psql -U postgres -c "DROP DATABASE felix;"

# Revert code
git checkout main
```

### Phase 1 Rollback

```powershell
# Keep database, disable new endpoints
# Revert to file-based state reading
git revert HEAD~3..HEAD
```

### Phase 2 Rollback

```powershell
# Point DATABASE_URL back to local Postgres
# Disable auth
# Update .env:
AUTH_MODE=disabled
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/felix
```

### Phase 3 Rollback

```powershell
# Frontend: restore polling code
# Backend: keep database writes
cd app/frontend
git checkout main -- src/hooks/useProjectState.ts
```

### Phase 4 Rollback

```powershell
# Scale down deployments
railway down
vercel rollback
```

---

## Success Metrics

**Phase 0**:

- Backend connects to Postgres: < 100ms
- Agent registration latency: < 50ms
- Database query latency (p95): < 20ms

**Phase 1**:

- Control command delivery: < 100ms
- Run creation latency: < 200ms
- Console streaming latency: < 500ms

**Phase 2**:

- Auth validation latency: < 50ms
- RLS policy overhead: < 10ms
- Signup to personal org: < 2s

**Phase 3**:

- Realtime update latency: < 500ms
- Concurrent subscribers: > 100
- WebSocket connections reduced: > 80%

**Phase 4**:

- Uptime: > 99.9%
- Database connection pool: < 50% utilization
- Zero data loss in migration

---

## Quick Reference Commands

**Database**:

```powershell
# Connect to local
psql -U postgres -d felix

# Connect to Supabase
psql "postgresql://postgres:[PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres"

# Run migration
psql -d felix -f app\backend\migrations\001_initial_schema.sql

# Check tables
\dt

# Check data
SELECT * FROM agents;
```

**Backend**:

```powershell
# Start server
cd app\backend
.\.venv\Scripts\Activate.ps1
python main.py

# Test endpoints
curl http://localhost:8080/health
curl http://localhost:8080/api/agents/
```

**Frontend**:

```powershell
# Start dev server
cd app\frontend
npm run dev

# Build for production
npm run build
```

---

## Next Steps After Completion

1. **Billing Integration**: Add Stripe for paid plans
2. **Storage Migration**: Move artifacts to Supabase Storage
3. **Agent Scaling**: Container-based cloud agents
4. **Advanced Features**:
   - Requirement dependencies
   - Parallel execution
   - Run replay/rollback
5. **Mobile Apps**: Native iOS/Android using Supabase SDKs
