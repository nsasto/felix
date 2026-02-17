# Project-Scoped API Keys & Swarm Management - Implementation Plan

**Version:** 0.3.0 (Breaking Change)  
**Status:** Ready for Implementation  
**Estimated Effort:** 2-3 days (backend + CLI + frontend + testing)  
**Priority:** HIGH - Blocking production swarm management

---

## Executive Summary

Implement project-scoped API keys to enable secure multi-agent swarm management in Felix. This enhancement eliminates the AUTH_MODE development hack, enforces proper authorization boundaries, and enables true multi-project isolation. Each API key authenticates to exactly one project, and the backend derives all project context from the key (not client requests).

**Key Benefits:**

- **Security**: Project-level isolation prevents cross-project data access
- **Simplicity**: API key IS the credential - no configuration duplication
- **Swarm Support**: Multiple agents per project with shared project key
- **Local Development**: CLI works without keys (sync disabled gracefully)
- **Zero Trust**: Backend validates all operations, clients cannot forge project_id

---

## Design Principles

### 1. Local Development Principle

- **Local dev doesn't need API key** - runs work, sync won't
- Maintains "local principle, no dependency" - Felix CLI operates independently
- Graceful degradation: agent runs execute locally, sync operations fail gracefully if no key provided

### 2. Project-Scoped Keys Only

- Every API key must be project-dependent (`project_id NOT NULL`)
- No org-level keys - rejected for security and simplicity
- Each key authenticates to exactly one project

### 3. API Key IS the Project Credential

- Don't store `project_id` in `config.json` - derive from API key lookup
- Simpler mental model: "This key IS my project access"
- Backend resolves project context from key: `API Key → api_keys.project_id → project`
- Single source of truth, no configuration duplication

### 4. Unified Architecture Decisions

- **Auto-register agents** - no manual registration step
- **One project per agent** - multi-project = multiple agents (different API keys)
- **API keys required for backend operations** - eliminate AUTH_MODE=disabled hack
- **Configuration hierarchy**: Environment variables > config.json > no fallback
- **Dual registration endpoints**:
  - UI-based (`/api/agents/register`) - user session auth, explicit project selection
  - CLI-based (`/api/agents/register-with-key`) - API key auth, auto-derived project

---

## Architecture Overview

### Simplified Config Schema

No `project_id` field needed - backend derives it from `api_key` lookup.

```json
{
  "agent": {
    "agent_id": "550e8400-e29b-41d4-a716-446655440000"
  },
  "sync": {
    "enabled": true,
    "provider": "fastapi",
    "base_url": "https://felix.example.com",
    "api_key": "fsk_a1b2c3d4e5f6..."
  }
}
```

### CLI Startup Flow

```mermaid
graph TD
    A[felix-agent.ps1 starts] --> B{sync.enabled?}
    B -->|No| C[Local-only mode]
    B -->|Yes| D{api_key present?}
    D -->|No| E[Error: Run 'felix setup']
    D -->|Yes| F[Validate key via GET /api/keys/validate]
    F -->|401/403| G[Warn: Disable sync, continue local]
    F -->|200| H[Cache project_id from response]
    H --> I[Register agent via POST /api/agents/register-with-key]
    I --> J[Run with sync enabled]
    C --> K[Run without sync]
    G --> K
```

### Backend API Key Lookup

```mermaid
sequenceDiagram
    participant CLI as Felix CLI
    participant API as Backend API
    participant DB as Database

    CLI->>API: POST /api/runs (Bearer fsk_...)
    API->>API: Extract token, hash SHA256
    API->>DB: SELECT project_id FROM api_keys JOIN projects...
    DB-->>API: {project_id, org_id, key_id, name}
    API->>API: Check expiration, update last_used_at
    API->>DB: INSERT run with key's project_id
    DB-->>API: Run created
    API-->>CLI: {run_id, project_id, status}
```

---

## Implementation Plan

### Phase 1: Backend Database Changes

**Estimated Time:** 4 hours

#### Step 1.1: Create Migration `017_project_scoped_api_keys.sql`

**File:** `app/backend/migrations/017_project_scoped_api_keys.sql`

```sql
-- ===================================================================
-- Migration 017: Project-Scoped API Keys
-- ===================================================================
-- Breaking change: Existing API keys are deleted (pre-production status).
-- All keys must now be scoped to a project (project_id NOT NULL).
-- Removes agent_id FK (deprecated in favor of project scoping).

-- Drop existing keys (pre-production, safe to delete)
TRUNCATE api_keys CASCADE;

-- Add project_id as NOT NULL with FK constraint
ALTER TABLE api_keys
  ADD COLUMN project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE;

-- Create index for project_id lookups (used on every auth)
CREATE INDEX idx_api_keys_project_id ON api_keys(project_id);

-- Drop agent_id constraint (deprecated - use project_id)
ALTER TABLE api_keys DROP CONSTRAINT IF EXISTS api_keys_agent_id_fkey;
ALTER TABLE api_keys DROP COLUMN IF EXISTS agent_id;

-- Create composite unique constraint (one key per project+name)
CREATE UNIQUE INDEX idx_api_keys_project_name ON api_keys(project_id, name)
  WHERE name IS NOT NULL;

-- Add comment
COMMENT ON COLUMN api_keys.project_id IS 'Project this key grants access to (NOT NULL - all keys are project-scoped)';
```

**Rollback:**

```sql
-- Undo migration 017
ALTER TABLE api_keys DROP CONSTRAINT IF EXISTS api_keys_project_id_fkey;
DROP INDEX IF EXISTS idx_api_keys_project_id;
DROP INDEX IF EXISTS idx_api_keys_project_name;
ALTER TABLE api_keys DROP COLUMN IF EXISTS project_id;
-- Note: Cannot recover deleted keys - regeneration required
```

#### Step 1.2: Update Database Models

**File:** `app/backend/database.py`

Add/update `ApiKey` model:

```python
class ApiKey(Base):
    __tablename__ = "api_keys"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    key_hash = Column(String, unique=True, nullable=False)
    project_id = Column(UUID(as_uuid=True), ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    name = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    last_used_at = Column(DateTime(timezone=True), nullable=True)
    created_by = Column(String, nullable=True)

    # Relationships
    project = relationship("Project", back_populates="api_keys")
```

Update `Project` model:

```python
class Project(Base):
    __tablename__ = "projects"

    # ... existing columns ...

    # Relationships
    api_keys = relationship("ApiKey", back_populates="project", cascade="all, delete-orphan")
```

**Testing Checkpoint:**

```bash
# Apply migration
psql -U postgres -d felix -f app/backend/migrations/017_project_scoped_api_keys.sql

# Verify schema
psql -U postgres -d felix -c "\d api_keys"
# Expected: project_id column exists (NOT NULL), no agent_id column

# Verify indexes
psql -U postgres -d felix -c "\di idx_api_keys*"
# Expected: idx_api_keys_project_id, idx_api_keys_project_name
```

---

### Phase 2: Backend Authentication

**Estimated Time:** 6 hours

#### Step 2.1: Update `verify_api_key()` Function

**File:** `app/backend/routers/sync.py`

Replace existing `verify_api_key()` with:

