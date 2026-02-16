# Runs Migration - Step-by-Step Implementation Plan

**Goal:** Implement agent-to-server run artifact mirroring with minimal disruption to existing functionality.

**Strategy:** Incremental implementation with feature flags, backward compatibility at each step, and continuous testing.

---

## Overview

This document provides concrete implementation steps for the [runs_migration.md](runs_migration.md) specification. Each phase includes:

- **Files to create/modify** with exact paths
- **Testing checkpoints** to verify progress
- **Rollback strategy** if issues arise
- **Estimated effort** (person-days)

---

## Phase 0: Preparation (1 day)

### Objectives

- Set up feature branch
- Create database migration stub
- Add feature flag to config
- Document baseline state

### Steps

#### 1. Create Feature Branch

```bash
git checkout -b feature/run-artifact-sync
git push -u origin feature/run-artifact-sync
```

#### 2. Add Feature Flag to Config Schema

**File:** `.felix/config.json` (add sync section)

```json
{
  "sync": {
    "enabled": false,
    "provider": "fastapi",
    "base_url": "http://localhost:8080",
    "api_key": null
  }
}
```

**File:** `app/backend/.env.example` (add storage config)

```
STORAGE_TYPE=filesystem
STORAGE_BASE_PATH=storage/runs
```

#### 3. Create Database Migration File

**File:** `app/backend/migrations/014_run_artifact_mirroring.sql`

```sql
-- Phase 1: Extend existing tables
-- To be implemented in steps

-- Placeholder for migration tracking
INSERT INTO schema_migrations (version, applied_at)
VALUES (14, NOW());
```

#### 4. Document Current State

**Command:**

```bash
# Count existing runs data
ls runs | measure-object

# Check database schema
psql -U postgres -d felix -c "\d runs"
psql -U postgres -d felix -c "\d agents"
psql -U postgres -d felix -c "\d run_artifacts"
```

**File:** `Enhancements/RUNS_BASELINE.md` (snapshot current behavior)

### Testing Checkpoint

