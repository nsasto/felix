# Run Artifact Sync - Production Implementation

**Version:** 1.0.0  
**Status:** ✅ Production Ready  
**Last Updated:** 2026-02-18

---

## Executive Summary

The Run Artifact Sync system enables Felix CLI agents to mirror run data (events, status, artifacts) to a central backend server for team visibility, audit trails, and collaboration. The system maintains Felix's **local-first philosophy** - all operations work offline, sync is optional and gracefully degrades on failure.

**Key Achievements:**

- ✅ **Plugin Architecture**: Hook-based lifecycle integration (OnPreIteration, OnEvent, OnRunComplete, etc.)
- ✅ **Event Batching**: 5-second heartbeat with background timer reduces backend load
- ✅ **Git URL Authentication**: Projects identified by git remote URL (no manual UUID config)
- ✅ **Idempotent Uploads**: SHA256-based file deduplication prevents duplicate storage
- ✅ **Outbox Queue**: Eventual consistency via retry queue (.felix/outbox/\*.jsonl)
- ✅ **Zero Runtime Dependency**: Local operations never blocked by sync failures

---

## Architecture Overview

### Design Principles

1. **Local First**: CLI always writes to local filesystem first; sync is secondary
2. **Graceful Degradation**: Network failures don't break runs (queue for retry)
3. **Event-Driven**: Plugin hooks observe lifecycle, core executor remains clean
4. **Secure by Default**: API keys scoped to single project, git URL validation prevents misuse
5. **Zero Config (Almost)**: Git remote URL auto-discovered, only API key needed

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│  Felix CLI Agent (.felix/ directory)                         │
│                                                              │
│  ┌──────────────┐    Hook Events    ┌──────────────────┐   │
│  │   Core       │───────────────────>│  Sync Plugin     │   │
│  │   Executor   │                    │  (sync-http)     │   │
│  │              │                    │                  │   │
│  │  • Runs      │                    │  • Queue Events  │   │
│  │  • Plans     │                    │  • Batch Send    │   │
│  │  • Commits   │                    │  • Upload Files  │   │
│  └──────────────┘                   └────────┬─────────┘   │
│                                                │             │
│                                                │ HTTP/REST   │
└────────────────────────────────────────────────┼─────────────┘
                                                 │
                                                 ▼
                        ┌─────────────────────────────────────┐
                        │  Backend API (FastAPI)              │
                        │                                     │
                        │  • /api/runs (create/finish)        │
                        │  • /api/runs/{id}/events (batch)    │
                        │  • /api/runs/{id}/files (upload)    │
                        │                                     │
                        └──────────┬──────────────────────────┘
                                   │
                   ┌───────────────┴───────────────┐
                   │                               │
                   ▼                               ▼
        ┌──────────────────┐          ┌──────────────────────┐
        │  PostgreSQL      │          │  Storage Backend     │
        │                  │          │  (filesystem/S3)     │
        │  • runs          │          │                      │
        │  • run_events    │          │  • artifacts/*.md    │
        │  • run_files     │          │  • logs/*.log        │
        │  • agents        │          │  • diffs/*.patch     │
        └──────────────────┘          └──────────────────────┘
```

---

## Plugin Architecture

### Hook-Based Integration

The sync system uses Felix's plugin architecture with lifecycle hooks:

| Hook                     | Trigger                          | Purpose                                                                            |
| ------------------------ | -------------------------------- | ---------------------------------------------------------------------------------- |
| **OnPreIteration**       | First iteration only             | Initialize HTTP client, register agent, create run record, start event flush timer |
| **OnEvent**              | Every event emission             | Queue events for batch sending (flush immediately for errors)                      |
| **OnPostModeSelection**  | Mode changes (planning↔building) | Update run status (throttled to max 1/sec)                                         |
| **OnBackpressureFailed** | Validation/test failures         | Queue validation_failed event, force status update                                 |
| **OnRunComplete**        | Run finishes (success/failure)   | Flush events, mark run complete, upload artifacts, stop timer                      |

### Plugin Discovery and Configuration

**Plugin Manifest** (`plugins/sync-http/plugin.json`):

```json
{
  "id": "sync-http",
  "name": "HTTP Sync Plugin",
  "version": "1.0.0",
  "api_version": "v1",
  "hooks": [
    {
      "name": "OnPreIteration",
      "type": "powershell",
      "script": "on-prediteration.ps1"
    },
    {
      "name": "OnEvent",
      "type": "powershell",
      "script": "on-event.ps1"
    },
    {
      "name": "OnPostModeSelection",
      "type": "powershell",
      "script": "on-postmodeselection.ps1"
    },
    {
      "name": "OnBackpressureFailed",
      "type": "powershell",
      "script": "on-backpressurefailed.ps1"
    },
    {
      "name": "OnRunComplete",
      "type": "powershell",
      "script": "on-runcomplete.ps1"
    }
  ],
  "config": {
    "event_batch_interval": 5,
    "status_throttle_ms": 1000,
    "retry_attempts": 3
  }
}
```

**Felix Configuration** (`.felix/config.json`):

```json
{
  "sync": {
    "enabled": true,
    "provider": "http",
    "base_url": "http://localhost:8080",
    "api_key": "fsk_51d8e1482650cd3f595353e0ed6774de59baf0e3ca4c552db82e95398cb70e11"
  },
  "plugins": {
    "enabled": true,
    "discovery_path": ".felix/plugins"
  }
}
```

**Environment Variables** (override config file):

```powershell
# Windows PowerShell
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "https://felix.example.com"
$env:FELIX_SYNC_KEY = "fsk_your_api_key_here"

# Linux/macOS
export FELIX_SYNC_ENABLED=true
export FELIX_SYNC_URL=https://felix.example.com
export FELIX_SYNC_KEY=fsk_your_api_key_here
```

---

## Authentication & Security

### Git URL-Based Project Identity

**Eliminates manual project configuration** by using git remote URL as project identifier:

1. **CLI extracts git URL** on run start:

   ```powershell
   $gitUrl = git config --get remote.origin.url
   # Example: "git@github.com:owner/repo.git"
   ```

2. **CLI sends git URL in RunCreate request**:

   ```json
   POST /api/runs
   {
     "agent_id": "550e8400-e29b-41d4-a716-446655440000",
     "requirement_id": "S-0058",
     "git_url": "git@github.com:owner/repo.git"
   }
   ```

3. **Backend normalizes URLs for comparison**:

   ```python
   # Converts SSH to HTTPS, removes .git, lowercases domain
   "git@github.com:owner/repo.git" → "https://github.com/owner/repo"
   "https://github.com/Owner/Repo/" → "https://github.com/owner/repo"
   ```

4. **Backend validates git URL matches API key's project**:
   ```python
   key_project = get_project_from_api_key(api_key)
   if normalize_git_url(key_project.git_url) != normalize_git_url(request.git_url):
       raise HTTPException(403, "Git URL mismatch")
   ```

**Security Benefits:**

- ✅ **Auto-discovery**: No manual project UUID in CLI config
- ✅ **Key scoping**: API key prevents usage in wrong git repository
- ✅ **Machine portability**: Same git remote URL → same project across machines
- ✅ **Zero-trust**: Backend validates all requests, clients cannot forge project_id

### API Key Management

**Key Format:** `fsk_` + 64 hex characters (256-bit entropy)

**Key Properties:**

- **Project-scoped**: Each key authenticates to exactly ONE project
- **SHA256 hashed**: Plain-text shown only once at generation
- **Expirable**: Optional expiration (30/90/180/365 days or never)
- **Revocable**: Immediate via UI or API

**Generating Keys:**

```bash
# Via UI: Project Settings → API Keys → Generate New Key
# Via API:
curl -X POST "http://localhost:8080/api/projects/{project_id}/keys" \
  -H "Authorization: Bearer {user_token}" \
  -d '{"name": "CI Pipeline", "expires_days": 365}'
```

**Authentication Flow:**

```
CLI Request → Backend extracts Bearer token
           → SHA256 hash token
           → Lookup in api_keys table
           → Get project_id from key
           → Validate git_url matches project
           → Authorize operation
```

---

## Event Batching & Status Updates

### Event Batching (Heartbeat Proxy)

**Problem:** Sending 1 HTTP request per event creates network overhead and backend load.

**Solution:** Batch events in memory, flush every 5 seconds via background timer.

**Implementation:**

- **In-Memory Queue**: Events added to `$Global:HttpSyncState.EventQueue`
- **Background Timer**: PowerShell timer flushes queue every 5 seconds
- **Immediate Flush**: Critical events (errors, validation failures) bypass batching
- **Batch API**: `POST /api/runs/{run_id}/events` accepts array of events

**Example Event Batch:**

```json
POST /api/runs/{run_id}/events
{
  "events": [
    {"ts": "2026-02-18T10:00:05Z", "type": "task_started", "level": "info", "message": "Starting task 1.2"},
    {"ts": "2026-02-18T10:00:42Z", "type": "task_completed", "level": "info", "message": "Task 1.2 complete"},
    {"ts": "2026-02-18T10:01:03Z", "type": "heartbeat", "level": "debug"}
  ]
}
```

### Status Throttling

**Problem:** Mode changes and task updates can trigger status updates multiple times per second.

**Solution:** Throttle to max 1 status update per second.

**Implementation:**

- Track last status update timestamp in `$Global:HttpSyncState.LastStatusUpdate`
- Skip status updates if < 1000ms since last update
- Critical events (errors, completion) bypass throttle

---

## Database Schema

### Tables

#### runs

Extended from baseline schema with sync-specific columns:

```sql
CREATE TABLE runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    agent_id UUID NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    requirement_id UUID REFERENCES requirements(id) ON DELETE SET NULL,
    org_id UUID REFERENCES organizations(id) ON DELETE SET NULL,

    -- Status and timing
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending', 'running', 'completed', 'failed', 'cancelled',
        'succeeded', 'stopped', 'queued', 'rejected', 'blocked'
    )),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Run metadata
    phase TEXT,                    -- 'planning', 'building', etc.
    scenario TEXT,                 -- Run scenario identifier
    branch TEXT,                   -- Git branch
    commit_sha TEXT,               -- Git commit at run start
    error TEXT,                    -- Legacy error field
    error_summary TEXT,            -- Structured error summary
    summary_json JSONB DEFAULT '{}',
    duration_sec INTEGER,
    exit_code INTEGER,
    metadata JSONB DEFAULT '{}'
);
```

#### run_events

Timeline of events during run execution:

```sql
CREATE TABLE run_events (
    id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    level TEXT NOT NULL CHECK (level IN ('info', 'warn', 'error', 'debug')),
    type TEXT NOT NULL CHECK (type IN (
        'started', 'plan_loaded', 'task_started', 'task_completed',
        'validation_started', 'validation_passed', 'validation_failed',
        'completed', 'failed', 'cancelled', 'heartbeat'
    )),
    message TEXT,
    payload JSONB
);

CREATE INDEX idx_run_events_run_ts ON run_events(run_id, ts DESC);
CREATE INDEX idx_run_events_type_ts ON run_events(type, ts DESC);
CREATE INDEX idx_run_events_level_ts ON run_events(level, ts DESC) WHERE level IN ('error', 'warn');
```

#### run_files

Metadata for uploaded artifacts (content stored in storage backend):

```sql
CREATE TABLE run_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    path TEXT NOT NULL,            -- Relative path within run (e.g., "plan.md")
    kind TEXT NOT NULL CHECK (kind IN ('artifact', 'log')),
    size_bytes INTEGER NOT NULL,
    sha256 TEXT NOT NULL,          -- For deduplication
    content_type TEXT NOT NULL,    -- MIME type
    storage_key TEXT NOT NULL,     -- Storage backend key
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(run_id, path)
);

CREATE INDEX idx_run_files_run_id ON run_files(run_id);
CREATE INDEX idx_run_files_sha256 ON run_files(sha256);
```

#### agents

Extended with registration metadata:

```sql
ALTER TABLE agents
    ADD COLUMN hostname TEXT,
    ADD COLUMN platform TEXT,      -- 'windows', 'linux', 'macos'
    ADD COLUMN version TEXT,        -- Felix version
    ADD COLUMN last_seen_at TIMESTAMPTZ DEFAULT NOW(),
    ALTER COLUMN project_id DROP NOT NULL;  -- Allow registration before project assignment
```

### Indexes

```sql
-- Run queries
CREATE INDEX idx_runs_org_project_created ON runs(org_id, project_id, created_at DESC);
CREATE INDEX idx_runs_project_requirement_created ON runs(project_id, requirement_id, created_at DESC);
CREATE INDEX idx_runs_agent_created ON runs(agent_id, created_at DESC);
CREATE INDEX idx_runs_status_created ON runs(status, created_at DESC);

-- Agent queries
CREATE INDEX idx_agents_last_seen ON agents(status, last_seen_at DESC);
```

---

## API Endpoints

### Run Lifecycle

#### POST /api/runs

Create new run record.

**Request:**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000", // Optional, generated if omitted
  "agent_id": "agent-uuid",
  "requirement_id": "S-0058",
  "git_url": "git@github.com:owner/repo.git", // Required for authentication
  "branch": "feature/sync",
  "commit_sha": "abc123def456",
  "phase": "planning",
  "scenario": "auto"
}
```

**Response:**

```json
{
  "run_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "created"
}
```

**Validation:**

- API key required (`Authorization: Bearer fsk_...`)
- Git URL must match API key's project (normalized comparison)
- Agent must exist or be auto-registered
- Idempotent: repeated calls with same ID update metadata

#### POST /api/runs/{run_id}/events

Append events to run timeline (batch operation).

**Request:**

```json
{
  "events": [
    {
      "ts": "2026-02-18T10:00:05.123Z",
      "type": "task_started",
      "level": "info",
      "message": "Starting task: Add input validation",
      "payload": { "task_id": "1.2", "title": "Add input validation" }
    },
    {
      "ts": "2026-02-18T10:00:42.789Z",
      "type": "task_completed",
      "level": "info",
      "message": "Task complete: Add input validation",
      "payload": { "task_id": "1.2", "duration_sec": 37 }
    }
  ]
}
```

**Response:**

```json
{
  "run_id": "550e8400-e29b-41d4-a716-446655440000",
  "inserted": 2,
  "status": "ok"
}
```

#### POST /api/runs/{run_id}/finish

Mark run as complete/failed.

**Request:**

```json
{
  "status": "succeeded", // or "failed", "cancelled"
  "exit_code": 0,
  "duration_sec": 127,
  "error_summary": null,
  "summary_json": {
    "tasks_completed": 3,
    "files_changed": 5
  }
}
```

**Response:**

```json
{
  "run_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "succeeded",
  "finished_at": "2026-02-18T10:02:15.456Z"
}
```

### Artifact Management

#### POST /api/runs/{run_id}/files

Batch upload artifacts (multipart/form-data).

**Request (manifest-first approach):**

```json
POST /api/runs/{run_id}/files
Content-Type: multipart/form-data

--boundary
Content-Disposition: form-data; name="manifest"

{
  "files": [
    {
      "path": "plan.md",
      "sha256": "abc123...",
      "size_bytes": 1024,
      "content_type": "text/markdown"
    },
    {
      "path": "diff.patch",
      "sha256": "def456...",
      "size_bytes": 2048,
      "content_type": "text/x-patch"
    }
  ]
}

--boundary
Content-Disposition: form-data; name="plan.md"; filename="plan.md"
Content-Type: text/markdown

# Plan content here...

--boundary
Content-Disposition: form-data; name="diff.patch"; filename="diff.patch"
Content-Type: text/x-patch

diff --git a/file.py b/file.py
...
```

**Response:**

```json
{
  "run_id": "550e8400-e29b-41d4-a716-446655440000",
  "files": [
    { "path": "plan.md", "status": "uploaded", "size_bytes": 1024 },
    {
      "path": "diff.patch",
      "status": "skipped",
      "size_bytes": 2048,
      "reason": "unchanged"
    }
  ],
  "total": 2,
  "uploaded": 1,
  "skipped": 1
}
```

**Deduplication:**

- Backend checks `run_files.sha256` before accepting upload
- If file with same SHA256 exists for this run, skip upload (idempotent)
- Storage backend may deduplicate at storage layer (content-addressed)

#### GET /api/runs/{run_id}/files

List artifacts for a run.

**Response:**

```json
{
  "run_id": "550e8400-e29b-41d4-a716-446655440000",
  "files": [
    {
      "path": "plan.md",
      "kind": "artifact",
      "size_bytes": 1024,
      "sha256": "abc123...",
      "content_type": "text/markdown",
      "updated_at": "2026-02-18T10:02:15.456Z"
    }
  ]
}
```

#### GET /api/runs/{run_id}/files/{path:path}

Download artifact content.

**Response:** Raw file content with appropriate Content-Type header.

---

## Storage Backend

### Abstraction Layer

```python
# app/backend/storage.py
class ArtifactStorage(Protocol):
    async def store_artifact(
        self, run_id: str, file_path: str, content: bytes
    ) -> str:
        """Store artifact, return storage key"""
        ...

    async def get_artifact(self, storage_key: str) -> bytes:
        """Retrieve artifact by storage key"""
        ...

    async def delete_artifact(self, storage_key: str) -> None:
        """Delete artifact (for cleanup)"""
        ...
```

### Filesystem Backend (Default)

```python
class FilesystemStorage:
    def __init__(self, base_path: str):
        self.base_path = Path(base_path)  # e.g., "storage/runs"

    async def store_artifact(self, run_id: str, file_path: str, content: bytes) -> str:
        # Storage key: runs/{run_id}/{file_path}
        storage_key = f"runs/{run_id}/{file_path}"
        full_path = self.base_path / storage_key
        full_path.parent.mkdir(parents=True, exist_ok=True)
        full_path.write_bytes(content)
        return storage_key
```

**Directory Structure:**

```
storage/
└── runs/
    ├── 550e8400-e29b-41d4-a716-446655440000/
    │   ├── plan.md
    │   ├── diff.patch
    │   ├── output.log
    │   └── report.md
    └── 660f9511-f3ac-52e5-b827-557766551111/
        └── ...
```

### S3 Backend (Future)

```python
class S3Storage:
    def __init__(self, bucket: str, prefix: str):
        self.s3 = boto3.client('s3')
        self.bucket = bucket
        self.prefix = prefix

    async def store_artifact(self, run_id: str, file_path: str, content: bytes) -> str:
        storage_key = f"{self.prefix}/runs/{run_id}/{file_path}"
        self.s3.put_object(Bucket=self.bucket, Key=storage_key, Body=content)
        return storage_key
```

**Configuration:**

```bash
# .env
STORAGE_TYPE=s3
STORAGE_S3_BUCKET=felix-artifacts
STORAGE_S3_PREFIX=production
AWS_REGION=us-west-2
```

---

## Outbox Queue & Retry Logic

### Outbox Pattern

**Problem:** Network failures during sync shouldn't break runs.

**Solution:** Queue failed requests to `.felix/outbox/` directory for later retry.

**Format:** NDJSON (newline-delimited JSON) files

```
.felix/outbox/
├── sync_20260218_100215_abc123.jsonl
├── sync_20260218_100230_def456.jsonl
└── sync_20260218_100245_ghi789.jsonl
```

**File Content (NDJSON):**

```jsonl
{"method":"POST","endpoint":"/api/runs/550e8400-e29b-41d4-a716-446655440000/events","body":{"events":[{"ts":"...","type":"task_started","level":"info"}]},"timestamp":"2026-02-18T10:02:15.456Z","retry_count":0}
{"method":"POST","endpoint":"/api/runs/550e8400-e29b-41d4-a716-446655440000/events","body":{"events":[{"ts":"...","type":"task_completed","level":"info"}]},"timestamp":"2026-02-18T10:02:42.789Z","retry_count":0}
```

### Retry Logic

```powershell
# Exponential backoff with max 5 attempts
$maxRetries = $env:FELIX_SYNC_MAX_RETRIES ?? 5
$delays = @(1, 2, 4, 8, 16)  # seconds

for ($i = 0; $i -lt $maxRetries; $i++) {
    try {
        Send-HttpRequest -Method $request.method -Endpoint $request.endpoint -Body $request.body
        # Success - delete from outbox
        Remove-Item $outboxFile
        break
    }
    catch {
        if (Is-PermanentError $_) {
            # 400, 401, 403, 404 - don't retry
            Remove-Item $outboxFile
            break
        }

        if ($i -lt $maxRetries - 1) {
            # Transient error (503, network) - retry with backoff
            Start-Sleep -Seconds $delays[$i]
        }
    }
}
```

**Error Classification:**

| Status Code               | Type      | Retry?                            |
| ------------------------- | --------- | --------------------------------- |
| 400 Bad Request           | Permanent | ❌ No (malformed request)         |
| 401 Unauthorized          | Permanent | ❌ No (invalid API key)           |
| 403 Forbidden             | Permanent | ❌ No (git URL mismatch)          |
| 404 Not Found             | Permanent | ❌ No (run/agent doesn't exist)   |
| 429 Too Many Requests     | Transient | ✅ Yes (rate limit, wait + retry) |
| 500 Internal Server Error | Permanent | ❌ No (backend bug)               |
| 503 Service Unavailable   | Transient | ✅ Yes (DB/storage down)          |
| Network Error             | Transient | ✅ Yes (connection failed)        |

---

## Configuration Reference

### Complete Config Example

```json
{
  "version": "0.1.0",
  "executor": {
    "mode": "local",
    "max_iterations": 100,
    "default_mode": "planning",
    "commit_on_complete": true
  },
  "agent": {
    "agent_id": "550e8400-e29b-41d4-a716-446655440000"
  },
  "sync": {
    "enabled": true,
    "provider": "http",
    "base_url": "http://localhost:8080",
    "api_key": "fsk_51d8e1482650cd3f595353e0ed6774de59baf0e3ca4c552db82e95398cb70e11"
  },
  "plugins": {
    "enabled": true,
    "discovery_path": ".felix/plugins",
    "api_version": "v1",
    "disabled": ["prompt-enhancer", "metrics-collector"]
  }
}
```

### Environment Variables

| Variable                     | Description                 | Default |
| ---------------------------- | --------------------------- | ------- |
| `FELIX_SYNC_ENABLED`         | Enable/disable sync         | `false` |
| `FELIX_SYNC_URL`             | Backend base URL            | none    |
| `FELIX_SYNC_KEY`             | API key (fsk\_...)          | none    |
| `FELIX_SYNC_MAX_RETRIES`     | Max retry attempts          | `5`     |
| `FELIX_SYNC_FEATURE_ENABLED` | Global backend feature flag | `true`  |

---

## Testing & Validation

### Unit Tests

```powershell
# Backend tests
cd app/backend
pytest tests/test_sync_endpoints.py -v

# Expected output:
# test_create_run_with_git_url ✓
# test_append_events_batch ✓
# test_upload_files_idempotent ✓
# test_unauthorized_without_api_key ✓
# test_git_url_mismatch_403 ✓
```

### Integration Tests

```powershell
# Run Felix agent with sync enabled (dev backend)
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "http://localhost:8080"
$env:FELIX_SYNC_KEY = "fsk_..."

.\felix\felix-agent.ps1 C:\dev\felix

# Expected console output:
# [10:00:15.123] INFO [sync] Sync enabled → http://localhost:8080
# [10:00:15.456] INFO [sync] Agent registered successfully
# [10:00:15.789] INFO [sync] Run started: 550e8400-e29b-41d4-a716-446655440000
# [10:02:30.000] INFO [sync] Run complete: uploaded 5 files
```

### Validation Checks

```powershell
# 1. Verify outbox is empty (all sent successfully)
Get-ChildItem .felix\outbox\*.jsonl
# Expected: 0 files

# 2. Query backend for run
curl http://localhost:8080/api/runs?limit=1 | ConvertFrom-Json
# Expected: Run record with correct requirement_id

# 3. Check events timeline
curl http://localhost:8080/api/runs/550e8400-e29b-41d4-a716-446655440000/events | ConvertFrom-Json
# Expected: Array of events (started, task_started, task_completed, completed)

# 4. Verify artifacts uploaded
curl http://localhost:8080/api/runs/550e8400-e29b-41d4-a716-446655440000/files | ConvertFrom-Json
# Expected: Files array with plan.md, diff.patch, report.md
```

---

## Troubleshooting

### Sync Not Working

**Symptom:** No data appearing in backend, but run completes locally.

**Diagnosis:**

```powershell
# 1. Check sync enabled
Get-Content .felix\config.json | ConvertFrom-Json | Select-Object -ExpandProperty sync

# 2. Check outbox for queued requests
Get-ChildItem .felix\outbox\*.jsonl

# 3. Check sync log for errors
Get-Content .felix\sync.log -Tail 50
```

**Common Causes:**

- `sync.enabled = false` in config
- Missing or invalid API key (401/403 errors in log)
- Backend not running (connection refused)
- Git URL mismatch (403 error - key scoped to different project)

### Events Not Appearing

**Symptom:** Run created, but no events in timeline.

**Cause:** Events batched but not flushed (background timer not started or agent crashed before flush).

**Fix:** Events flush every 5 seconds during run. Check:

```powershell
# Verify flush timer started
Select-String -Path .felix\sync.log -Pattern "event flush timer"

# Check for queued events
Select-String -Path .felix\outbox\*.jsonl -Pattern "events"
```

### Artifacts Not Uploading

**Symptom:** Run complete, but files missing from backend.

**Cause:** Artifact upload happens in OnRunComplete hook. If agent crashes/exits early, upload skipped.

**Fix:**

```powershell
# Manual retry: re-upload artifacts for a run
.\scripts\retry-artifact-upload.ps1 -RunId "550e8400-..." -RunDir "runs\S-0058-20260218-100215-it1"
```

### Git URL Mismatch (403)

**Symptom:** `403 Forbidden: Git URL mismatch` error.

**Cause:** API key scoped to project A, trying to sync from project B.

**Fix:**

1. Verify git remote URL matches project:

   ```powershell
   git config --get remote.origin.url
   # Compare with project's git_url in backend
   ```

2. Generate new API key for correct project (or use correct key for current project)

---

## Migration Path

### From Local-Only to Synced

**Prerequisites:**

- Backend running with database migrated to 015+
- Project registered in backend with git_url
- API key generated for project

**Steps:**

1. **Update config:**

   ```json
   {
     "sync": {
       "enabled": true,
       "provider": "http",
       "base_url": "https://felix.example.com",
       "api_key": "fsk_..."
     }
   }
   ```

2. **Verify git remote:**

   ```powershell
   git config --get remote.origin.url
   # Must match project.git_url in backend
   ```

3. **Test connection:**

   ```powershell
   $env:FELIX_SYNC_ENABLED = "true"
   $env:FELIX_SYNC_URL = "https://felix.example.com"
   $env:FELIX_SYNC_KEY = "fsk_..."

   .\felix\felix-agent.ps1 --dry-run
   # Should show "Sync enabled → https://felix.example.com"
   ```

4. **Run with sync:**
   ```powershell
   .\felix\felix-agent.ps1 C:\dev\myproject
   ```

### Rollback to Local-Only

**Emergency disable:**

```powershell
# Disable via environment
$env:FELIX_SYNC_ENABLED = "false"

# Or edit config
$config = Get-Content .felix\config.json | ConvertFrom-Json
$config.sync.enabled = $false
$config | ConvertTo-Json | Set-Content .felix\config.json
```

**No data loss:** All runs still written to local `runs/` directory. Sync is additive.

---

## Performance Characteristics

### Benchmarks (Local Network)

| Operation                              | Latency | Throughput |
| -------------------------------------- | ------- | ---------- |
| Create run                             | ~50ms   | 20 req/sec |
| Append events (batch of 10)            | ~30ms   | 33 req/sec |
| Upload artifacts (5 files, 10KB total) | ~200ms  | 5 req/sec  |
| Finish run                             | ~40ms   | 25 req/sec |

### Optimization Techniques

1. **Event Batching**: Reduces HTTP requests by 10-20x
2. **Status Throttling**: Prevents status update storms (max 1/sec)
3. **Deduplication**: SHA256 check skips unchanged file uploads
4. **Async I/O**: Backend uses async database + storage operations
5. **Connection Pooling**: HTTP client reuses connections

### Scaling Considerations

**Single Backend Server:**

- ~50 concurrent agents (event batching reduces load)
- ~1000 runs/day with 5KB avg artifacts each = ~5MB/day storage

**Bottlenecks:**

- Database writes (runs, events, run_files inserts)
- Storage backend I/O (artifact writes)
- Network bandwidth (large artifacts from many agents)

**Scaling Strategies:**

- **Database**: Read replicas for queries, write to primary
- **Storage**: S3/object storage instead of filesystem
- **Load Balancer**: Horizontal scaling with multiple backend instances
- **Rate Limiting**: Prevent abuse (100 req/min per API key)

---

## Future Enhancements

### Planned Features

- **WebSocket Event Streaming**: Real-time event stream to UI (replace polling)
- **Artifact Compression**: Gzip artifacts before upload (reduce bandwidth)
- **Incremental Diffs**: Only upload changed file portions for large files
- **Retention Policies**: Auto-delete old runs/artifacts after 90 days
- **Analytics Dashboard**: Run statistics, success rates, duration trends

### Extensibility Points

- **Storage Backends**: Azure Blob, GCS, MinIO
- **Authentication Methods**: OAuth, JWT tokens
- **Event Formats**: Custom event types, plugin-specific events
- **UI Customization**: Pluggable UI components for artifact viewers

---

## Related Documentation

- **[AGENTS.md](../AGENTS.md)**: Agent operations, sync configuration
- **[docs/SYNC_OPERATIONS.md](../docs/SYNC_OPERATIONS.md)**: Operational runbook, monitoring, troubleshooting
- **[.felix/plugins/sync-http/README.md](../.felix/plugins/sync-http/README.md)**: Plugin-specific documentation
- **[Enhancements/RUNS_BASELINE.md](./RUNS_BASELINE.md)**: Pre-sync baseline state

---

## Changelog

### v1.0.0 (2026-02-18)

- ✅ **Git URL Authentication**: Replaced manual project_id with git remote URL discovery
- ✅ **Database Migration 019**: Removed path column, made git_url mandatory
- ✅ **Plugin Architecture**: Hook-based lifecycle integration complete
- ✅ **Event Batching**: 5-second heartbeat with background timer
- ✅ **Idempotent Uploads**: SHA256-based deduplication
- ✅ **Outbox Queue**: Eventual consistency via retry queue
- ✅ **API Key Management**: Project-scoped keys with UI generation
- ✅ **Storage Abstraction**: Filesystem backend with S3 extensibility

### v0.8.0 (2026-02-16)

- ✅ **Database Schema**: Migration 015 (run_events, run_files tables)
- ✅ **Sync Endpoints**: POST /api/runs, POST /api/runs/{id}/events, POST /api/runs/{id}/files
- ✅ **Plugin Discovery**: Auto-load from .felix/plugins/ directory

### v0.7.0 (2026-02-15)

- ✅ **Initial Implementation**: Hook-based sync plugin
- ✅ **Local Write Module**: Core executor lifecycle hooks
- ✅ **Configuration**: .felix/config.json sync section

---

**Document Version:** 1.0.0  
**Last Updated:** 2026-02-18  
**Maintained By:** Felix Team