```python
from pydantic import BaseModel
from datetime import datetime
import hashlib

class ApiKeyInfo(BaseModel):
    """API key validation result with project context"""
    key_id: str
    project_id: str
    org_id: str
    name: Optional[str] = None

async def verify_api_key(
    authorization: str = Header(None),
    db: Database = Depends(get_db)
) -> ApiKeyInfo:
    """
    Verify API key and return project context.

    API keys are project-scoped (NOT NULL project_id).
    Backend derives project context from key, client cannot override.

    Raises:
        HTTPException 401: Missing or invalid API key
        HTTPException 403: API key expired
    """
    if not authorization:
        raise HTTPException(
            status_code=401,
            detail="Authorization header required (Bearer fsk_...)"
        )

    # Extract token (support "Bearer fsk_..." or raw "fsk_...")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer":
        token = authorization  # Allow plain token without Bearer prefix

    if not token.startswith("fsk_"):
        raise HTTPException(
            status_code=401,
            detail="Invalid API key format (expected fsk_...)"
        )

    # Hash and lookup
    key_hash = hashlib.sha256(token.encode()).hexdigest()

    result = await db.fetch_one(
        """
        SELECT
            ak.id as key_id,
            ak.project_id,
            p.org_id,
            ak.name,
            ak.expires_at
        FROM api_keys ak
        JOIN projects p ON ak.project_id = p.id
        WHERE ak.key_hash = :key_hash
        """,
        {"key_hash": key_hash}
    )

    if not result:
        raise HTTPException(
            status_code=401,
            detail="Invalid API key"
        )

    # Check expiration
    if result["expires_at"] and datetime.now(result["expires_at"].tzinfo) > result["expires_at"]:
        raise HTTPException(
            status_code=403,
            detail="API key expired"
        )

    # Update last_used_at (fire and forget - don't block response)
    asyncio.create_task(
        db.execute(
            "UPDATE api_keys SET last_used_at = NOW() WHERE id = :key_id",
            {"key_id": result["key_id"]}
        )
    )

    return ApiKeyInfo(
        key_id=str(result["key_id"]),
        project_id=str(result["project_id"]),
        org_id=str(result["org_id"]),
        name=result["name"]
    )
```

#### Step 2.2: Add Authorization Helper

**File:** `app/backend/routers/sync.py` (add after `verify_api_key`)

```python
def require_project_access(key_info: ApiKeyInfo, requested_project_id: str):
    """
    Validate API key grants access to requested project.

    Raises:
        HTTPException 403: Project mismatch
    """
    if str(key_info.project_id) != requested_project_id:
        raise HTTPException(
            status_code=403,
            detail=f"API key not authorized for project {requested_project_id}"
        )
```

#### Step 2.3: Agent Registration Endpoints (Dual Architecture)

**File:** `app/backend/routers/agents.py`

Implement two separate endpoints for different use cases:

**A. UI-Based Registration (User Auth)**

For manual agent registration via web UI:

```python
@router.post("/agents/register")
async def register_agent(
    agent: AgentRegistration,
    db: Database = Depends(get_db),
    current_user: User = Depends(get_current_user)  # Session/JWT auth
):
    """
    Register agent manually via UI (user auth).

    User must have permissions for target org/project.
    Allows explicit project_id selection.
    Used for: Remote agent provisioning, inventory management
    """

    try:
        # Verify user has access to specified project
        # (Add RBAC check here when user auth implemented)

        # Allow user to specify project_id explicitly
        project_id = agent.project_id  # From request body

        # Verify project exists and user has access
        project = await db.fetch_one(
            "SELECT id FROM projects WHERE id = :id",
            {"id": project_id}
        )
        if not project:
            raise HTTPException(404, "Project not found")

        # Upsert agent record
        await db.execute(
            """
            INSERT INTO agents (
                id, name, type, hostname, platform, version,
                project_id, status, last_seen_at, metadata
            )
            VALUES (
                :id, :name, 'felix', :hostname, :platform, :version,
                :project_id, 'idle', NOW(), :metadata
            )
            ON CONFLICT (id) DO UPDATE SET
                hostname = EXCLUDED.hostname,
                platform = EXCLUDED.platform,
                version = EXCLUDED.version,
                project_id = EXCLUDED.project_id,
                last_seen_at = NOW(),
                updated_at = NOW()
            """,
            {
                "id": agent.agent_id,
                "name": f"agent-{agent.hostname}",
                "hostname": agent.hostname,
                "platform": agent.platform,
                "version": agent.version,
                "project_id": project_id,
                "metadata": json.dumps({"felix_root": agent.felix_root})
            }
        )

        return {
            "status": "registered",
            "agent_id": agent.agent_id,
            "project_id": project_id
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Failed to register agent: {str(e)}")
```

**B. CLI Self-Registration (API Key Auth)**

For autonomous agent self-registration:

```python
@router.post("/agents/register-with-key")
async def register_agent_with_key(
    agent: AgentRegistration,
    db: Database = Depends(get_db),
    key_info: ApiKeyInfo = Depends(verify_api_key)  # API key auth
):
    """
    Agent self-registration via API key (CLI auth).

    Project context derived from API key automatically.
    No client-provided project_id accepted.
    Used for: Felix CLI agents, autonomous registration
    """

    try:
        # Use API key's project_id (single source of truth)
        project_id = key_info.project_id

        # Upsert agent record
        await db.execute(
            """
            INSERT INTO agents (
                id, name, type, hostname, platform, version,
                project_id, status, last_seen_at, metadata
            )
            VALUES (
                :id, :name, 'felix', :hostname, :platform, :version,
                :project_id, 'idle', NOW(), :metadata
            )
            ON CONFLICT (id) DO UPDATE SET
                hostname = EXCLUDED.hostname,
                platform = EXCLUDED.platform,
                version = EXCLUDED.version,
                project_id = EXCLUDED.project_id,
                last_seen_at = NOW(),
                updated_at = NOW()
            """,
            {
                "id": agent.agent_id,
                "name": f"agent-{agent.hostname}",
                "hostname": agent.hostname,
                "platform": agent.platform,
                "version": agent.version,
                "project_id": project_id,
                "metadata": json.dumps({"felix_root": agent.felix_root})
            }
        )

        return {
            "status": "registered",
            "agent_id": agent.agent_id,
            "project_id": project_id
        }

    except Exception as e:
        raise HTTPException(500, f"Failed to register agent: {str(e)}")
```

**Architecture Benefits:**

- ✅ Clean separation: UI users don't need API keys for manual operations
- ✅ Flexible auth: Session-based for UI, token-based for CLI
- ✅ RBAC preserved: UI operations go through normal permission checks
- ✅ Backward compatible: Existing UI code unchanged
- ✅ Security: Different attack surfaces, different auth boundaries

````

#### Step 2.4: Update Run Creation Endpoint

**File:** `app/backend/routers/sync.py`

Update `RunCreate` model (remove `project_id`):