- [ ] Feature branch created and pushed
- [ ] Config schema accepts sync settings (parse test)
- [ ] Baseline metrics documented
- [ ] Migration file exists (doesn't break setup-db.ps1)

### Rollback

- Delete branch: `git branch -D feature/run-artifact-sync`
- No production impact (all changes local)

---

## Phase 1: Database Schema Extensions (2 days)

### Objectives

- Extend `runs` table with new columns
- Extend `agents` table with registration fields
- Create `run_events` table
- Create `run_files` table
- Maintain backward compatibility (nullable columns)

### Steps

#### 1. Extend Runs Table

**File:** `app/backend/migrations/014_run_artifact_mirroring.sql`

```sql
-- Extend runs table (all nullable for backward compatibility)
ALTER TABLE runs ADD COLUMN IF NOT EXISTS org_id UUID REFERENCES organizations(id);
ALTER TABLE runs ADD COLUMN IF NOT EXISTS phase TEXT;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS scenario TEXT;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS branch TEXT;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS commit_sha TEXT;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS error_summary TEXT;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS summary_json JSONB DEFAULT '{}'::jsonb;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS duration_sec INTEGER;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS exit_code INTEGER;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS finished_at TIMESTAMPTZ;

-- Add indexes for common queries
CREATE INDEX IF NOT EXISTS idx_runs_org_project ON runs(org_id, project_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_runs_requirement ON runs(project_id, requirement_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_runs_agent ON runs(agent_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_runs_status_time ON runs(status, created_at DESC);

-- Extend status enum
ALTER TABLE runs DROP CONSTRAINT IF EXISTS runs_status_check;
ALTER TABLE runs ADD CONSTRAINT runs_status_check
  CHECK (status IN ('pending', 'queued', 'running', 'completed', 'succeeded', 'failed', 'cancelled', 'stopped', 'rejected', 'blocked'));
```

#### 2. Extend Agents Table

**File:** `app/backend/migrations/014_run_artifact_mirroring.sql` (continue)

```sql
-- Extend agents table
ALTER TABLE agents ADD COLUMN IF NOT EXISTS hostname TEXT;
ALTER TABLE agents ADD COLUMN IF NOT EXISTS platform TEXT;
ALTER TABLE agents ADD COLUMN IF NOT EXISTS version TEXT;
ALTER TABLE agents ADD COLUMN IF NOT EXISTS profile_id UUID;
ALTER TABLE agents ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ DEFAULT NOW();

-- Make project_id nullable (agents can register before assignment)
ALTER TABLE agents ALTER COLUMN project_id DROP NOT NULL;

-- Add index for last_seen queries
CREATE INDEX IF NOT EXISTS idx_agents_last_seen ON agents(status, last_seen_at DESC);
```

#### 3. Create Run Events Table

**File:** `app/backend/migrations/014_run_artifact_mirroring.sql` (continue)

```sql
-- Run events for timeline tracking
CREATE TABLE IF NOT EXISTS run_events (
    id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    level TEXT NOT NULL DEFAULT 'info' CHECK (level IN ('info', 'warn', 'error', 'debug')),
    type TEXT NOT NULL CHECK (type ~ '^[a-z_]+$'),
    message TEXT,
    payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_run_events_run_ts ON run_events(run_id, ts DESC);
CREATE INDEX idx_run_events_type ON run_events(type, ts DESC);
CREATE INDEX idx_run_events_level ON run_events(level, ts DESC) WHERE level IN ('error', 'warn');

COMMENT ON TABLE run_events IS 'Timeline of events during run execution for real-time streaming and analysis';
```

#### 4. Create Run Files Table

**File:** `app/backend/migrations/014_run_artifact_mirroring.sql` (continue)

```sql
-- Run files for artifact tracking (replaces run_artifacts usage)
CREATE TABLE IF NOT EXISTS run_files (
    id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    path TEXT NOT NULL,
    kind TEXT NOT NULL DEFAULT 'artifact' CHECK (kind IN ('artifact', 'log')),
    storage_key TEXT NOT NULL,
    size_bytes BIGINT NOT NULL,
    sha256 TEXT,
    content_type TEXT DEFAULT 'application/octet-stream',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (run_id, path)
);

CREATE INDEX idx_run_files_run ON run_files(run_id);
CREATE INDEX idx_run_files_kind ON run_files(run_id, kind);
CREATE INDEX idx_run_files_sha ON run_files(sha256) WHERE sha256 IS NOT NULL;
CREATE INDEX idx_run_files_updated ON run_files(updated_at DESC);

COMMENT ON TABLE run_files IS 'Artifact storage tracking with SHA256 integrity and deduplication';
```

#### 5. Apply Migration

```bash
# Backup database first
pg_dump -U postgres felix > backup_pre_014_$(date +%Y%m%d).sql

# Apply migration
psql -U postgres -d felix -f app/backend/migrations/014_run_artifact_mirroring.sql

# Verify tables exist
psql -U postgres -d felix -c "\d+ run_events"
psql -U postgres -d felix -c "\d+ run_files"
psql -U postgres -d felix -c "\d runs" | grep -E "(phase|scenario|branch|duration_sec)"
```

### Testing Checkpoint

- [ ] Migration applies without errors
- [ ] All new columns exist with correct types
- [ ] Indexes created successfully
- [ ] Existing data preserved (row count unchanged)
- [ ] Backend still starts without errors
- [ ] Existing run queries still work

**Verification:**

```bash
# Check record counts before/after
psql -U postgres -d felix -c "SELECT COUNT(*) FROM runs;"
psql -U postgres -d felix -c "SELECT COUNT(*) FROM agents;"

# Test nullable columns don't break existing queries
psql -U postgres -d felix -c "SELECT id, status, created_at FROM runs LIMIT 5;"
```

### Rollback

```bash
# Restore from backup
psql -U postgres -d felix < backup_pre_014_$(date +%Y%m%d).sql

# Or manual rollback
psql -U postgres -d felix << EOF
DROP TABLE IF EXISTS run_files CASCADE;
DROP TABLE IF EXISTS run_events CASCADE;
ALTER TABLE runs DROP COLUMN IF EXISTS phase, DROP COLUMN IF EXISTS scenario,
  DROP COLUMN IF EXISTS branch, DROP COLUMN IF EXISTS commit_sha,
  DROP COLUMN IF EXISTS error_summary, DROP COLUMN IF EXISTS summary_json,
  DROP COLUMN IF EXISTS duration_sec, DROP COLUMN IF EXISTS exit_code,
  DROP COLUMN IF EXISTS finished_at, DROP COLUMN IF EXISTS org_id;
ALTER TABLE agents DROP COLUMN IF EXISTS hostname, DROP COLUMN IF EXISTS platform,
  DROP COLUMN IF EXISTS version, DROP COLUMN IF EXISTS profile_id,
  DROP COLUMN IF EXISTS last_seen_at;
EOF
```

---

## Phase 2: Storage Abstraction Layer (2 days)

### Objectives

- Create storage interface
- Implement filesystem storage
- Implement Supabase storage (stub for now)
- Add storage factory with config

### Steps

#### 1. Create Storage Base Interface

**File:** `app/backend/storage/__init__.py`

```python
"""Storage abstraction for run artifacts"""
```

**File:** `app/backend/storage/base.py`

```python
from abc import ABC, abstractmethod
from typing import BinaryIO, Optional

class ArtifactStorage(ABC):
    """Abstract interface for artifact storage"""

    @abstractmethod
    async def put(
        self,
        key: str,
        content: BinaryIO,
        content_type: str,
        metadata: dict[str, str]
    ) -> None:
        """Upload artifact to storage"""
        pass

    @abstractmethod
    async def get(self, key: str) -> bytes:
        """Download artifact from storage"""
        pass

    @abstractmethod
    async def exists(self, key: str) -> bool:
        """Check if artifact exists"""
        pass

    @abstractmethod
    async def delete(self, key: str) -> None:
        """Delete artifact from storage"""
        pass

    @abstractmethod
    async def list_keys(self, prefix: str) -> list[str]:
        """List all keys with given prefix"""
        pass

    @abstractmethod
    async def get_metadata(self, key: str) -> Optional[dict]:
        """Get metadata for a key without downloading content"""
        pass
```

#### 2. Implement Filesystem Storage

**File:** `app/backend/storage/filesystem.py`

```python
import aiofiles
import json
from pathlib import Path
from typing import BinaryIO, Optional
from .base import ArtifactStorage

class FilesystemStorage(ArtifactStorage):
    """Local filesystem storage for artifacts"""

    def __init__(self, base_path: str = "storage/runs"):
        self.base_path = Path(base_path)
        self.base_path.mkdir(parents=True, exist_ok=True)

    def _get_path(self, key: str) -> Path:
        """Convert storage key to safe filesystem path"""
        # Normalize and validate to prevent directory traversal
        safe_key = key.replace("..", "").lstrip("/\\")
        return self.base_path / safe_key

    async def put(
        self,
        key: str,
        content: BinaryIO,
        content_type: str,
        metadata: dict[str, str]
    ) -> None:
        path = self._get_path(key)
        path.parent.mkdir(parents=True, exist_ok=True)

        # Write content
        async with aiofiles.open(path, 'wb') as f:
            await f.write(content.read())

        # Write metadata sidecar
        meta_path = path.with_suffix(path.suffix + '.meta.json')
        async with aiofiles.open(meta_path, 'w') as f:
            await f.write(json.dumps({
                'content_type': content_type,
                **metadata
            }))

    async def get(self, key: str) -> bytes:
        path = self._get_path(key)
        if not path.exists():
            raise FileNotFoundError(f"Artifact not found: {key}")

        async with aiofiles.open(path, 'rb') as f:
            return await f.read()

    async def exists(self, key: str) -> bool:
        return self._get_path(key).exists()

    async def delete(self, key: str) -> None:
        path = self._get_path(key)
        if path.exists():
            path.unlink()

        # Also delete metadata sidecar
        meta_path = path.with_suffix(path.suffix + '.meta.json')
        if meta_path.exists():
            meta_path.unlink()

    async def list_keys(self, prefix: str) -> list[str]:
        prefix_path = self._get_path(prefix)
        if not prefix_path.exists():
            return []

        keys = []
        for path in prefix_path.rglob("*"):
            if path.is_file() and not path.name.endswith('.meta.json'):
                rel_path = path.relative_to(self.base_path)
                keys.append(str(rel_path).replace("\\", "/"))
        return sorted(keys)

    async def get_metadata(self, key: str) -> Optional[dict]:
        path = self._get_path(key)
        meta_path = path.with_suffix(path.suffix + '.meta.json')

        if not meta_path.exists():
            return None

        async with aiofiles.open(meta_path, 'r') as f:
            return json.loads(await f.read())
```

#### 3. Create Supabase Storage Stub

**File:** `app/backend/storage/supabase.py`

```python
from typing import BinaryIO, Optional
from .base import ArtifactStorage

class SupabaseStorage(ArtifactStorage):
    """Supabase Storage implementation (TODO)"""

    def __init__(self, project_url: str, api_key: str, bucket: str = "run-artifacts"):
        self.project_url = project_url
        self.api_key = api_key
        self.bucket = bucket
        raise NotImplementedError("Supabase storage not yet implemented - use filesystem for now")

    async def put(self, key: str, content: BinaryIO, content_type: str, metadata: dict[str, str]) -> None:
        raise NotImplementedError()

    async def get(self, key: str) -> bytes:
        raise NotImplementedError()

    async def exists(self, key: str) -> bool:
        raise NotImplementedError()

    async def delete(self, key: str) -> None:
        raise NotImplementedError()

    async def list_keys(self, prefix: str) -> list[str]:
        raise NotImplementedError()

    async def get_metadata(self, key: str) -> Optional[dict]:
        raise NotImplementedError()
```

#### 4. Create Storage Factory

**File:** `app/backend/storage/factory.py`

```python
import os
from .base import ArtifactStorage
from .filesystem import FilesystemStorage
from .supabase import SupabaseStorage

def get_storage() -> ArtifactStorage:
    """Factory to create storage implementation from environment config"""

    storage_type = os.getenv('STORAGE_TYPE', 'filesystem')

    if storage_type == 'filesystem':
        base_path = os.getenv('STORAGE_BASE_PATH', 'storage/runs')
        return FilesystemStorage(base_path=base_path)

    elif storage_type == 'supabase':
        project_url = os.getenv('SUPABASE_PROJECT_URL')
        api_key = os.getenv('SUPABASE_API_KEY')
        bucket = os.getenv('SUPABASE_BUCKET', 'run-artifacts')

        if not project_url or not api_key:
            raise ValueError("SUPABASE_PROJECT_URL and SUPABASE_API_KEY required for supabase storage")

        return SupabaseStorage(
            project_url=project_url,
            api_key=api_key,
            bucket=bucket
        )

    else:
        raise ValueError(f"Unknown storage type: {storage_type}")

# Singleton instance
_storage_instance: Optional[ArtifactStorage] = None

def get_artifact_storage() -> ArtifactStorage:
    """Get or create singleton storage instance"""
    global _storage_instance
    if _storage_instance is None:
        _storage_instance = get_storage()
    return _storage_instance
```

#### 5. Create Storage Tests

**File:** `app/backend/tests/test_storage.py`

```python
import pytest
import tempfile
import shutil
from pathlib import Path
from io import BytesIO
from app.backend.storage.filesystem import FilesystemStorage

@pytest.fixture
def temp_storage():
    """Create temporary storage for testing"""
    temp_dir = tempfile.mkdtemp()
    storage = FilesystemStorage(base_path=temp_dir)
    yield storage
    shutil.rmtree(temp_dir)

@pytest.mark.asyncio
async def test_put_and_get(temp_storage):
    """Test basic put and get operations"""
    content = b"Hello, World!"
    key = "test/file.txt"

    await temp_storage.put(
        key=key,
        content=BytesIO(content),
        content_type="text/plain",
        metadata={"test": "true"}
    )

    assert await temp_storage.exists(key)

    retrieved = await temp_storage.get(key)
    assert retrieved == content

@pytest.mark.asyncio
async def test_list_keys(temp_storage):
    """Test listing keys with prefix"""
    files = [
        "test/file1.txt",
        "test/file2.txt",
        "other/file3.txt"
    ]

    for key in files:
        await temp_storage.put(
            key=key,
            content=BytesIO(b"test"),
            content_type="text/plain",
            metadata={}
        )

    test_keys = await temp_storage.list_keys("test/")
    assert len(test_keys) == 2
    assert all("test/" in k for k in test_keys)

@pytest.mark.asyncio
async def test_delete(temp_storage):
    """Test file deletion"""
    key = "test/delete-me.txt"

    await temp_storage.put(
        key=key,
        content=BytesIO(b"delete me"),
        content_type="text/plain",
        metadata={}
    )

    assert await temp_storage.exists(key)

    await temp_storage.delete(key)

    assert not await temp_storage.exists(key)

@pytest.mark.asyncio
async def test_get_metadata(temp_storage):
    """Test metadata retrieval"""
    key = "test/meta.txt"
    metadata = {"author": "test", "version": "1.0"}

    await temp_storage.put(
        key=key,
        content=BytesIO(b"content"),
        content_type="text/plain",
        metadata=metadata
    )

    retrieved_meta = await temp_storage.get_metadata(key)
    assert retrieved_meta is not None
    assert retrieved_meta['author'] == "test"
    assert retrieved_meta['version'] == "1.0"
    assert retrieved_meta['content_type'] == "text/plain"
```

### Testing Checkpoint

- [ ] Storage module imports without errors
- [ ] Filesystem storage creates directories correctly
- [ ] Put/get operations work for text and binary files
- [ ] List operations return correct keys
- [ ] Metadata sidecar files created and readable
- [ ] All storage tests pass

**Verification:**

```bash
# Run storage tests
cd app/backend
pytest tests/test_storage.py -v

# Manual test
python -c "
import asyncio
from storage.filesystem import FilesystemStorage
from io import BytesIO

async def test():
    storage = FilesystemStorage('test_storage')
    await storage.put('test.txt', BytesIO(b'Hello'), 'text/plain', {})
    content = await storage.get('test.txt')
    print(f'Retrieved: {content}')
    exists = await storage.exists('test.txt')
    print(f'Exists: {exists}')

asyncio.run(test())
"

# Cleanup
rm -rf test_storage
```

### Rollback

```bash
# Remove storage module
rm -rf app/backend/storage/
git checkout app/backend/storage/  # if previously existed
```

---

## Phase 3: Backend Sync Endpoints (3 days)

### Objectives

- Create sync router with artifact upload endpoints
- Implement agent registration
- Implement run lifecycle endpoints (create, events, finish)
- Add basic authentication (API key)

### Steps

#### 1. Create Sync Router

**File:** `app/backend/routers/sync.py`

```python
from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Form, Header
from fastapi.responses import StreamingResponse
from databases import Database
from typing import Optional
import uuid
import json
from datetime import datetime
from io import BytesIO

from app.backend.database import get_db
from app.backend.storage.factory import get_artifact_storage
from app.backend.storage.base import ArtifactStorage
from pydantic import BaseModel

router = APIRouter(prefix="/api", tags=["sync"])

# --- Models ---

class AgentRegistration(BaseModel):
    agent_id: str
    hostname: str
    platform: str
    version: str
    felix_root: Optional[str] = None

class RunCreate(BaseModel):
    id: Optional[str] = None
    requirement_id: str
    agent_id: str
    project_id: str
    branch: Optional[str] = None
    commit_sha: Optional[str] = None
    scenario: Optional[str] = "autonomous"
    phase: Optional[str] = "planning"

class RunEvent(BaseModel):
    type: str
    level: str = "info"
    message: Optional[str] = None
    payload: Optional[dict] = None

class RunCompletion(BaseModel):
    status: str
    exit_code: int
    duration_sec: Optional[int] = None
    error_summary: Optional[str] = None
    summary_json: Optional[dict] = None

# --- Authentication ---

async def verify_api_key(authorization: str = Header(None)):
    """Simple API key authentication (optional)"""
    # TODO: Implement proper API key validation
    # For now, accept any Bearer token or no auth
    return True

# --- Endpoints ---

@router.post("/agents/register")
async def register_agent(
    agent: AgentRegistration,
    db: Database = Depends(get_db),
    _auth: bool = Depends(verify_api_key)
):
    """Register or update agent (idempotent)"""

    try:
        # Use INSERT ... ON CONFLICT for idempotent upsert
        await db.execute(
            """
            INSERT INTO agents (id, name, type, hostname, platform, version, status, last_seen_at, metadata)
            VALUES (:id, :name, 'felix', :hostname, :platform, :version, 'idle', NOW(), :metadata)
            ON CONFLICT (id) DO UPDATE SET
                hostname = EXCLUDED.hostname,
                platform = EXCLUDED.platform,
                version = EXCLUDED.version,
                last_seen_at = NOW(),
                updated_at = NOW()
            """,
            {
                "id": agent.agent_id,
                "name": f"agent-{agent.hostname}",
                "hostname": agent.hostname,
                "platform": agent.platform,
                "version": agent.version,
                "metadata": json.dumps({"felix_root": agent.felix_root})
            }
        )

        return {"status": "registered", "agent_id": agent.agent_id}

    except Exception as e:
        raise HTTPException(500, f"Failed to register agent: {str(e)}")

@router.post("/runs")
async def create_run(
    run: RunCreate,
    db: Database = Depends(get_db),
    _auth: bool = Depends(verify_api_key)
):
    """Create new run record"""

    run_id = run.id or str(uuid.uuid4())

    try:
        # Verify agent and project exist
        agent = await db.fetch_one("SELECT id FROM agents WHERE id = :id", {"id": run.agent_id})
        if not agent:
            raise HTTPException(404, f"Agent not found: {run.agent_id}")

        project = await db.fetch_one("SELECT id FROM projects WHERE id = :id", {"id": run.project_id})
        if not project:
            raise HTTPException(404, f"Project not found: {run.project_id}")

        # Create run record
        await db.execute(
            """
            INSERT INTO runs (id, agent_id, project_id, requirement_id, branch, commit_sha,
                            status, phase, scenario, created_at, started_at)
            VALUES (:id, :agent_id, :project_id, :requirement_id, :branch, :commit_sha,
                    'running', :phase, :scenario, NOW(), NOW())
            """,
            {
                "id": run_id,
                "agent_id": run.agent_id,
                "project_id": run.project_id,
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
                "message": f"Run started on {run.agent_id}"
            }
        )

        return {"run_id": run_id, "status": "created"}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Failed to create run: {str(e)}")

@router.post("/runs/{run_id}/events")
async def append_events(
    run_id: str,
    events: list[RunEvent],
    db: Database = Depends(get_db),
    _auth: bool = Depends(verify_api_key)
):
    """Append events to run timeline (batch insert)"""

    try:
        # Verify run exists
        run = await db.fetch_one("SELECT id FROM runs WHERE id = :run_id", {"run_id": run_id})
        if not run:
            raise HTTPException(404, "Run not found")

        if not events:
            return {"status": "ok", "count": 0}

        # Batch insert events
        values = []
        for event in events:
            values.append({
                "run_id": run_id,
                "type": event.type,
                "level": event.level,
                "message": event.message,
                "payload": json.dumps(event.payload) if event.payload else None
            })

        await db.execute_many(
            """
            INSERT INTO run_events (run_id, type, level, message, payload, ts)
            VALUES (:run_id, :type, :level, :message, :payload, NOW())
            """,
            values
        )

        return {"status": "appended", "count": len(events)}

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Failed to append events: {str(e)}")

@router.post("/runs/{run_id}/finish")
async def finish_run(
    run_id: str,
    completion: RunCompletion,
    db: Database = Depends(get_db),
    _auth: bool = Depends(verify_api_key)
):
    """Mark run as complete with final status"""

    try:
        result = await db.execute(
            """
            UPDATE runs SET
                status = :status,
                finished_at = NOW(),
                completed_at = NOW(),
                exit_code = :exit_code,
                duration_sec = :duration_sec,
                error_summary = :error_summary,
                summary_json = :summary_json
            WHERE id = :run_id
            """,
            {
                "run_id": run_id,
                "status": completion.status,
                "exit_code": completion.exit_code,
                "duration_sec": completion.duration_sec,
                "error_summary": completion.error_summary,
                "summary_json": json.dumps(completion.summary_json) if completion.summary_json else None
            }
        )

        # Log completion event
        await db.execute(
            """
            INSERT INTO run_events (run_id, type, level, message, ts)
            VALUES (:run_id, 'run_finished', :level, :message, NOW())
            """,
            {
                "run_id": run_id,
                "level": "info" if completion.status == "succeeded" else "error",
                "message": f"Run {completion.status} with exit code {completion.exit_code}"
            }
        )

        return {"status": "finished", "run_id": run_id}

    except Exception as e:
        raise HTTPException(500, f"Failed to finish run: {str(e)}")

@router.post("/runs/{run_id}/files")
async def upload_artifacts_batch(
    run_id: str,
    manifest: str = Form(...),
    files: list[UploadFile] = File(...),
    db: Database = Depends(get_db),
    storage: ArtifactStorage = Depends(get_artifact_storage),
    _auth: bool = Depends(verify_api_key)
):
    """Batch upload run artifacts with SHA256 manifest"""

    try:
        # Verify run exists
        run = await db.fetch_one(
            "SELECT id, project_id FROM runs WHERE id = :run_id",
            {"run_id": run_id}
        )
        if not run:
            raise HTTPException(404, "Run not found")

        project_id = run["project_id"]

        # Parse manifest
        try:
            manifest_data = json.loads(manifest)
        except json.JSONDecodeError:
            raise HTTPException(400, "Invalid manifest JSON")

        # Create lookup for uploaded files
        files_by_name = {f.filename: f for f in files}

        results = []

        for file_meta in manifest_data:
            path = file_meta["path"]
            sha256 = file_meta["sha256"]
            size_bytes = file_meta["size_bytes"]
            content_type = file_meta.get("content_type", "application/octet-stream")

            # Check for existing file with same SHA256 (idempotency)
            existing = await db.fetch_one(
                "SELECT sha256 FROM run_files WHERE run_id = :run_id AND path = :path",
                {"run_id": run_id, "path": path}
            )

            if existing and existing["sha256"] == sha256:
                results.append({"path": path, "status": "skipped", "reason": "unchanged"})
                continue

            # Find uploaded file
            file_data = files_by_name.get(path)
            if not file_data:
                results.append({"path": path, "status": "missing", "reason": "file not in upload"})
                continue

            # Build storage key
            storage_key = f"runs/{project_id}/{run_id}/{path}"

            # Upload to storage
            content = await file_data.read()
            await storage.put(
                key=storage_key,
                content=BytesIO(content),
                content_type=content_type,
                metadata={
                    "sha256": sha256,
                    "size_bytes": str(size_bytes),
                    "run_id": run_id
                }
            )

            # Determine kind
            kind = "log" if path.endswith(".log") else "artifact"

            # Record in database (upsert)
            await db.execute(
                """
                INSERT INTO run_files (run_id, path, kind, storage_key, size_bytes, sha256, content_type, updated_at)
                VALUES (:run_id, :path, :kind, :storage_key, :size_bytes, :sha256, :content_type, NOW())
                ON CONFLICT (run_id, path) DO UPDATE SET
                    storage_key = EXCLUDED.storage_key,
                    size_bytes = EXCLUDED.size_bytes,
                    sha256 = EXCLUDED.sha256,
                    content_type = EXCLUDED.content_type,
                    updated_at = NOW()
                """,
                {
                    "run_id": run_id,
                    "path": path,
                    "kind": kind,
                    "storage_key": storage_key,
                    "size_bytes": size_bytes,
                    "sha256": sha256,
                    "content_type": content_type
                }
            )

            results.append({"path": path, "status": "uploaded", "size_bytes": size_bytes})

        return {
            "run_id": run_id,
            "files": results,
            "total": len(manifest_data),
            "uploaded": len([r for r in results if r["status"] == "uploaded"]),
            "skipped": len([r for r in results if r["status"] == "skipped"])
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"Failed to upload artifacts: {str(e)}")

@router.get("/runs/{run_id}/files")
async def list_run_files(
    run_id: str,
    db: Database = Depends(get_db)
):
    """List all files for a run"""

    files = await db.fetch_all(
        """
        SELECT path, kind, size_bytes, sha256, content_type, updated_at
        FROM run_files
        WHERE run_id = :run_id
        ORDER BY CASE kind WHEN 'artifact' THEN 0 ELSE 1 END, path
        """,
        {"run_id": run_id}
    )

    return {
        "run_id": run_id,
        "files": [dict(f) for f in files]
    }

@router.get("/runs/{run_id}/files/{file_path:path}")
async def download_artifact(
    run_id: str,
    file_path: str,
    db: Database = Depends(get_db),
    storage: ArtifactStorage = Depends(get_artifact_storage)
):
    """Download run artifact"""

    # Get storage key from database
    file_record = await db.fetch_one(
        """
        SELECT storage_key, size_bytes, path, content_type
        FROM run_files
        WHERE run_id = :run_id AND path = :file_path
        """,
        {"run_id": run_id, "file_path": file_path}
    )

    if not file_record:
        raise HTTPException(404, "File not found")

    # Check storage
    if not await storage.exists(file_record["storage_key"]):
        raise HTTPException(404, "Artifact not found in storage")

    # Stream from storage
    content = await storage.get(file_record["storage_key"])

    return StreamingResponse(
        iter([content]),
        media_type=file_record["content_type"] or "application/octet-stream",
        headers={
            "Content-Disposition": f'inline; filename="{file_path}"',
            "Content-Length": str(len(content))
        }
    )

@router.get("/runs/{run_id}/events")
async def get_run_events(
    run_id: str,
    after: Optional[int] = None,
    limit: int = 100,
    db: Database = Depends(get_db)
):
    """Get run event timeline"""

    query = """
        SELECT id, ts, type, level, message, payload
        FROM run_events
        WHERE run_id = :run_id
    """
    params = {"run_id": run_id, "limit": limit}

    if after is not None:
        query += " AND id > :after"
        params["after"] = after

    query += " ORDER BY id ASC LIMIT :limit"

    events = await db.fetch_all(query, params)

    return {
        "run_id": run_id,
        "events": [dict(e) for e in events],
        "has_more": len(events) == limit
    }
```

#### 2. Register Sync Router in Main

**File:** `app/backend/main.py` (modify)

Find the router registration section and add:

```python
from app.backend.routers import sync

app.include_router(sync.router)
```

#### 3. Create Sync Endpoint Tests

**File:** `app/backend/tests/test_sync_endpoints.py`

```python
import pytest
from fastapi.testclient import TestClient
from app.backend.main import app

client = TestClient(app)

def test_agent_registration():
    """Test agent registration endpoint"""
    response = client.post("/api/agents/register", json={
        "agent_id": "test-agent-001",
        "hostname": "test-machine",
        "platform": "windows",
        "version": "0.8.0"
    })

    assert response.status_code == 200
    assert response.json()["status"] == "registered"

def test_create_run():
    """Test run creation endpoint"""
    # First register agent
    client.post("/api/agents/register", json={
        "agent_id": "test-agent-001",
        "hostname": "test-machine",
        "platform": "windows",
        "version": "0.8.0"
    })

    # Create run
    response = client.post("/api/runs", json={
        "requirement_id": "S-0001",
        "agent_id": "test-agent-001",
        "project_id": "test-project-001",
        "branch": "main"
    })

    assert response.status_code == 200
    json_data = response.json()
    assert "run_id" in json_data
    assert json_data["status"] == "created"

# Add more tests for events, finish, file upload/download
```

### Testing Checkpoint

- [ ] Sync router imports successfully
- [ ] Backend starts without errors
- [ ] Agent registration endpoint works
- [ ] Run creation endpoint works
- [ ] Event append endpoint works
- [ ] File upload endpoint accepts multipart data
- [ ] File download endpoint streams content
- [ ] All sync tests pass

**Verification:**

```bash
# Start backend
cd app/backend
python main.py

# In another terminal - test endpoints
curl http://localhost:8080/docs  # Check Swagger UI shows sync endpoints

# Test agent registration
curl -X POST http://localhost:8080/api/agents/register \
  -H "Content-Type: application/json" \
  -d '{"agent_id":"test-001","hostname":"my-machine","platform":"windows","version":"0.8.0"}'

# Run tests
pytest tests/test_sync_endpoints.py -v
```

### Rollback

```bash
# Remove sync router
rm app/backend/routers/sync.py

# Remove router registration from main.py
git checkout app/backend/main.py
```

---

## Phase 4: CLI Sync Plugin (3 days)

### Objectives

- Create sync interface in PowerShell
- Implement NoOp reporter (default)
- Implement FastAPI reporter with outbox queue
- Integrate with felix-agent.ps1

### Steps

#### 1. Create Core Sync Interface

**File:** `.felix/core/sync-interface.ps1`

```powershell
# Abstract interface for run reporting/syncing
class IRunReporter {
    # Agent registration (once per session)
    [void] RegisterAgent([hashtable]$agentInfo) { }

    # Run lifecycle
    [string] StartRun([hashtable]$metadata) { return $null }
    [void] AppendEvent([hashtable]$event) { }
    [void] FinishRun([string]$runId, [hashtable]$result) { }

    # Artifact upload
    [void] UploadArtifact([string]$runId, [string]$relativePath, [string]$localPath) { }
    [void] UploadRunFolder([string]$runId, [string]$runFolderPath) { }

    # Force delivery
    [void] Flush() { }
}

# Default: does nothing (sync disabled)
class NoOpReporter : IRunReporter {
    NoOpReporter() {
        Write-Verbose "Sync disabled - using NoOp reporter"
    }
}

# Factory: load reporter from config
function Get-RunReporter {
    param(
        [string]$ConfigPath = ".felix/config.json"
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-Verbose "Config not found, sync disabled"
        return [NoOpReporter]::new()
    }

    $config = Get-Content $ConfigPath | ConvertFrom-Json

    if (-not $config.sync -or -not $config.sync.enabled) {
        Write-Verbose "Sync not enabled in config"
        return [NoOpReporter]::new()
    }

    # Check environment variable override
    if ($env:FELIX_SYNC_ENABLED -eq "false") {
        Write-Verbose "Sync disabled via environment variable"
        return [NoOpReporter]::new()
    }

    # Load plugin
    $provider = $config.sync.provider
    $pluginPath = ".felix/plugins/sync-$provider.ps1"

    if (Test-Path $pluginPath) {
        Write-Host "Loading sync plugin: $provider" -ForegroundColor Cyan
        . $pluginPath

        # Merge env vars with config
        $syncConfig = $config.sync
        if ($env:FELIX_SYNC_URL) {
            $syncConfig.base_url = $env:FELIX_SYNC_URL
        }
        if ($env:FELIX_SYNC_KEY) {
            $syncConfig.api_key = $env:FELIX_SYNC_KEY
        }

        return New-PluginReporter -Config $syncConfig
    }

    Write-Warning "Sync enabled but plugin not found: $pluginPath"
    return [NoOpReporter]::new()
}

# Export
Export-ModuleMember -Function Get-RunReporter
```

#### 2. Create FastAPI Sync Plugin

**File:** `.felix/plugins/sync-fastapi.ps1`

```powershell
# Load interface
. "$PSScriptRoot/../core/sync-interface.ps1"

class FastApiReporter : IRunReporter {
    [string]$BaseUrl
    [string]$ApiKey
    [string]$OutboxPath

    FastApiReporter([hashtable]$config) {
        $this.BaseUrl = $config.base_url
        $this.ApiKey = $config.api_key
        $this.OutboxPath = ".felix/outbox"

        # Ensure outbox exists
        New-Item -ItemType Directory -Path $this.OutboxPath -Force | Out-Null

        Write-Verbose "FastAPI reporter initialized: $($this.BaseUrl)"
    }

    [void] RegisterAgent([hashtable]$agentInfo) {
        $this.QueueRequest("POST", "/api/agents/register", $agentInfo)
        $this.TrySendOutbox()
    }

    [string] StartRun([hashtable]$metadata) {
        # Generate client-side run ID
        $runId = [guid]::NewGuid().ToString()
        $metadata.id = $runId
        $this.QueueRequest("POST", "/api/runs", $metadata)
        $this.TrySendOutbox()
        return $runId
    }

    [void] AppendEvent([hashtable]$event) {
        $runId = $event.run_id
        $this.AppendToRunOutbox($runId, @{
            type = "event"
            data = $event
        })
    }

    [void] FinishRun([string]$runId, [hashtable]$result) {
        # Flush pending events first
        $this.FlushRunOutbox($runId)

        $this.QueueRequest("POST", "/api/runs/$runId/finish", $result)
        $this.Flush()
    }

    [void] UploadArtifact([string]$runId, [string]$relativePath, [string]$localPath) {
        if (-not (Test-Path $localPath)) {
            Write-Warning "Artifact not found: $localPath"
            return
        }

        $hash = (Get-FileHash $localPath -Algorithm SHA256).Hash.ToLower()
        $size = (Get-Item $localPath).Length

        $this.QueueFileUpload($runId, $relativePath, $localPath, @{
            sha256 = $hash
            size_bytes = $size
            content_type = Get-ContentType $relativePath
        })
    }

    [void] UploadRunFolder([string]$runId, [string]$runFolderPath) {
        $artifacts = @(
            "requirement_id.txt",
            "plan.md",
            "report.md",
            "diff.patch",
            "output.log",
            "backpressure.log",
            "commit.txt"
        )

        $filesToUpload = @()
        foreach ($fileName in $artifacts) {
            $fullPath = Join-Path $runFolderPath $fileName
            if (Test-Path $fullPath) {
                $hash = (Get-FileHash $fullPath -Algorithm SHA256).Hash.ToLower()
                $size = (Get-Item $fullPath).Length

                $filesToUpload += @{
                    relative_path = $fileName
                    local_path = $fullPath
                    sha256 = $hash
                    size_bytes = $size
                    content_type = Get-ContentType $fileName
                }
            }
        }

        if ($filesToUpload.Count -gt 0) {
            $this.QueueBatchUpload($runId, $filesToUpload)
        }
    }

    [void] Flush() {
        $this.TrySendOutbox()
    }

    # --- Private methods ---

    hidden [void] QueueRequest([string]$method, [string]$path, [hashtable]$body) {
        $request = @{
            method = $method
            path = $path
            body = $body
            timestamp = (Get-Date -Format o)
        } | ConvertTo-Json -Compress -Depth 10

        $filename = "{0:yyyyMMdd-HHmmss-fff}.jsonl" -f (Get-Date)
        Add-Content -Path "$($this.OutboxPath)/$filename" -Value $request
    }

    hidden [void] AppendToRunOutbox([string]$runId, [hashtable]$item) {
        $filename = "run-$runId.jsonl"
        $item.timestamp = (Get-Date -Format o)
        $line = $item | ConvertTo-Json -Compress -Depth 10
        Add-Content -Path "$($this.OutboxPath)/$filename" -Value $line
    }

    hidden [void] FlushRunOutbox([string]$runId) {
        $filename = "run-$runId.jsonl"
        $filepath = "$($this.OutboxPath)/$filename"

        if (-not (Test-Path $filepath)) { return }

        try {
            $lines = Get-Content $filepath
            $events = @()

            foreach ($line in $lines) {
                $item = $line | ConvertFrom-Json
                if ($item.type -eq "event") {
                    $events += $item.data
                }
            }

            if ($events.Count -gt 0) {
                $this.SendJsonRequest(@{
                    method = "POST"
                    path = "/api/runs/$runId/events"
                    body = $events
                })
            }

            Remove-Item $filepath -Force
        }
        catch {
            Write-Warning "Failed to flush events for run $runId : $_"
        }
    }

    hidden [void] QueueBatchUpload([string]$runId, [array]$files) {
        $request = @{
            method = "POST"
            path = "/api/runs/$runId/files"
            files = $files
            timestamp = (Get-Date -Format o)
        } | ConvertTo-Json -Compress -Depth 10

        $filename = "{0:yyyyMMdd-HHmmss-fff}-batch-upload.jsonl" -f (Get-Date)
        Add-Content -Path "$($this.OutboxPath)/$filename" -Value $request
    }

    hidden [void] TrySendOutbox() {
        $files = Get-ChildItem -Path $this.OutboxPath -Filter "*.jsonl" -ErrorAction SilentlyContinue |
                 Sort-Object Name

        if (-not $files) { return }

        foreach ($file in $files) {
            try {
                $lines = Get-Content $file.FullName
                foreach ($line in $lines) {
                    $req = $line | ConvertFrom-Json

                    if ($req.method -eq "POST" -and $req.path -match '/files$' -and $req.files) {
                        $this.UploadBatch($req)
                    } else {
                        $this.SendJsonRequest($req)
                    }
                }

                Remove-Item $file.FullName -Force
                Write-Verbose "Synced outbox file: $($file.Name)"
            }
            catch {
                Write-Warning "Sync failed (will retry): $_"
                break
            }
        }
    }

    hidden [void] SendJsonRequest([object]$req) {
        $headers = @{
            "Content-Type" = "application/json"
        }

        if ($this.ApiKey) {
            $headers["Authorization"] = "Bearer $($this.ApiKey)"
        }

        $url = "$($this.BaseUrl)$($req.path)"
        $body = $req.body | ConvertTo-Json -Depth 10 -Compress

        Invoke-RestMethod -Uri $url -Method $req.method `
            -Headers $headers -Body $body `
            -TimeoutSec 10 | Out-Null
    }

    hidden [void] UploadBatch([object]$req) {
        $headers = @{}

        if ($this.ApiKey) {
            $headers["Authorization"] = "Bearer $($this.ApiKey)"
        }

        $url = "$($this.BaseUrl)$($req.path)"

        # Build manifest and form
        $manifest = @()
        $form = @{}

        foreach ($fileInfo in $req.files) {
            if (-not (Test-Path $fileInfo.local_path)) {
                Write-Warning "File no longer exists: $($fileInfo.local_path)"
                continue
            }

            $manifest += @{
                path = $fileInfo.relative_path
                sha256 = $fileInfo.sha256
                size_bytes = $fileInfo.size_bytes
                content_type = $fileInfo.content_type
            }

            $form[$fileInfo.relative_path] = Get-Item $fileInfo.local_path
        }

        if ($form.Count -eq 0) {
            Write-Warning "No valid files to upload"
            return
        }

        $form.manifest = ($manifest | ConvertTo-Json -Compress)

        Invoke-RestMethod -Uri $url -Method Post `
            -Headers $headers -Form $form `
            -TimeoutSec 120 | Out-Null
    }
}

function Get-ContentType([string]$filename) {
    switch -Regex ($filename) {
        '\.md$'    { return "text/markdown" }
        '\.log$'   { return "text/plain; charset=utf-8" }
        '\.txt$'   { return "text/plain; charset=utf-8" }
        '\.patch$' { return "text/x-patch" }
        '\.json$'  { return "application/json" }
        default    { return "application/octet-stream" }
    }
}

function New-PluginReporter([hashtable]$config) {
    return [FastApiReporter]::new($config)
}
```

#### 3. Integrate with Felix Agent

**File:** `.felix/felix-agent.ps1` (modify)

Add at the top after sourcing other modules:

```powershell
# Load sync interface
. "$PSScriptRoot/core/sync-interface.ps1"

# Initialize sync reporter
$global:SyncReporter = Get-RunReporter -ConfigPath "$PSScriptRoot/config.json"

# Register agent on startup
if ($SyncReporter) {
    try {
        $SyncReporter.RegisterAgent(@{
            agent_id = if ($env:FELIX_AGENT_ID) { $env:FELIX_AGENT_ID } else { [guid]::NewGuid().ToString() }
            hostname = $env:COMPUTERNAME
            platform = "windows"
            version = "0.8.0"
            felix_root = $PSScriptRoot
        })
    }
    catch {
        Write-Warning "Failed to register agent: $_"
    }
}
```

### Testing Checkpoint

- [ ] Sync interface loads without errors
- [ ] NoOp reporter works (default behavior)
- [ ] FastAPI plugin loads when enabled
- [ ] Outbox directory created automatically
- [ ] Queue operations write .jsonl files
- [ ] TrySendOutbox successfully sends to backend
- [ ] Agent registration works via plugin

**Verification:**

```powershell
# Test interface loading
. .felix/core/sync-interface.ps1
$reporter = Get-RunReporter
Write-Host "Reporter type: $($reporter.GetType().Name)"

# Test with sync enabled
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "http://localhost:8080"

# Enable in config
$config = Get-Content .felix/config.json | ConvertFrom-Json
$config.sync.enabled = $true
$config | ConvertTo-Json -Depth 10 | Set-Content .felix/config.json

# Run agent and check outbox
.\.felix\felix-agent.ps1 C:\dev\felix

# Check outbox created
ls .felix\outbox\*.jsonl
```

### Rollback

```bash
# Remove sync files
rm .felix/core/sync-interface.ps1
rm .felix/plugins/sync-fastapi.ps1
rm -rf .felix/outbox/

# Restore felix-agent.ps1
git checkout .felix/felix-agent.ps1
```

---

## Phase 5: End-to-End Testing (2 days)

### Objectives

- Test complete flow: CLI → Outbox → Backend → Database → Storage
- Verify idempotency (re-run same data)
- Test failure scenarios (network down, invalid data)
- Performance test (100+ runs)

### Test Scenarios

#### 1. Happy Path Test

```powershell
# Setup
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "http://localhost:8080"

# Run a single requirement
.\.felix\felix.ps1 run S-0001

# Verify
ls .felix\outbox\  # Should be empty (sent successfully)

# Check backend
curl http://localhost:8080/api/runs | jq '.runs[] | select(.requirement_id == "S-0001")'

# Check database
psql -U postgres -d felix -c "
  SELECT r.id, r.requirement_id, r.status, COUNT(rf.id) as file_count
  FROM runs r
  LEFT JOIN run_files rf ON rf.run_id = r.id
  WHERE r.requirement_id = 'S-0001'
  GROUP BY r.id;
"

# Check storage
ls storage/runs/  # Should have project/run folders
```

#### 2. Idempotency Test

```powershell
# Run same requirement twice
.\.felix\felix.ps1 run S-0001  # First run
.\.felix\felix.ps1 run S-0001  # Second run

# Verify only new/changed files uploaded
psql -U postgres -d felix -c "
  SELECT path, sha256, updated_at
  FROM run_files
  WHERE run_id IN (
    SELECT id FROM runs WHERE requirement_id = 'S-0001'
    ORDER BY created_at DESC LIMIT 2
  );
"
```

#### 3. Network Failure Test

```powershell
# Stop backend
# (backend process killed)

# Run with backend down
.\.felix\felix.ps1 run S-0002

# Verify outbox has queued requests
ls .felix\outbox\*.jsonl  # Should have files

# Restart backend
cd app/backend; python main.py

# Run another requirement (triggers flush)
.\.felix\felix.ps1 run S-0003

# Verify outbox cleared
ls .felix\outbox\*.jsonl  # Should be empty

# Verify both runs in database
psql -U postgres -d felix -c "
  SELECT requirement_id, status FROM runs
  WHERE requirement_id IN ('S-0002', 'S-0003');
"
```

#### 4. Large File Test

```powershell
# Create large output file
$largeContent = "x" * (5 * 1024 * 1024)  # 5MB
Set-Content -Path "runs/test-large/output.log" -Value $largeContent

# Upload via reporter
$reporter = Get-RunReporter
$reporter.UploadRunFolder("test-run-large", "runs/test-large")
$reporter.Flush()

# Verify upload succeeded
curl http://localhost:8080/api/runs/test-run-large/files | jq '.files[] | select(.path == "output.log")'
```

### Performance Benchmarks

```powershell
# Benchmark: 100 runs
Measure-Command {
    1..100 | ForEach-Object {
        .\.felix\felix.ps1 run S-0001
    }
}

# Benchmark: Batch upload vs individual
# (Compare old approach with new batch approach)
```

### Testing Checkpoint

- [ ] Happy path works end-to-end
- [ ] Idempotency prevents duplicate uploads
- [ ] Network failures queue requests properly
- [ ] Large files (>5MB) upload successfully
- [ ] 100+ runs complete without errors
- [ ] Database has correct counts and relationships
- [ ] Storage has all artifacts accessible

### Rollback

N/A - test phase only

---

## Phase 6: Frontend Integration (3 days)

### Objectives

- Add API client methods for sync endpoints
- Create run detail component with file viewer
- Add event timeline component
- Implement SSE streaming (optional - can defer to Phase 7)

### Steps

#### 1. Update API Client

**File:** `app/frontend/services/felixApi.ts`

Add these interfaces and methods:

```typescript
export interface RunFile {
  path: string;
  kind: "artifact" | "log";
  size_bytes: number;
  sha256?: string;
  content_type?: string;
  updated_at: string;
}

export interface RunEvent {
  id: number;
  ts: string;
  type: string;
  level: "info" | "warn" | "error" | "debug";
  message?: string;
  payload?: any;
}

// Add to felixApi object:
async getRunFiles(runId: string): Promise<{ run_id: string; files: RunFile[] }> {
  const response = await fetch(`${API_BASE_URL}/api/runs/${runId}/files`);
  if (!response.ok) throw new Error("Failed to fetch run files");
  return response.json();
},

async getRunFile(runId: string, filePath: string): Promise<string> {
  const response = await fetch(
    `${API_BASE_URL}/api/runs/${runId}/files/${encodeURIComponent(filePath)}`
  );
  if (!response.ok) throw new Error(`Failed to fetch file: ${filePath}`);
  return response.text();
},

async getRunEvents(
  runId: string,
  after?: number
): Promise<{ run_id: string; events: RunEvent[]; has_more: boolean }> {
  const url = new URL(`${API_BASE_URL}/api/runs/${runId}/events`);
  if (after !== undefined) url.searchParams.set("after", after.toString());

  const response = await fetch(url.toString());
  if (!response.ok) throw new Error("Failed to fetch run events");
  return response.json();
}
```

#### 2. Create Run Detail Component (stub for now)

**File:** `app/frontend/components/RunDetail.tsx`

```typescript
import React, { useState, useEffect } from 'react';
import { felixApi, RunFile, RunEvent } from '../services/felixApi';

interface RunDetailProps {
  runId: string;
  onClose: () => void;
}

export const RunDetail: React.FC<RunDetailProps> = ({ runId, onClose }) => {
  const [files, setFiles] = useState<RunFile[]>([]);
  const [selectedFile, setSelectedFile] = useState<string | null>(null);
  const [fileContent, setFileContent] = useState<string>('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!runId) return;

    setLoading(true);
    felixApi.getRunFiles(runId)
      .then(data => {
        setFiles(data.files);
        // Auto-select report.md
        const report = data.files.find(f => f.path === 'report.md');
        if (report) setSelectedFile(report.path);
      })
      .catch(console.error)
      .finally(() => setLoading(false));
  }, [runId]);

  useEffect(() => {
    if (!runId || !selectedFile) return;

    felixApi.getRunFile(runId, selectedFile)
      .then(content => setFileContent(content))
      .catch(console.error);
  }, [runId, selectedFile]);

  if (loading) {
    return <div>Loading...</div>;
  }

  return (
    <div style={{ display: 'flex', height: '100%' }}>
      {/* File list */}
      <div style={{ width: '200px', borderRight: '1px solid #ccc', padding: '10px' }}>
        <h3>Artifacts</h3>
        {files.map(file => (
          <div
            key={file.path}
            onClick={() => setSelectedFile(file.path)}
            style={{
              padding: '5px',
              cursor: 'pointer',
              background: selectedFile === file.path ? '#e0e0e0' : 'transparent'
            }}
          >
            {file.path}
          </div>
        ))}
      </div>

      {/* File content */}
      <div style={{ flex: 1, padding: '20px', overflow: 'auto' }}>
        {selectedFile && (
          <>
            <h2>{selectedFile}</h2>
            <pre>{fileContent}</pre>
          </>
        )}
      </div>
    </div>
  );
};
```

### Testing Checkpoint

- [ ] API methods fetch data correctly
- [ ] Run detail component renders
- [ ] File list displays all artifacts
- [ ] Selected file content displays
- [ ] Large files don't freeze UI

**Verification:**

```bash
# Start frontend
cd app/frontend
npm run dev

# Navigate to run detail
# http://localhost:3000 (with a valid run ID)
```

### Rollback

```bash
git checkout app/frontend/services/felixApi.ts
rm app/frontend/components/RunDetail.tsx
```

---

## Phase 7: Production Readiness (3 days)

### Objectives

- Add proper error handling and logging
- Implement retry logic with exponential backoff
- Add monitoring/metrics
- Write operations documentation
- Security review

### Tasks

1. **Error Handling**
   - Backend: Structured error responses
   - CLI: Graceful degradation when sync fails
   - Frontend: User-friendly error messages

2. **Logging**
   - Backend: Structured logs for sync operations
   - CLI: Verbose mode for debugging sync
   - Metrics: Track sync success/failure rates

3. **Documentation**
   - Update AGENTS.md with sync troubleshooting
   - Add sync configuration examples
   - Document outbox format for debugging

4. **Security**
   - API key rotation procedure
   - Rate limiting on sync endpoints
   - Input validation for all endpoints

### Testing Checkpoint

- [ ] All error cases handled gracefully
- [ ] Logs provide actionable debugging info
- [ ] Documentation complete and accurate
- [ ] Security review passed

---

## Rollout Plan

### Week 1: Opt-In Beta

- Enable sync on 1 developer machine
- Monitor for issues
- Collect feedback

### Week 2: Team Rollout

- Enable sync for all team members (opt-in)
- CI/CD agents enabled
- Verify no disruption to workflows

### Week 3: Default On

- Make sync default (can still disable)
- Monitor system load
- Tune performance if needed

### Week 4: Deprecate Legacy

- Remove old filesystem-only code paths
- Update all documentation
- Celebrate launch! 🎉

---

## Success Criteria

- [ ] Agent can register with backend
- [ ] Run lifecycle tracked in database
- [ ] Artifacts uploaded and retrievable
- [ ] Events timeline visible in UI
- [ ] Idempotent uploads (no duplicates)
- [ ] Works offline (queues for later)
- [ ] < 10% overhead on run time
- [ ] Zero data loss
- [ ] Team using it daily

---

## Rollback Procedures

### Emergency Rollback (Production Down)

```bash
# Disable sync globally
export FELIX_SYNC_ENABLED=false

# Or in config
jq '.sync.enabled = false' .felix/config.json > tmp && mv tmp .felix/config.json

# Backend: Remove sync router registration
git revert <sync-router-commit>

# Database: No rollback needed (backward compatible)
```

### Partial Rollback (Issues with Specific Feature)

- Disable file uploads only: Comment out batch upload in plugin
- Disable events only: Comment out event append in plugin
- Keep everything local: Set `sync.enabled = false`

---

## Estimated Timeline

| Phase                | Duration    | Dependencies | Risk   |
| -------------------- | ----------- | ------------ | ------ |
| Phase 0: Preparation | 1 day       | None         | Low    |
| Phase 1: Database    | 2 days      | Phase 0      | Low    |
| Phase 2: Storage     | 2 days      | Phase 1      | Medium |
| Phase 3: Backend API | 3 days      | Phase 1, 2   | Medium |
| Phase 4: CLI Plugin  | 3 days      | Phase 3      | Medium |
| Phase 5: E2E Testing | 2 days      | Phase 4      | Low    |
| Phase 6: Frontend    | 3 days      | Phase 3      | Low    |
| Phase 7: Production  | 3 days      | All phases   | High   |
| **Total**            | **19 days** |              |        |

**Note:** Timeline assumes 1 developer working full-time. Can parallelize Phases 4 & 6 with 2 developers to save 3 days.

---

## Next Steps

1. **Review this plan** with team
2. **Create tracking tickets** for each phase
3. **Set up test environment** (separate DB for testing)
4. **Begin Phase 0** - Preparation
5. **Daily standups** to track progress

---

## Support & Questions

- **Documentation**: See [runs_migration.md](runs_migration.md) for architecture details
- **Issues**: Create GitHub issue with `sync` label
- **Questions**: Ask in team chat or weekly sync meeting