```python
class RunCreate(BaseModel):
    id: Optional[str] = None
    requirement_id: str
    agent_id: str
    # REMOVED: project_id (backend derives from API key)
    branch: Optional[str] = None
    commit_sha: Optional[str] = None
    scenario: Optional[str] = "autonomous"
    phase: Optional[str] = "planning"
````

Update `create_run()` endpoint:

```python
@router.post("/runs")
async def create_run(
    run: RunCreate,
    db: Database = Depends(get_db),
    key_info: ApiKeyInfo = Depends(verify_api_key)
):
    """
    Create new run record.

    project_id derived from API key (not client request).
    """

    run_id = run.id or str(uuid.uuid4())
    project_id = key_info.project_id  # API key determines project

    try:
        # Verify agent exists
        agent = await db.fetch_one(
            "SELECT id FROM agents WHERE id = :id",
            {"id": run.agent_id}
        )
        if not agent:
            raise HTTPException(404, f"Agent not found: {run.agent_id}")

        # Create run record (project_id from key_info)
        await db.execute(
            """
            INSERT INTO runs (
                id, agent_id, project_id, org_id, requirement_id,
                branch, commit_sha, status, phase, scenario,
                created_at, started_at
            )
            VALUES (
                :id, :agent_id, :project_id, :org_id, :requirement_id,
                :branch, :commit_sha, 'running', :phase, :scenario,
                NOW(), NOW()
            )
            """,
            {
                "id": run_id,
                "agent_id": run.agent_id,
                "project_id": project_id,
                "org_id": key_info.org_id,
                "requirement_id": run.requirement_id,
                "branch": run.branch,
                "commit_sha": run.commit_sha,
                "phase": run.phase,
                "scenario": run.scenario
            }
        )

        # Log initial event
        await db.execute(
            """
            INSERT INTO run_events (run_id, type, level, message, ts)
            VALUES (:run_id, 'run_started', 'info', :message, NOW())
            """,
            {
                "run_id": run_id,
                "message": f"Run started on {run.agent_id} in project {project_id}"
            }
        )

        return {
            "run_id": run_id,
            "status": "created",
            "project_id": project_id
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Failed to create run: {str(e)}")
```

#### Step 2.5: Update Artifact Upload Endpoint

**File:** `app/backend/routers/sync.py`

Update `upload_artifacts_batch()`:

```python
@router.post("/runs/{run_id}/files")
async def upload_artifacts_batch(
    run_id: str,
    manifest: str = Form(...),
    files: list[UploadFile] = File(...),
    db: Database = Depends(get_db),
    storage: ArtifactStorage = Depends(get_artifact_storage),
    key_info: ApiKeyInfo = Depends(verify_api_key)
):
    """
    Batch upload run artifacts with SHA256 manifest.

    Validates run belongs to API key's project.
    """

    try:
        # Verify run exists and belongs to key's project
        run = await db.fetch_one(
            "SELECT id, project_id FROM runs WHERE id = :run_id",
            {"run_id": run_id}
        )
        if not run:
            raise HTTPException(404, "Run not found")

        # Authorize project access
        require_project_access(key_info, str(run["project_id"]))

        project_id = run["project_id"]

        # ... rest of implementation unchanged ...
```

#### Step 2.6: Remove AUTH_MODE

**File:** `app/backend/config.py`

Remove or comment out:

```python
# DEPRECATED: AUTH_MODE removed in v0.3.0
# All backend operations now require valid API key
# AUTH_MODE = os.getenv("AUTH_MODE", "disabled")
```

**File:** `app/backend/auth.py`

Remove mock auth mode from `get_current_user()`:

```python
async def get_current_user(...):
    # REMOVED: AUTH_MODE=disabled mock credentials
    # Always require real authentication
    if not token:
        raise HTTPException(401, "Authentication required")

    # ... real auth implementation ...
```

**Testing Checkpoint:**

```bash
# Start backend
cd app/backend && python main.py

# Test key validation (should fail - no key)
curl http://localhost:8080/api/runs
# Expected: 401 Unauthorized

# Generate test key
python scripts/generate-sync-key.py --project-id 00000000-0000-0000-0000-000000000001 --name "Test Key"
# Output: fsk_abc123...

# Test with valid key
curl -H "Authorization: Bearer fsk_abc123..." http://localhost:8080/api/runs
# Expected: 200 OK (empty runs list)

# Test with invalid key
curl -H "Authorization: Bearer fsk_invalid..." http://localhost:8080/api/runs
# Expected: 401 Invalid API key

# Test CLI agent registration (API key auth)
curl -X POST -H "Authorization: Bearer fsk_abc123..." \
  -H "Content-Type: application/json" \
  -d '{"agent_id":"test-123","hostname":"test-host","platform":"windows","version":"0.3.0"}' \
  http://localhost:8080/api/agents/register-with-key
# Expected: {"status":"registered","agent_id":"test-123","project_id":"00000000-..."}

# Verify agent assigned to key's project
psql -c "SELECT id, hostname, project_id FROM agents WHERE id = 'test-123'"
# Expected: project_id matches key's project

# Test UI agent registration (user auth - TODO when auth implemented)
# curl -X POST -H "Cookie: session=..." \
#   -H "Content-Type: application/json" \
#   -d '{"agent_id":"ui-agent-123","hostname":"remote-host","project_id":"..."}' \
#   http://localhost:8080/api/agents/register
```

---

### Phase 3: API Key Management Endpoints

**Estimated Time:** 4 hours

#### Step 3.1: Create Keys Router

**File:** `app/backend/routers/keys.py` (new file)

```python
from fastapi import APIRouter, HTTPException, Depends
from databases import Database
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime, timedelta
import secrets
import hashlib
import uuid

from app.backend.database import get_db
from app.backend.routers.sync import verify_api_key, ApiKeyInfo

router = APIRouter(prefix="/api", tags=["api-keys"])

# --- Models ---

class ApiKeyCreateRequest(BaseModel):
    name: str
    expires_days: Optional[int] = None  # None = never expires

class ApiKeyCreateResponse(BaseModel):
    key: str  # Raw key (shown ONCE)
    key_id: str
    name: str
    project_id: str
    expires_at: Optional[str] = None

class ApiKeyListItem(BaseModel):
    id: str
    name: str
    created_at: str
    expires_at: Optional[str] = None
    last_used_at: Optional[str] = None

class ApiKeyValidationResponse(BaseModel):
    project_id: str
    project_name: str
    org_id: str
    key_name: Optional[str] = None
    expires_at: Optional[str] = None

# --- Endpoints ---

@router.post("/projects/{project_id}/api-keys", response_model=ApiKeyCreateResponse)
async def generate_api_key(
    project_id: str,
    request: ApiKeyCreateRequest,
    db: Database = Depends(get_db),
    # TODO: Add user authentication when ready
):
    """
    Generate new API key for project.

    Returns raw key ONCE - cannot be retrieved later.
    """

    try:
        # Verify project exists
        project = await db.fetch_one(
            "SELECT id, name FROM projects WHERE id = :id",
            {"id": project_id}
        )
        if not project:
            raise HTTPException(404, "Project not found")

        # Generate key
        raw_key = f"fsk_{secrets.token_hex(32)}"
        key_hash = hashlib.sha256(raw_key.encode()).hexdigest()
        key_id = str(uuid.uuid4())

        # Calculate expiration
        expires_at = None
        if request.expires_days:
            expires_at = datetime.now() + timedelta(days=request.expires_days)

        # Insert key
        await db.execute(
            """
            INSERT INTO api_keys (id, key_hash, project_id, name, expires_at, created_at)
            VALUES (:id, :key_hash, :project_id, :name, :expires_at, NOW())
            """,
            {
                "id": key_id,
                "key_hash": key_hash,
                "project_id": project_id,
                "name": request.name,
                "expires_at": expires_at
            }
        )

        return ApiKeyCreateResponse(
            key=raw_key,
            key_id=key_id,
            name=request.name,
            project_id=project_id,
            expires_at=expires_at.isoformat() if expires_at else None
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Failed to generate API key: {str(e)}")


@router.get("/projects/{project_id}/api-keys", response_model=List[ApiKeyListItem])
async def list_api_keys(
    project_id: str,
    db: Database = Depends(get_db),
    # TODO: Add user authentication when ready
):
    """List all API keys for project (excludes raw keys)."""

    try:
        rows = await db.fetch_all(
            """
            SELECT id, name, created_at, expires_at, last_used_at
            FROM api_keys
            WHERE project_id = :project_id
            ORDER BY created_at DESC
            """,
            {"project_id": project_id}
        )

        return [
            ApiKeyListItem(
                id=str(row["id"]),
                name=row["name"],
                created_at=row["created_at"].isoformat(),
                expires_at=row["expires_at"].isoformat() if row["expires_at"] else None,
                last_used_at=row["last_used_at"].isoformat() if row["last_used_at"] else None
            )
            for row in rows
        ]

    except Exception as e:
        raise HTTPException(500, f"Failed to list API keys: {str(e)}")


@router.delete("/api-keys/{key_id}")
async def revoke_api_key(
    key_id: str,
    db: Database = Depends(get_db),
    # TODO: Add user authentication + authorization when ready
):
    """Revoke (delete) an API key."""

    try:
        result = await db.execute(
            "DELETE FROM api_keys WHERE id = :key_id",
            {"key_id": key_id}
        )

        if result == 0:
            raise HTTPException(404, "API key not found")

        return {"status": "revoked", "key_id": key_id}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Failed to revoke API key: {str(e)}")


@router.get("/keys/validate", response_model=ApiKeyValidationResponse)
async def validate_api_key(
    db: Database = Depends(get_db),
    key_info: ApiKeyInfo = Depends(verify_api_key)
):
    """
    Validate current API key and return project info.

    Used by CLI during startup to verify key and cache project_id.
    """

    try:
        # Fetch project details
        project = await db.fetch_one(
            "SELECT id, name, org_id FROM projects WHERE id = :id",
            {"id": key_info.project_id}
        )

        if not project:
            raise HTTPException(500, "Project not found for valid API key")

        # Fetch expiration
        key = await db.fetch_one(
            "SELECT expires_at FROM api_keys WHERE id = :id",
            {"id": key_info.key_id}
        )

        return ApiKeyValidationResponse(
            project_id=str(project["id"]),
            project_name=project["name"],
            org_id=str(project["org_id"]),
            key_name=key_info.name,
            expires_at=key["expires_at"].isoformat() if key["expires_at"] else None
        )

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Failed to validate API key: {str(e)}")
```

#### Step 3.2: Register Keys Router

**File:** `app/backend/main.py`

Add:

```python
from app.backend.routers import keys

app.include_router(keys.router, tags=["api-keys"])
```

#### Step 3.3: Update Key Generation Script

**File:** `scripts/generate-sync-key.py`

Update to require `--project-id`:

```python
import argparse
import secrets
import hashlib
import uuid
from datetime import datetime, timedelta
import psycopg2

parser = argparse.ArgumentParser(description="Generate Felix sync API key")
parser.add_argument("--project-id", required=True, help="Project UUID (required)")
parser.add_argument("--name", required=True, help="Human-readable key name")
parser.add_argument("--expires-days", type=int, help="Expiration in days (omit for never)")
parser.add_argument("--db-url", default="postgresql://postgres:postgres@localhost/felix")
args = parser.parse_args()

# Generate key
raw_key = f"fsk_{secrets.token_hex(32)}"
key_hash = hashlib.sha256(raw_key.encode()).hexdigest()
key_id = str(uuid.uuid4())

expires_at = None
if args.expires_days:
    expires_at = datetime.now() + timedelta(days=args.expires_days)

# Insert into database
conn = psycopg2.connect(args.db_url)
cur = conn.cursor()

# Verify project exists
cur.execute("SELECT name FROM projects WHERE id = %s", (args.project_id,))
project = cur.fetchone()
if not project:
    print(f"ERROR: Project {args.project_id} not found")
    exit(1)

cur.execute(
    """
    INSERT INTO api_keys (id, key_hash, project_id, name, expires_at)
    VALUES (%s, %s, %s, %s, %s)
    """,
    (key_id, key_hash, args.project_id, args.name, expires_at)
)

conn.commit()
cur.close()
conn.close()

# Output
print(f"\n✅ API Key Generated Successfully")
print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"Key:        {raw_key}")
print(f"ID:         {key_id}")
print(f"Name:       {args.name}")
print(f"Project:    {project[0]} ({args.project_id})")
print(f"Expires:    {expires_at.isoformat() if expires_at else 'Never'}")
print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"\n⚠️  Save this key now - you won't see it again!")
print(f"\nConfigure CLI:")
print(f"  $env:FELIX_SYNC_KEY = \"{raw_key}\"")
print(f"  Or run: felix setup")
```

**Testing Checkpoint:**

```bash
# Generate key for default project
python scripts/generate-sync-key.py \
  --project-id 00000000-0000-0000-0000-000000000001 \
  --name "Dev Key" \
  --expires-days 90

# Test validation endpoint
$key = "fsk_..."  # From script output
curl -H "Authorization: Bearer $key" http://localhost:8080/api/keys/validate | jq .

# Expected output:
# {
#   "project_id": "00000000-0000-0000-0000-000000000001",
#   "project_name": "Default Project",
#   "org_id": "...",
#   "key_name": "Dev Key",
#   "expires_at": "2026-05-18T12:34:56"
# }

# Test list endpoint
curl http://localhost:8080/api/projects/00000000-0000-0000-0000-000000000001/api-keys | jq .

# Test revoke endpoint
curl -X DELETE http://localhost:8080/api/api-keys/<key_id>
```

---

### Phase 4: CLI Changes

**Estimated Time:** 6 hours

#### Step 4.1: Create `felix setup` Command

**File:** `felix/commands/Setup.ps1` (new file)

```powershell
<#
.SYNOPSIS
    Configure Felix CLI for backend sync.

.DESCRIPTION
    Interactive setup wizard to configure API key and backend URL.
    Validates key and saves to .felix/config.json.

.EXAMPLE
    felix setup
#>

function Invoke-Setup {
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host " Felix CLI Setup Wizard" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Cyan

    # Load existing config
    $configPath = ".felix/config.json"
    $config = @{
        agent = @{ agent_id = $null }
        sync = @{
            enabled = $false
            provider = "fastapi"
            base_url = "http://localhost:8080"
            api_key = $null
        }
    }

    if (Test-Path $configPath) {
        $existingConfig = Get-Content $configPath | ConvertFrom-Json
        if ($existingConfig.sync) {
            $config.sync.base_url = $existingConfig.sync.base_url
            $config.sync.api_key = $existingConfig.sync.api_key
        }
    }

    # Prompt for backend URL
    Write-Host "Backend URL"
    $newUrl = Read-Host "  Enter backend URL [$($config.sync.base_url)]"
    if ($newUrl) {
        $config.sync.base_url = $newUrl.TrimEnd('/')
    }

    # Prompt for API key
    Write-Host "`nAPI Key"
    Write-Host "  Generate a key at: $($config.sync.base_url)/settings"
    $newKey = Read-Host "  Paste your API key (fsk_...)"

    if (-not $newKey) {
        Write-Host "`n⚠️  No API key provided - sync will be disabled" -ForegroundColor Yellow
        $config.sync.enabled = $false
    }
    else {
        if (-not $newKey.StartsWith("fsk_")) {
            Write-Host "`n❌ Invalid API key format (expected fsk_...)" -ForegroundColor Red
            exit 1
        }

        # Validate key
        Write-Host "`n🔍 Validating API key..." -ForegroundColor Cyan

        try {
            $validateUrl = "$($config.sync.base_url)/api/keys/validate"
            $headers = @{ "Authorization" = "Bearer $newKey" }
            $response = Invoke-RestMethod -Uri $validateUrl -Method Get -Headers $headers -ErrorAction Stop

            Write-Host "✅ Valid API key!" -ForegroundColor Green
            Write-Host "   Project: $($response.project_name) ($($response.project_id))" -ForegroundColor Gray
            Write-Host "   Organization: $($response.org_id)" -ForegroundColor Gray

            if ($response.expires_at) {
                $expiresAt = [DateTime]::Parse($response.expires_at)
                $daysLeft = ($expiresAt - [DateTime]::Now).Days
                Write-Host "   Expires: $($expiresAt.ToString('yyyy-MM-dd')) ($daysLeft days)" -ForegroundColor Gray
            }

            $config.sync.api_key = $newKey
            $config.sync.enabled = $true
        }
        catch {
            Write-Host "❌ API key validation failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "   Check backend URL and key, then try again" -ForegroundColor Yellow
            exit 1
        }
    }

    # Save config
    Write-Host "`n💾 Saving configuration..." -ForegroundColor Cyan

    $config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8

    Write-Host "✅ Configuration saved to $configPath" -ForegroundColor Green

    # Update .gitignore
    $gitignorePath = ".gitignore"
    if (Test-Path $gitignorePath) {
        $gitignore = Get-Content $gitignorePath -Raw
        if ($gitignore -notmatch ".felix/config.json") {
            Add-Content $gitignorePath "`n# Felix local config (contains API key)`n.felix/config.json"
            Write-Host "✅ Updated .gitignore to exclude config.json" -ForegroundColor Green
        }
    }

    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host " Setup Complete!" -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

    if ($config.sync.enabled) {
        Write-Host "`n✅ Sync enabled - runs will mirror to backend" -ForegroundColor Green
        Write-Host "   Run: felix run <requirement-id>" -ForegroundColor Gray
    }
    else {
        Write-Host "`n⚠️  Sync disabled - runs will only save locally" -ForegroundColor Yellow
        Write-Host "   Run 'felix setup' again to enable sync" -ForegroundColor Gray
    }

    Write-Host ""
}

Export-ModuleMember -Function Invoke-Setup
```

#### Step 4.2: Update CLI Startup Validation

**File:** `felix/felix-agent.ps1`

Add after config load:

```powershell
# Validate sync configuration
if ($config.sync -and $config.sync.enabled) {
    if (-not $config.sync.api_key) {
        Write-Host "❌ Sync enabled but no API key configured" -ForegroundColor Red
        Write-Host "   Run: felix setup" -ForegroundColor Yellow
        exit 1
    }

    # Validate API key during startup
    try {
        $validateUrl = "$($config.sync.base_url)/api/keys/validate"
        $headers = @{ "Authorization" = "Bearer $($config.sync.api_key)" }
        $response = Invoke-RestMethod -Uri $validateUrl -Method Get -Headers $headers -ErrorAction Stop

        Write-Host "[SYNC] Validated API key → Project: $($response.project_name) ($($response.project_id))" -ForegroundColor Cyan

        # Cache project_id for this session
        $global:FELIX_PROJECT_ID = $response.project_id
    }
    catch {
        Write-Warning "[SYNC] API key validation failed: $($_.Exception.Message)"
        Write-Warning "[SYNC] Sync disabled - running in local-only mode"

        # Gracefully disable sync
        $config.sync.enabled = $false
    }
}
else {
    Write-Host "[SYNC] Sync not enabled - running in local-only mode" -ForegroundColor Gray
}
```

#### Step 4.3: Update Sync Plugin

**File:** `.felix/plugins/sync-fastapi.ps1`

Update constructor:

```powershell
FastApiReporter([hashtable]$config) {
    $this.BaseUrl = $config.base_url
    $this.ApiKey = $config.api_key
    $this.OutboxPath = ".felix/outbox"

    # Ensure outbox exists
    New-Item -ItemType Directory -Path $this.OutboxPath -Force | Out-Null

    # Validate API key and cache project_id
    try {
        $validateUrl = "$($this.BaseUrl)/api/keys/validate"
        $headers = @{ "Authorization" = "Bearer $($this.ApiKey)" }
        $response = Invoke-RestMethod -Uri $validateUrl -Method Get -Headers $headers

        $this.ProjectId = $response.project_id
        Write-Host "[SYNC] Validated API key → Project: $($response.project_name) ($($this.ProjectId))" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "[SYNC] API key validation failed: $($_.Exception.Message)"
        Write-Warning "[SYNC] Sync disabled - run 'felix setup' to configure"
        throw "API key validation failed"
    }
}
```

Update `StartRun()`:

```powershell
[string] StartRun([hashtable]$metadata) {
    # Generate client-side run ID
    $runId = [guid]::NewGuid().ToString()
    $metadata.id = $runId

    # REMOVED: project_id from request body (backend derives from API key)
    # Backend will use key's project_id automatically

    $this.QueueRequest("POST", "/api/runs", $metadata)
    $this.TrySendOutbox()
    return $runId
}
```

**Testing Checkpoint:**

```powershell
# Test setup command
.\felix\felix.ps1 setup

# Follow prompts:
# Backend URL: http://localhost:8080
# API Key: fsk_... (paste generated key)

# Expected: Validation success, config saved

# Verify config
Get-Content .felix\config.json | ConvertFrom-Json

# Test agent startup with valid key
.\felix\felix.ps1 run S-0001
# Expected log: "[SYNC] Validated API key → Project: ..."

# Test with invalid key
$env:FELIX_SYNC_KEY = "fsk_invalid..."
.\felix\felix.ps1 run S-0002
# Expected log: "[SYNC] API key validation failed... running in local-only mode"

# Test without key (local-only)
$config = Get-Content .felix\config.json | ConvertFrom-Json
$config.sync.api_key = $null
$config | ConvertTo-Json -Depth 10 | Set-Content .felix\config.json
.\felix\felix.ps1 run S-0003
# Expected log: "[SYNC] Sync not enabled - running in local-only mode"
```

---

### Phase 5: Frontend UI

**Estimated Time:** 6 hours

#### Step 5.1: Add API Keys Tab

**File:** `app/frontend/components/OrganizationSettingsScreen.tsx`

Add new tab after Projects:

```tsx
const [selectedTab, setSelectedTab] = useState<
  | "members"
  | "projects"
  | "api-keys"
  | "adapters"
  | "templates"
  | "policies"
  | "billing"
>("members");

// In tab buttons section:
<button
  onClick={() => setSelectedTab("api-keys")}
  className={selectedTab === "api-keys" ? "active" : ""}
>
  <Key className="w-4 h-4" />
  API Keys
</button>;

// In tab content section:
{
  selectedTab === "api-keys" && <ApiKeysTab organization={organization} />;
}
```

#### Step 5.2: Create API Keys Tab Component

**File:** `app/frontend/components/ApiKeysTab.tsx` (new file)

```tsx
import React, { useState, useEffect } from "react";
import { Key, Plus, Trash2, Copy, Clock } from "lucide-react";
import { formatDistanceToNow } from "date-fns";

interface ApiKey {
  id: string;
  name: string;
  created_at: string;
  expires_at: string | null;
  last_used_at: string | null;
}

interface ApiKeysTabProps {
  organization: Organization;
}

export function ApiKeysTab({ organization }: ApiKeysTabProps) {
  const [keys, setKeys] = useState<ApiKey[]>([]);
  const [selectedProject, setSelectedProject] = useState<string | null>(null);
  const [showGenerateDialog, setShowGenerateDialog] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (selectedProject) {
      fetchKeys(selectedProject);
    }
  }, [selectedProject]);

  const fetchKeys = async (projectId: string) => {
    setLoading(true);
    try {
      const response = await fetch(`/api/projects/${projectId}/api-keys`);
      if (response.ok) {
        const data = await response.json();
        setKeys(data);
      }
    } catch (error) {
      console.error("Failed to fetch API keys:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleRevoke = async (keyId: string) => {
    if (!confirm("Revoke this API key? This action cannot be undone.")) {
      return;
    }

    try {
      const response = await fetch(`/api/api-keys/${keyId}`, {
        method: "DELETE",
      });

      if (response.ok) {
        setKeys(keys.filter((k) => k.id !== keyId));
      } else {
        alert("Failed to revoke API key");
      }
    } catch (error) {
      console.error("Failed to revoke key:", error);
      alert("Failed to revoke API key");
    }
  };

  return (
    <div className="space-y-6">
      {/* Project Selector */}
      <div className="flex items-center justify-between">
        <div className="flex-1 max-w-md">
          <label className="block text-sm font-medium text-gray-700 mb-2">
            Select Project
          </label>
          <select
            value={selectedProject || ""}
            onChange={(e) => setSelectedProject(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-md"
          >
            <option value="">Select a project...</option>
            {organization.projects?.map((project) => (
              <option key={project.id} value={project.id}>
                {project.name}
              </option>
            ))}
          </select>
        </div>

        {selectedProject && (
          <button
            onClick={() => setShowGenerateDialog(true)}
            className="btn btn-primary flex items-center gap-2"
          >
            <Plus className="w-4 h-4" />
            Generate Key
          </button>
        )}
      </div>

      {/* Keys Table */}
      {selectedProject && (
        <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
          <table className="w-full">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Name
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Created
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Last Used
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Expires
                </th>
                <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {loading ? (
                <tr>
                  <td
                    colSpan={5}
                    className="px-6 py-8 text-center text-gray-500"
                  >
                    Loading...
                  </td>
                </tr>
              ) : keys.length === 0 ? (
                <tr>
                  <td
                    colSpan={5}
                    className="px-6 py-8 text-center text-gray-500"
                  >
                    No API keys for this project.
                    <br />
                    <button
                      onClick={() => setShowGenerateDialog(true)}
                      className="text-blue-600 hover:underline mt-2"
                    >
                      Generate your first key
                    </button>
                  </td>
                </tr>
              ) : (
                keys.map((key) => (
                  <tr key={key.id}>
                    <td className="px-6 py-4">
                      <div className="flex items-center gap-2">
                        <Key className="w-4 h-4 text-gray-400" />
                        <span className="font-medium">{key.name}</span>
                      </div>
                    </td>
                    <td className="px-6 py-4 text-sm text-gray-500">
                      {formatDistanceToNow(new Date(key.created_at), {
                        addSuffix: true,
                      })}
                    </td>
                    <td className="px-6 py-4 text-sm text-gray-500">
                      {key.last_used_at
                        ? formatDistanceToNow(new Date(key.last_used_at), {
                            addSuffix: true,
                          })
                        : "Never"}
                    </td>
                    <td className="px-6 py-4 text-sm">
                      {key.expires_at ? (
                        <span className="flex items-center gap-1 text-orange-600">
                          <Clock className="w-3 h-3" />
                          {new Date(key.expires_at).toLocaleDateString()}
                        </span>
                      ) : (
                        <span className="text-gray-500">Never</span>
                      )}
                    </td>
                    <td className="px-6 py-4 text-right">
                      <button
                        onClick={() => handleRevoke(key.id)}
                        className="text-red-600 hover:text-red-700"
                        title="Revoke key"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}

      {/* Generate Key Dialog */}
      {showGenerateDialog && (
        <ApiKeyGenerationDialog
          projectId={selectedProject!}
          onClose={() => setShowGenerateDialog(false)}
          onGenerated={() => {
            setShowGenerateDialog(false);
            fetchKeys(selectedProject!);
          }}
        />
      )}
    </div>
  );
}
```

#### Step 5.3: Create Key Generation Dialog

**File:** `app/frontend/components/ApiKeyGenerationDialog.tsx` (new file)

```tsx
import React, { useState } from "react";
import { Copy, Check, AlertTriangle } from "lucide-react";

interface ApiKeyGenerationDialogProps {
  projectId: string;
  onClose: () => void;
  onGenerated: () => void;
}

export function ApiKeyGenerationDialog({
  projectId,
  onClose,
  onGenerated,
}: ApiKeyGenerationDialogProps) {
  const [step, setStep] = useState<"form" | "show-key">("form");
  const [name, setName] = useState("");
  const [expiresDays, setExpiresDays] = useState<number | null>(90);
  const [generatedKey, setGeneratedKey] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [loading, setLoading] = useState(false);

  const handleGenerate = async () => {
    if (!name.trim()) {
      alert("Please enter a key name");
      return;
    }

    setLoading(true);

    try {
      const response = await fetch(`/api/projects/${projectId}/api-keys`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: name.trim(),
          expires_days: expiresDays,
        }),
      });

      if (!response.ok) {
        throw new Error("Failed to generate key");
      }

      const data = await response.json();
      setGeneratedKey(data.key);
      setStep("show-key");
    } catch (error) {
      console.error("Failed to generate key:", error);
      alert("Failed to generate API key");
    } finally {
      setLoading(false);
    }
  };

  const handleCopy = () => {
    if (generatedKey) {
      navigator.clipboard.writeText(generatedKey);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg shadow-xl max-w-lg w-full mx-4">
        {step === "form" ? (
          <>
            <div className="px-6 py-4 border-b border-gray-200">
              <h2 className="text-xl font-semibold">Generate API Key</h2>
            </div>

            <div className="px-6 py-4 space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Key Name *
                </label>
                <input
                  type="text"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="e.g., Production Agent 1"
                  className="w-full px-3 py-2 border border-gray-300 rounded-md"
                  autoFocus
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Expiration
                </label>
                <select
                  value={expiresDays || ""}
                  onChange={(e) =>
                    setExpiresDays(
                      e.target.value ? parseInt(e.target.value) : null,
                    )
                  }
                  className="w-full px-3 py-2 border border-gray-300 rounded-md"
                >
                  <option value="30">30 days</option>
                  <option value="90">90 days</option>
                  <option value="365">365 days</option>
                  <option value="">Never</option>
                </select>
              </div>
            </div>

            <div className="px-6 py-4 border-t border-gray-200 flex justify-end gap-3">
              <button onClick={onClose} className="btn btn-secondary">
                Cancel
              </button>
              <button
                onClick={handleGenerate}
                disabled={loading}
                className="btn btn-primary"
              >
                {loading ? "Generating..." : "Generate Key"}
              </button>
            </div>
          </>
        ) : (
          <>
            <div className="px-6 py-4 border-b border-gray-200">
              <h2 className="text-xl font-semibold text-green-600">
                API Key Generated
              </h2>
            </div>

            <div className="px-6 py-4 space-y-4">
              <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4 flex gap-3">
                <AlertTriangle className="w-5 h-5 text-yellow-600 flex-shrink-0 mt-0.5" />
                <div className="text-sm text-yellow-800">
                  <strong>Save this key now!</strong> You won't be able to see
                  it again. If you lose it, you'll need to generate a new key.
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  API Key
                </label>
                <div className="flex gap-2">
                  <input
                    type="text"
                    value={generatedKey || ""}
                    readOnly
                    className="flex-1 px-3 py-2 border border-gray-300 rounded-md font-mono text-sm bg-gray-50"
                  />
                  <button
                    onClick={handleCopy}
                    className="btn btn-secondary flex items-center gap-2"
                  >
                    {copied ? (
                      <>
                        <Check className="w-4 h-4" />
                        Copied
                      </>
                    ) : (
                      <>
                        <Copy className="w-4 h-4" />
                        Copy
                      </>
                    )}
                  </button>
                </div>
              </div>

              <div className="bg-gray-50 border border-gray-200 rounded-lg p-4">
                <p className="text-sm text-gray-700 mb-2">
                  <strong>Next Steps:</strong>
                </p>
                <ol className="text-sm text-gray-600 space-y-1 list-decimal list-inside">
                  <li>Copy the key above</li>
                  <li>
                    Run{" "}
                    <code className="bg-gray-200 px-1 rounded">
                      felix setup
                    </code>{" "}
                    in your CLI
                  </li>
                  <li>Paste the key when prompted</li>
                </ol>
              </div>
            </div>

            <div className="px-6 py-4 border-t border-gray-200 flex justify-end">
              <button
                onClick={() => {
                  onGenerated();
                  onClose();
                }}
                className="btn btn-primary"
              >
                Done
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
```

#### Step 5.4: Update Types

**File:** `app/frontend/types/api.ts`

Add:

```typescript
export interface ApiKey {
  id: string;
  name: string;
  created_at: string;
  expires_at: string | null;
  last_used_at: string | null;
}

export interface ApiKeyCreateResponse {
  key: string; // Raw key (shown once)
  key_id: string;
  name: string;
  project_id: string;
  expires_at: string | null;
}
```

**Testing Checkpoint:**

1. Start frontend: `cd app/frontend && npm run dev`
2. Navigate to Organization Settings → API Keys tab
3. Select a project from dropdown
4. Click "Generate Key"
5. Enter name "Test Key", select 90 days expiration
6. Click "Generate Key"
7. Verify key shown with warning (save now)
8. Copy key to clipboard
9. Close dialog
10. Verify key appears in table
11. Test revoke button (confirm dialog, key removed)

---

### Phase 6: Documentation

**Estimated Time:** 2 hours

#### Step 6.1: Update AGENTS.md

**File:** `AGENTS.md`

Replace "Sync Configuration" section:

````markdown
## Sync Configuration (Optional)

Enable artifact mirroring to server for team collaboration:

### Quick Setup

```powershell
# Run interactive setup wizard
felix setup

# Follow prompts:
# 1. Backend URL: https://felix.example.com
# 2. API Key: fsk_... (generate at /settings)
```
````

### Manual Configuration

**Environment Variables:**

```powershell
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "https://felix.example.com"
$env:FELIX_SYNC_KEY = "fsk_your_api_key_here"
```

**Config File (.felix/config.json):**

```json
{
  "sync": {
    "enabled": true,
    "provider": "fastapi",
    "base_url": "https://felix.example.com",
    "api_key": "fsk_your_api_key_here"
  }
}
```

**Important:**

- API key is **required** for sync (no fallback mode)
- No `project_id` in config - backend derives from API key
- Add `.felix/config.json` to `.gitignore` (contains sensitive key)

### Local-Only Mode

Felix CLI works without API key - runs execute locally, sync disabled:

```powershell
# No sync config needed for local development
felix run S-0001

# Artifacts saved to local runs/ folder only
```

### How It Works

- Agent validates API key on startup via `GET /api/keys/validate`
- Backend derives project context from API key (single source of truth)
- Agent writes artifacts locally first (always)
- Sync plugin queues uploads in `.felix/outbox/*.jsonl`
- Automatic retry on network failure (eventual consistency)
- Idempotent: unchanged files skip upload (SHA256 check)

### Console Output

When sync is enabled, agent startup shows:

```
[SYNC] Validated API key → Project: My Project (00000000-...)
```

### Troubleshooting

See [docs/SYNC_OPERATIONS.md](docs/SYNC_OPERATIONS.md) for:

- Error codes (401, 403, 429, 503)
- Outbox queue management
- Key validation issues
- Disabling sync in emergency

````

#### Step 6.2: Update SYNC_OPERATIONS.md

Add section on API key errors:

```markdown
## API Key Troubleshooting

### 401 Unauthorized

**Cause:** Invalid or missing API key

**Solution:**
1. Verify key format starts with `fsk_`
2. Check key not revoked: Visit Organization Settings → API Keys
3. Generate new key if needed: `POST /api/projects/{project_id}/api-keys`
4. Update CLI config: `felix setup`

### 403 Forbidden (Project Mismatch)

**Cause:** API key not authorized for requested project

**Example:**
- Key scoped to Project A
- Attempting to upload artifact for Project B run

**Solution:**
1. Verify key's project: `curl -H "Authorization: Bearer $key" /api/keys/validate`
2. Use correct key for target project
3. Or generate new key for target project

### 403 Forbidden (Key Expired)

**Cause:** API key past expiration date

**Solution:**
1. Check expiration: Visit Organization Settings → API Keys
2. Generate new key with longer expiration (or never expire)
3. Update CLI: `felix setup`

### Key Validation Failures

**Symptoms:**
- Agent logs: "API key validation failed"
- Sync disabled, runs local-only

**Diagnosis:**
```powershell
# Test key manually
$key = "fsk_..."
curl -H "Authorization: Bearer $key" http://localhost:8080/api/keys/validate
````

**Common Causes:**

- Backend not running
- Network connectivity issues
- Key typo in config
- Key revoked

**Recovery:**

1. Verify backend health: `curl http://localhost:8080/health`
2. Check key in config: `Get-Content .felix\config.json`
3. Validate key via backend: Test with curl
4. Re-run setup if needed: `felix setup`

````

#### Step 6.3: Create CLI Tutorial

**File:** `tuts/FELIX_CLI.md`

Add section:

```markdown
## Sync Setup

### First-Time Setup

Generate API key via web UI:

1. Open Felix backend: http://localhost:8080
2. Navigate to Organization Settings → API Keys
3. Select target project
4. Click "Generate Key"
5. Copy key (shown once!)

Configure CLI:

```powershell
felix setup

# Prompts:
# Backend URL: http://localhost:8080
# API Key: fsk_... (paste)

# Output:
# ✅ Valid API key!
#    Project: My Project (00000000-...)
# ✅ Configuration saved to .felix/config.json
````

### Verify Setup

```powershell
# Should show sync enabled
felix run S-0001

# Expected log:
# [SYNC] Validated API key → Project: My Project
```

### Switch Projects

To work on different project:

```powershell
# Generate key for new project via web UI
# Run setup again with new key
felix setup

# Or set environment variable (temporary)
$env:FELIX_SYNC_KEY = "fsk_new_project_key..."
```

### Disable Sync

```powershell
# Edit config
$config = Get-Content .felix\config.json | ConvertFrom-Json
$config.sync.enabled = $false
$config | ConvertTo-Json -Depth 10 | Set-Content .felix\config.json

# Or delete config entirely
Remove-Item .felix\config.json
```

````

---

## Verification & Testing

### Unit Tests

**Backend:**

```bash
# Test API key authentication
pytest tests/test_auth.py::test_verify_api_key
pytest tests/test_auth.py::test_verify_api_key_expired
pytest tests/test_auth.py::test_verify_api_key_invalid

# Test project authorization
pytest tests/test_auth.py::test_require_project_access

# Test key management endpoints
pytest tests/test_keys.py::test_generate_key
pytest tests/test_keys.py::test_list_keys
pytest tests/test_keys.py::test_revoke_key
pytest tests/test_keys.py::test_validate_key
````

**CLI:**

```powershell
# Test setup command
Pester tests/Setup.Tests.ps1

# Test key validation
Pester tests/Sync.Tests.ps1
```

### Integration Tests

**Project Isolation:**

```bash
# Generate keys for two projects
$keyA = (python scripts/generate-sync-key.py --project-id $projectA --name "Key A").Split()[-1]
$keyB = (python scripts/generate-sync-key.py --project-id $projectB --name "Key B").Split()[-1]

# Run with Key A
$env:FELIX_SYNC_KEY = $keyA
felix run S-0001

# Verify run in Project A
psql -c "SELECT project_id FROM runs WHERE requirement_id = 'S-0001'" | grep $projectA

# Run with Key B
$env:FELIX_SYNC_KEY = $keyB
felix run S-0002

# Verify run in Project B
psql -c "SELECT project_id FROM runs WHERE requirement_id = 'S-0002'" | grep $projectB

# Attempt cross-project access (should fail)
$runId = (psql -t -c "SELECT id FROM runs WHERE requirement_id = 'S-0001'")
curl -X POST -H "Authorization: Bearer $keyB" \
  http://localhost:8080/api/runs/$runId/files
# Expected: 403 Forbidden
```

**Local-Only Mode:**

```powershell
# Remove API key
Remove-Item .felix\config.json

# Run agent
felix run S-0003

# Verify local artifacts exist
Test-Path runs/**/S-0003  # True

# Verify no sync attempted
ls .felix\outbox\*.jsonl  # Empty
```

**Agent Re-assignment:**

```powershell
# Register with Project A
$env:FELIX_SYNC_KEY = $keyA
felix run S-0004

# Check agent project
psql -c "SELECT project_id FROM agents WHERE hostname = '$env:COMPUTERNAME'"
# Expected: Project A ID

# Switch to Project B
$env:FELIX_SYNC_KEY = $keyB
felix run S-0005

# Check agent project again
psql -c "SELECT project_id FROM agents WHERE hostname = '$env:COMPUTERNAME'"
# Expected: Project B ID (updated)
```

### Manual Testing Checklist

**Database & API Keys:**

- [ ] Migration 017 applies cleanly
- [ ] Generate key via script with `--project-id`
- [ ] Validate key via `GET /api/keys/validate`
- [ ] List keys via `GET /api/projects/{id}/api-keys`
- [ ] Revoke key via `DELETE /api/api-keys/{id}`

**Frontend:**

- [ ] Frontend API Keys tab loads
- [ ] Generate key via UI, copy to clipboard

**Agent Registration:**

- [ ] CLI agent self-registration via `/api/agents/register-with-key` (API key auth)
- [ ] UI agent registration via `/api/agents/register` (user auth - TODO)
- [ ] Agent auto-assigned to API key's project
- [ ] Verify agent.project_id matches key.project_id in database

**CLI Integration:**

- [ ] Run `felix setup` with valid key
- [ ] Agent startup validates key successfully
- [ ] Run with sync enabled, verify backend receives data
- [ ] Run with invalid key, verify graceful degradation
- [ ] Run without key, verify local-only mode

**Authorization:**

- [ ] Attempt cross-project access, verify 403
- [ ] Switch projects (change API key), verify agent reassignment
- [ ] Revoke key via UI, verify agent auth fails on next run

---

## Rollback Plan

### Phase 1: Revert Migration

```sql
-- Undo migration 017
BEGIN;

ALTER TABLE api_keys DROP CONSTRAINT IF EXISTS api_keys_project_id_fkey;
DROP INDEX IF EXISTS idx_api_keys_project_id;
DROP INDEX IF EXISTS idx_api_keys_project_name;
ALTER TABLE api_keys DROP COLUMN IF EXISTS project_id;

-- Re-add agent_id if needed
ALTER TABLE api_keys ADD COLUMN agent_id UUID REFERENCES agents(id) ON DELETE CASCADE;

DELETE FROM schema_migrations WHERE version = 17;

COMMIT;
```

### Phase 2: Revert Backend Code

```bash
git revert <commit-hash-for-auth-changes>
git revert <commit-hash-for-keys-router>
```

### Phase 3: Revert CLI Changes

```bash
git revert <commit-hash-for-felix-setup>
git revert <commit-hash-for-sync-plugin>
```

### Phase 4: Revert Frontend

```bash
git revert <commit-hash-for-api-keys-tab>
```

### Emergency Disable

If blocked in production:

**Backend:**

```bash
# Temporarily disable key validation
export FELIX_SYNC_FEATURE_ENABLED=false
# All sync endpoints return 503
```

**CLI:**

```powershell
# Disable sync in all agents
$env:FELIX_SYNC_ENABLED = "false"
# Agents run in local-only mode
```

---

## Success Criteria

- [x] Every API key is project-scoped (no org-level keys)
- [x] Local dev works without API key (sync disabled gracefully)
- [x] API key IS the project credential (no project_id in config)
- [x] Dual agent registration endpoints (UI user auth + CLI API key auth)
- [x] Frontend UI for key generation, listing, revocation
- [x] CLI `felix setup` command for easy configuration
- [x] Agent auto-registration with project_id from API key
- [x] AUTH_MODE=disabled removed, always use API keys for backend
- [x] Comprehensive error messages guide users to `felix setup`
- [x] All tests passing (unit + integration)
- [x] Documentation complete (AGENTS.md, SYNC_OPERATIONS.md, CLI tutorial)

---

## Breaking Changes Summary

**Version:** 0.3.0

**Changes:**

1. **API keys required for sync** - No AUTH_MODE fallback
2. **Existing keys deleted** - Must regenerate with `--project-id`
3. **project_id removed from config** - Backend derives from key
4. **agent_id removed from api_keys** - Project scoping only

**Migration Path:**

1. Upgrade backend (apply migration 017)
2. Generate new project-scoped keys via script or UI
3. Update CLI configs: Run `felix setup` with new keys
4. Agents will re-register with new project assignments

**Rollback:**

- Revert migration 017
- Revert code changes (3 commits)
- Regenerate old-style keys (no project_id)

---

## Post-Implementation

### Metrics to Monitor

- API key validation success rate
- 403 errors (project mismatch)
- Local-only mode usage (no key configured)
- Agent re-assignment frequency (project switching)
- API key expiration warnings

### Future Enhancements

1. **Key Rotation** - Auto-expire old keys, generate new
2. **Key Permissions** - Read-only vs read-write keys
3. **Org-Level Keys** - Optional super-admin keys (if needed)
4. **Key Usage Analytics** - Dashboard of API calls per key
5. **SCIM Integration** - Auto-provision keys for SSO users

---

**End of Document**
