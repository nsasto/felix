# Run Artifact Mirroring and Storage Migration

## Goal

Enable Felix local runner to push run status and artifacts to the server so teammates can view run history, logs, plans, diffs, and reports in a web UI. Keep Felix local and file-based. Server acts as an audit mirror and interrogation surface.

## Non-Goals

- Server does not execute runs
- Server does not require git access
- No attempt to make server the source of truth
- Local filesystem remains canonical; server is mirror/cache

## Architecture Principles

### Local First

- Runner always writes artifacts to local filesystem first
- Server sync is optional and can fail without breaking runs
- Outbox pattern ensures eventual consistency
- Plugin-based sync keeps core CLI clean

### Reliability

- HTTP ingest (not WebSocket) for runner → server communication
- Outbox queue with automatic retry on failure
- Idempotent endpoints (repeated uploads safe)
- SHA256 integrity checks for artifacts

### Separation of Concerns

- **Core CLI**: Writes local files, emits lifecycle events
- **Sync Plugin**: Observes events, pushes to server
- **Backend API**: Receives data, stores in DB + storage
- **Frontend**: Queries and renders via REST + SSE

---

## Phase 1: Plugin Architecture

### Core Interface

Create `.felix/core/sync-interface.ps1`:

```powershell
# Abstract interface - core calls these during execution
class IRunReporter {
    # Agent registration (once per session or daily)
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

# Default: does nothing
class NoOpReporter : IRunReporter { }

# Factory: loads from config
function Get-RunReporter {
    $config = Get-FelixConfig
    if (-not $config.sync.enabled) {
        return [NoOpReporter]::new()
    }

    # Load plugin implementation
    $pluginType = $config.sync.provider  # "fastapi" (primary)
    $pluginPath = ".felix/plugins/sync-$pluginType.ps1"

    if (Test-Path $pluginPath) {
        Write-Host "Loading sync plugin: $pluginType" -ForegroundColor Cyan
        . $pluginPath
        return New-PluginReporter -Config $config.sync
    }

    Write-Warning "Sync enabled but plugin not found: $pluginPath"
    return [NoOpReporter]::new()
}
```

### Core Integration Points

Modify `.felix/felix-agent.ps1` to call reporter at key lifecycle points:

```powershell
# At startup
$reporter = Get-RunReporter

# Register agent (creates/updates agent record on server)
$reporter.RegisterAgent(@{
    agent_id = $env:FELIX_AGENT_ID ?? (New-Guid).ToString()
    hostname = $env:COMPUTERNAME
    platform = "windows"
    version = "0.8.0"
    felix_root = $PSScriptRoot
})

# Create run record before execution starts
$runId = $reporter.StartRun(@{
    requirement_id = $reqId
    agent_id = $agentId
    project_id = $projectId
    branch = (git branch --show-current 2>$null) ?? "main"
    commit_sha = (git rev-parse HEAD 2>$null) ?? $null
    scenario = $scenario  # e.g., "planning", "building"
})

# During execution - append structured events
$reporter.AppendEvent(@{
    run_id = $runId
    type = "phase_changed"
    level = "info"
    message = "Entering planning mode"
    timestamp = (Get-Date -Format o)
})

$reporter.AppendEvent(@{
    run_id = $runId
    type = "task_started"
    level = "info"
    payload = @{ task_id = "1.2"; title = "Add input validation" }
})

$reporter.AppendEvent(@{
    run_id = $runId
    type = "task_complete"
    level = "info"
    payload = @{ task_id = "1.2"; duration_sec = 42 }
})

# After writing artifacts
$planPath = Join-Path $runFolder "plan.md"
Set-Content -Path $planPath -Value $planContent
$reporter.UploadArtifact($runId, "plan.md", $planPath)

# On completion
$reporter.FinishRun($runId, @{
    status = if ($exitCode -eq 0) { "succeeded" } else { "failed" }
    exit_code = $exitCode
    duration_sec = $durationSec
    error_summary = $errorMessage
})

# Upload all artifacts (idempotent - server checks SHA256)
$reporter.UploadRunFolder($runId, $runFolder)

# Ensure delivery before exit
$reporter.Flush()
```

### Configuration

Add to `.felix/config.json`:

```json
{
  "sync": {
    "enabled": false,
    "provider": "fastapi",
    "base_url": "http://localhost:8080",
    "api_key": null,
    "batch_size": 10,
    "flush_interval_sec": 30
  }
}
```

Or use environment variables for per-machine setup:

```powershell
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "https://felix.company.com"
$env:FELIX_SYNC_KEY = "fsk_abc123..."
```

---

## Phase 2: Plugin Implementation

### FastAPI Reporter Plugin

Create `.felix/plugins/sync-fastapi.ps1`:

```powershell
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
    }

    [void] RegisterAgent([hashtable]$agentInfo) {
        $this.QueueRequest("POST", "/api/agents/register", $agentInfo)
        $this.TrySendOutbox()
    }

    [string] StartRun([hashtable]$metadata) {
        # Generate run_id client-side for correlation
        $runId = [guid]::NewGuid().ToString()
        $metadata.id = $runId
        $this.QueueRequest("POST", "/api/runs", $metadata)
        $this.TrySendOutbox()
        return $runId
    }

    [void] AppendEvent([hashtable]$event) {
        # Batch events per run to reduce HTTP calls and DB writes
        $runId = $event.run_id
        $this.AppendToRunOutbox($runId, @{
            type = "event"
            data = $event
        })
    }

    [void] FinishRun([string]$runId, [hashtable]$result) {
        # Flush any pending events before sending completion
        $this.FlushRunOutbox($runId)

        $this.QueueRequest("POST", "/api/runs/$runId/finish", $result)
        $this.Flush()  # Force delivery on completion
    }

    [void] UploadArtifact([string]$runId, [string]$relativePath, [string]$localPath) {
        if (-not (Test-Path $localPath)) {
            Write-Warning "Artifact not found: $localPath"
            return
        }

        # Calculate SHA256 for integrity verification
        $hash = (Get-FileHash $localPath -Algorithm SHA256).Hash.ToLower()
        $size = (Get-Item $localPath).Length

        $this.QueueFileUpload($runId, $relativePath, $localPath, @{
            sha256 = $hash
            size_bytes = $size
            content_type = Get-ContentType $relativePath
        })
    }

    [void] UploadRunFolder([string]$runId, [string]$runFolderPath) {
        # Standard artifacts in predictable locations
        $artifacts = @(
            "requirement_id.txt",
            "plan.md",
            "report.md",
            "diff.patch",
            "output.log",
            "backpressure.log",
            "commit.txt"
        )

        # Collect all files with metadata for batch upload
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

        # Single batch upload request for all files
        if ($filesToUpload.Count -gt 0) {
            $this.QueueBatchUpload($runId, $filesToUpload)
        }
    }

    [void] Flush() {
        $this.TrySendOutbox()
    }

    # --- Private implementation ---

    hidden [void] QueueRequest([string]$method, [string]$path, [hashtable]$body) {
        $request = @{
            method = $method
            path = $path
            body = $body
            timestamp = (Get-Date -Format o)
        } | ConvertTo-Json -Compress -Depth 10

        # Use timestamped filename for general requests
        $filename = "{0:yyyyMMdd-HHmmss-fff}.jsonl" -f (Get-Date)
        Add-Content -Path "$($this.OutboxPath)/$filename" -Value $request
    }

    hidden [void] AppendToRunOutbox([string]$runId, [hashtable]$item) {
        # One outbox file per run - append events to reduce file count
        $filename = "run-$runId.jsonl"
        $item.timestamp = (Get-Date -Format o)
        $line = $item | ConvertTo-Json -Compress -Depth 10
        Add-Content -Path "$($this.OutboxPath)/$filename" -Value $line
    }

    hidden [void] FlushRunOutbox([string]$runId) {
        # Send all batched events for this run
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
                # Send as batch to match backend list[RunEvent] expectation
                $this.SendJsonRequest(@{
                    method = "POST"
                    path = "/api/runs/$runId/events"
                    body = $events
                })
            }

            # Success - delete run outbox file
            Remove-Item $filepath -Force
        }
        catch {
            Write-Warning "Failed to flush events for run $runId: $_"
            throw
        }
    }

    hidden [void] QueueBatchUpload([string]$runId, [array]$files) {
        # Queue batch upload of multiple files in single HTTP request
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
                        # Batch file upload request
                        $this.UploadBatch($req)
                    } else {
                        # Regular JSON request
                        $this.SendJsonRequest($req)
                    }
                }

                # Success - delete outbox file
                Remove-Item $file.FullName -Force
            }
            catch {
                Write-Warning "Sync failed (will retry later): $_"
                break  # Stop processing, keep remaining files for retry
            }
        }
    }

    hidden [void] SendJsonRequest([object]$req) {
        $headers = @{
            "Authorization" = "Bearer $($this.ApiKey)"
            "Content-Type" = "application/json"
        }

        $url = "$($this.BaseUrl)$($req.path)"
        $body = $req.body | ConvertTo-Json -Depth 10 -Compress

        Invoke-RestMethod -Uri $url -Method $req.method `
            -Headers $headers -Body $body `
            -TimeoutSec 10 | Out-Null
    }

    hidden [void] UploadBatch([object]$req) {
        # Upload multiple files in single multipart/form-data request
        $headers = @{
            "Authorization" = "Bearer $($this.ApiKey)"
        }

        $url = "$($this.BaseUrl)$($req.path)"

        # Build manifest and form data
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

            # Add file to form data (field name = relative path)
            $form[$fileInfo.relative_path] = Get-Item $fileInfo.local_path
        }

        if ($form.Count -eq 0) {
            Write-Warning "No valid files to upload in batch"
            return
        }

        # Add manifest as JSON string
        $form.manifest = ($manifest | ConvertTo-Json -Compress)

        # PowerShell automatically handles gzip compression via Accept-Encoding
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

### Outbox Format

Outbox files are line-delimited JSON (`.jsonl`) for easy append and parsing:

**JSON Request** (`.felix/outbox/20260216-143022-456.jsonl`):

```json
{"method":"POST","path":"/api/runs","body":{"id":"abc-123","requirement_id":"S-0042"},"timestamp":"2026-02-16T14:30:22Z"}
{"method":"POST","path":"/api/runs/abc-123/events","body":{"type":"phase_changed","message":"Planning"},"timestamp":"2026-02-16T14:30:45Z"}
```

**Batch File Upload** (`.felix/outbox/20260216-143055-789-batch-upload.jsonl`):

```json
{
  "method": "POST",
  "path": "/api/runs/abc-123/files",
  "files": [
    {
      "relative_path": "plan.md",
      "local_path": "C:\\dev\\myproject\\runs\\20260216-143000\\plan.md",
      "sha256": "a1b2c3d4...",
      "size_bytes": 4521,
      "content_type": "text/markdown"
    },
    {
      "relative_path": "report.md",
      "local_path": "C:\\dev\\myproject\\runs\\20260216-143000\\report.md",
      "sha256": "e5f6g7h8...",
      "size_bytes": 8932,
      "content_type": "text/markdown"
    },
    {
      "relative_path": "output.log",
      "local_path": "C:\\dev\\myproject\\runs\\20260216-143000\\output.log",
      "sha256": "i9j0k1l2...",
      "size_bytes": 12458,
      "content_type": "text/plain; charset=utf-8"
    }
  ],
  "timestamp": "2026-02-16T14:30:55Z"
}
```

**Benefits of Batch Upload:**

- **Single HTTP request** for 5-10 files vs 5-10 separate requests (~90% reduction)
- **Automatic gzip compression** via `Accept-Encoding: gzip` (handled by PowerShell and FastAPI)
- **Idempotent via SHA256 manifest** - server skips unchanged files
- **Atomic operation** - all files uploaded together or retry batch
- **Simpler outbox** - one entry per run folder, not per file

---

## Phase 3: Database Schema

### Current State vs Target State

**Baseline:** Felix already has core tables (`runs`, `agents`, `run_artifacts`) from [001_initial_schema.sql](../app/backend/migrations/001_initial_schema.sql). This phase extends them for artifact mirroring.

#### Runs Table Changes

**Current Schema:**

```sql
CREATE TABLE runs (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    agent_id UUID NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    requirement_id UUID REFERENCES requirements(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    error TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled'))
);
```

**Required Additions:**

- `org_id UUID` - Link to organization for multi-tenancy
- `phase TEXT` - Agent execution phase ('planning', 'building', 'validating')
- `scenario TEXT` - Run context ('autonomous', 'manual', 'ci')
- `branch TEXT` - Git branch for this run
- `commit_sha TEXT` - Git commit after run completion
- `error_summary TEXT` - Structured error message (complement to `error`)
- `summary_json JSONB` - Diff stats, file counts, test results
- `duration_sec INTEGER` - Total run time in seconds
- `exit_code INTEGER` - Process exit code (0 = success)
- `finished_at TIMESTAMPTZ` - Completion timestamp (alias for `completed_at`)

**Status Values:** Extend to include `'succeeded'`, `'stopped'` for consistency with CLI output.

#### Agents Table Changes

**Current Schema:**

```sql
CREATE TABLE agents (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'idle',
    heartbeat_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (status IN ('idle', 'running', 'stopped', 'error'))
);
```

**Required Additions:**

- `hostname TEXT` - Machine hostname (currently may be in metadata)
- `platform TEXT` - OS platform ('windows', 'linux', 'darwin')
- `version TEXT` - Felix CLI version
- `profile_id UUID` - Reference to agent_profiles table
- `last_seen_at TIMESTAMPTZ` - Last heartbeat or activity timestamp

**Make `project_id` nullable:** Agents can register before being assigned to projects.

#### New Tables Required

**1. run_events** - Event timeline for runs (completely new)

```sql
CREATE TABLE run_events (
    id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    level TEXT NOT NULL CHECK (level IN ('info', 'warn', 'error', 'debug')),
    type TEXT NOT NULL,  -- 'run_started', 'phase_changed', 'task_complete', etc.
    message TEXT,
    payload JSONB,
    CONSTRAINT valid_event_type CHECK (type ~ '^[a-z_]+$')
);

CREATE INDEX idx_run_events_run_ts ON run_events(run_id, ts);
CREATE INDEX idx_run_events_type ON run_events(type, ts);
```

**Purpose:** Stores timeline of events for real-time streaming and post-run analysis.

**2. run_files** - Artifact storage tracking

**Current:** `run_artifacts` table exists but has different structure:

```sql
CREATE TABLE run_artifacts (
    id UUID PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    artifact_type TEXT NOT NULL,
    file_path TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**Migration Strategy:** Either:

- **Option A:** Migrate `run_artifacts` → `run_files` (rename + add columns)
- **Option B:** Create `run_files` alongside `run_artifacts` (deprecate old table later)

**Recommended:** Option A (migration) for consistency.

#### API Endpoints Gap Analysis

**Current Backend Routes:**

From [runs.py](../app/backend/routers/runs.py):

```
POST   /api/projects/{project_id}/runs/start     (spawn agent process)
GET    /api/projects/{project_id}/runs/status    (get running agent status)
POST   /api/projects/{project_id}/runs/stop      (kill agent process)
GET    /api/projects/{project_id}/runs           (run history - in-memory)
GET    /api/projects/{project_id}/runs/{run_id}  (run detail - filesystem)
GET    /api/projects/{project_id}/runs/{run_id}/output (console streaming)
```

From [agents.py](../app/backend/routers/agents.py):

```
POST   /api/agents/register                      (DB-backed agent registry)
POST   /api/agents/{agent_id}/heartbeat          (update last_seen)
POST   /api/agents/{agent_id}/status             (update status)
GET    /api/agents                               (list all agents)
GET    /api/agents/{agent_id}                    (get agent detail)
POST   /api/agents/runs                          (create run record)
GET    /api/agents/runs                          (list runs)
GET    /api/agents/runs/{run_id}                 (get run detail)
```

**New Routes Required (sync.py):**

```
POST   /api/runs                          (client-initiated run creation)
POST   /api/runs/{run_id}/events          (batch event ingest)
POST   /api/runs/{run_id}/finish          (mark run complete with exit_code)
PATCH  /api/runs/{run_id}/status          (tray status transitions)
POST   /api/runs/{run_id}/files           (batch artifact upload with SHA256 manifest)
GET    /api/runs/{run_id}/files           (list run artifacts)
GET    /api/runs/{run_id}/files/{path}    (download artifact via storage proxy)
GET    /api/runs/{run_id}/events          (query event timeline)
GET    /api/runs/{run_id}/stream          (SSE live event streaming)
```

**Conflicts to Resolve:**

- `POST /api/agents/register` exists in both routers - merge implementations
- `POST /api/runs` vs `POST /api/agents/runs` - different semantics (client-provided ID vs server-generated)

#### Storage Subsystem Gap

**Current:** No storage abstraction. Backend uses filesystem paths directly and in-memory dictionaries for run tracking.

**Required:** New subsystem `app/backend/storage/`:

```
storage/
  ├── base.py         (ArtifactStorage ABC interface)
  ├── filesystem.py   (FilesystemStorage - local disk)
  ├── supabase.py     (SupabaseStorage - cloud hosting)
  └── factory.py      (get_storage() configuration factory)
```

**Impact:** All artifact upload/download endpoints need storage abstraction dependency.

---

### Migration Summary

| Component           | Current State                | Required Change                           | Complexity              |
| ------------------- | ---------------------------- | ----------------------------------------- | ----------------------- |
| `runs` table        | ✅ Exists                    | Add 9 columns                             | Low (ALTER TABLE)       |
| `agents` table      | ✅ Exists                    | Add 5 columns, make project_id nullable   | Low (ALTER TABLE)       |
| `run_events` table  | ❌ Missing                   | Create new table + indexes                | Medium (new table)      |
| `run_files` table   | ⚠️ `run_artifacts` different | Migrate existing table                    | Medium (data migration) |
| Storage abstraction | ❌ Missing                   | Create new module (filesystem + supabase) | High (new subsystem)    |
| Sync router         | ❌ Missing                   | Create `routers/sync.py`                  | High (9 endpoints)      |
| SSE streaming       | ❌ Missing                   | Add pubsub + streaming endpoint           | High (real-time infra)  |

**Database Migration:** Create `014_run_artifact_mirroring.sql` with ALTER TABLE statements and new table definitions.

**Backend Implementation:** ~1000 lines of new code (storage module + sync router + SSE).

---

### Extend Runs Table

```sql
-- Add new columns to existing runs table
ALTER TABLE runs ADD COLUMN IF NOT EXISTS org_id UUID REFERENCES organizations(id);
ALTER TABLE runs ADD COLUMN IF NOT EXISTS phase TEXT;  -- 'planning', 'building', 'validating'
ALTER TABLE runs ADD COLUMN IF NOT EXISTS scenario TEXT;  -- 'autonomous', 'manual', 'ci'
ALTER TABLE runs ADD COLUMN IF NOT EXISTS branch TEXT;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS commit_sha TEXT;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS error_summary TEXT;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS summary_json JSONB;  -- diff stats, counts, etc.
ALTER TABLE runs ADD COLUMN IF NOT EXISTS duration_sec INTEGER;

-- Add indexes for queries
CREATE INDEX IF NOT EXISTS idx_runs_project_created ON runs(project_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_runs_requirement ON runs(project_id, requirement_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_runs_agent ON runs(agent_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_runs_status ON runs(status, created_at DESC);
```

### Run Events Table

```sql
CREATE TABLE IF NOT EXISTS run_events (
    id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    level TEXT NOT NULL CHECK (level IN ('info', 'warn', 'error', 'debug')),
    type TEXT NOT NULL,  -- 'run_started', 'phase_changed', 'task_started', 'task_complete', etc.
    message TEXT,
    payload JSONB,  -- Structured data for specific event types

    CONSTRAINT valid_event_type CHECK (type ~ '^[a-z_]+$')
);

CREATE INDEX idx_run_events_run_ts ON run_events(run_id, ts);
CREATE INDEX idx_run_events_type ON run_events(type, ts);
```

### Run Files Table

```sql
CREATE TABLE IF NOT EXISTS run_files (
    id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    path TEXT NOT NULL,  -- Relative path in run folder (e.g., 'report.md', 'output.log')
    kind TEXT NOT NULL CHECK (kind IN ('artifact', 'log')),
    storage_key TEXT NOT NULL,  -- Full key in storage (e.g., 'runs/org1/proj1/run123/report.md')
    size_bytes BIGINT NOT NULL,
    sha256 TEXT,  -- Hex string for integrity checks
    content_type TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (run_id, path)
);

CREATE INDEX idx_run_files_run ON run_files(run_id);
CREATE INDEX idx_run_files_kind ON run_files(run_id, kind);
CREATE INDEX idx_run_files_sha ON run_files(sha256) WHERE sha256 IS NOT NULL;
```

### Agents Table (if not exists)

```sql
CREATE TABLE IF NOT EXISTS agents (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL,  -- 'ralph', 'felix', 'custom'
    hostname TEXT,
    platform TEXT,  -- 'windows', 'linux', 'darwin'
    version TEXT,
    project_id UUID REFERENCES projects(id),
    profile_id UUID,  -- References agent configuration
    status TEXT NOT NULL CHECK (status IN ('running', 'idle', 'stopped', 'error')),
    heartbeat_at TIMESTAMPTZ,
    last_seen_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB
);

CREATE INDEX idx_agents_project ON agents(project_id);
CREATE INDEX idx_agents_status ON agents(status, last_seen_at DESC);
```

---

## Phase 4: Storage Abstraction

### Base Interface

Create `app/backend/storage/base.py`:

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

### Filesystem Implementation

Create `app/backend/storage/filesystem.py`:

```python
import aiofiles
import os
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
            import json
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
            import json
            return json.loads(await f.read())
```

### Supabase Storage Implementation

Create `app/backend/storage/supabase.py`:

```python
from supabase import create_client, Client
from typing import BinaryIO, Optional
import asyncio
from .base import ArtifactStorage

class SupabaseStorage(ArtifactStorage):
    """Supabase Storage for cloud-based artifact hosting"""

    def __init__(
        self,
        project_url: str,
        api_key: str,
        bucket: str = "run-artifacts"
    ):
        self.bucket = bucket
        self.client: Client = create_client(project_url, api_key)

    async def put(
        self,
        key: str,
        content: BinaryIO,
        content_type: str,
        metadata: dict[str, str]
    ) -> None:
        # Supabase storage client is sync, run in executor
        await asyncio.to_thread(
            self.client.storage.from_(self.bucket).upload,
            path=key,
            file=content.read(),
            file_options={"content-type": content_type, "upsert": "true"}
        )

    async def get(self, key: str) -> bytes:
        response = await asyncio.to_thread(
            self.client.storage.from_(self.bucket).download,
            path=key
        )
        return response

    async def exists(self, key: str) -> bool:
        try:
            file_list = await asyncio.to_thread(
                self.client.storage.from_(self.bucket).list,
                path=key
            )
            return len(file_list) > 0
        except Exception:
            return False

    async def delete(self, key: str) -> None:
        await asyncio.to_thread(
            self.client.storage.from_(self.bucket).remove,
            paths=[key]
        )

    async def list_keys(self, prefix: str) -> list[str]:
        files = await asyncio.to_thread(
            self.client.storage.from_(self.bucket).list,
            path=prefix
        )
        # Recursively collect all file paths
        keys = []
        for item in files:
            if item.get('name'):
                full_path = f"{prefix}/{item['name']}" if prefix else item['name']
                keys.append(full_path)
        return sorted(keys)

    async def get_metadata(self, key: str) -> Optional[dict]:
        # Supabase doesn't expose metadata separately, would need custom implementation
        # Could store metadata in separate table or JSON file
        return None
```

### Storage Factory

Create `app/backend/storage/factory.py`:

```python
from .base import ArtifactStorage
from .filesystem import FilesystemStorage
from .supabase import SupabaseStorage

def get_storage(config: dict) -> ArtifactStorage:
    """Factory to create storage implementation from config"""

    storage_type = config.get('type', 'filesystem')

    if storage_type == 'filesystem':
        return FilesystemStorage(
            base_path=config.get('base_path', 'storage/runs')
        )

    elif storage_type == 'supabase':
        return SupabaseStorage(
            project_url=config['project_url'],
            api_key=config['api_key'],
            bucket=config.get('bucket', 'run-artifacts')
        )

    else:
        raise ValueError(f"Unknown storage type: {storage_type}")
```

---

## Phase 5: Backend API Endpoints

### Ingest Endpoints

Create `app/backend/routers/sync.py`:

```python
from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Header
from fastapi.responses import StreamingResponse
from databases import Database
from typing import Optional
import uuid
from datetime import datetime

from app.backend.database import get_db
from app.backend.storage.factory import get_storage
from app.backend.storage.base import ArtifactStorage

router = APIRouter(prefix="/api", tags=["sync"])

# Models
from pydantic import BaseModel

class AgentRegistration(BaseModel):
    agent_id: str
    hostname: str
    platform: str
    version: str
    felix_root: Optional[str] = None

class RunCreate(BaseModel):
    id: Optional[str] = None  # Client can provide UUID
    requirement_id: str
    agent_id: str
    project_id: str
    branch: Optional[str] = None
    commit_sha: Optional[str] = None
    scenario: Optional[str] = None
    phase: Optional[str] = None

class RunEvent(BaseModel):
    run_id: str
    type: str
    level: str = "info"
    message: Optional[str] = None
    payload: Optional[dict] = None

class RunCompletion(BaseModel):
    status: str  # 'succeeded', 'failed', 'stopped'
    exit_code: int
    duration_sec: Optional[int] = None
    error_summary: Optional[str] = None
    summary_json: Optional[dict] = None

# Dependency for storage
def get_artifact_storage() -> ArtifactStorage:
    # TODO: Read from app config
    from app.backend.storage.filesystem import FilesystemStorage
    return FilesystemStorage()

# --- Agent Registration ---

@router.post("/agents/register")
async def register_agent(
    agent: AgentRegistration,
    db: Database = Depends(get_db)
):
    """Register or update agent (idempotent)"""

    await db.execute(
        """INSERT INTO agents (id, name, type, hostname, platform, version,
                               status, last_seen_at, metadata)
           VALUES (:id, :name, 'felix', :hostname, :platform, :version,
                   'idle', NOW(), :metadata)
           ON CONFLICT (id) DO UPDATE SET
               hostname = EXCLUDED.hostname,
               platform = EXCLUDED.platform,
               version = EXCLUDED.version,
               last_seen_at = NOW()""",
        {
            "id": agent.agent_id,
            "name": f"agent-{agent.hostname}",
            "hostname": agent.hostname,
            "platform": agent.platform,
            "version": agent.version,
            "metadata": {"felix_root": agent.felix_root}
        }
    )

    return {"status": "registered", "agent_id": agent.agent_id}

# --- Run Lifecycle ---

@router.post("/runs")
async def create_run(
    run: RunCreate,
    db: Database = Depends(get_db)
):
    """Create new run record"""

    run_id = run.id or str(uuid.uuid4())

    await db.execute(
        """INSERT INTO runs (id, agent_id, project_id, requirement_id,
                            branch, commit_sha, status, phase, created_at)
           VALUES (:id, :agent_id, :project_id, :requirement_id,
                   :branch, :commit_sha, 'running', :phase, NOW())""",
        {
            "id": run_id,
            "agent_id": run.agent_id,
            "project_id": run.project_id,
            "requirement_id": run.requirement_id,
            "branch": run.branch,
            "commit_sha": run.commit_sha,
            "phase": run.phase
        }
    )

    # Record run_started event
    await db.execute(
        """INSERT INTO run_events (run_id, type, level, message, ts)
           VALUES (:run_id, 'run_started', 'info', :message, NOW())""",
        {
            "run_id": run_id,
            "message": f"Run started on {run.agent_id}"
        }
    )

    return {"run_id": run_id, "status": "created"}

@router.post("/runs/{run_id}/events")
async def append_events(
    run_id: str,
    events: list[RunEvent],
    db: Database = Depends(get_db)
):
    """Append events to run timeline (idempotent batch insert)"""

    # Verify run exists
    run = await db.fetch_one("SELECT id FROM runs WHERE id = :run_id", {"run_id": run_id})
    if not run:
        raise HTTPException(404, "Run not found")

    # Batch insert events
    values = []
    for event in events:
        values.append({
            "run_id": run_id,
            "type": event.type,
            "level": event.level,
            "message": event.message,
            "payload": event.payload
        })

    if values:
        await db.execute_many(
            """INSERT INTO run_events (run_id, type, level, message, payload, ts)
               VALUES (:run_id, :type, :level, :message, :payload, NOW())""",
            values
        )

    # TODO: Broadcast to SSE subscribers

    return {"status": "appended", "count": len(events)}

@router.post("/runs/{run_id}/finish")
async def finish_run(
    run_id: str,
    completion: RunCompletion,
    db: Database = Depends(get_db)
):
    """Mark run as complete with final status"""

    await db.execute(
        """UPDATE runs SET
               status = :status,
               finished_at = NOW(),
               exit_code = :exit_code,
               duration_sec = :duration_sec,
               error_summary = :error_summary,
               summary_json = :summary_json
           WHERE id = :run_id""",
        {
            "run_id": run_id,
            "status": completion.status,
            "exit_code": completion.exit_code,
            "duration_sec": completion.duration_sec,
            "error_summary": completion.error_summary,
            "summary_json": completion.summary_json
        }
    )

    # Record completion event
    await db.execute(
        """INSERT INTO run_events (run_id, type, level, message, ts)
           VALUES (:run_id, 'run_finished', :level, :message, NOW())""",
        {
            "run_id": run_id,
            "level": "info" if completion.status == "succeeded" else "error",
            "message": f"Run {completion.status} with exit code {completion.exit_code}"
        }
    )

    return {"status": "finished", "run_id": run_id}

@router.patch("/runs/{run_id}/status")
async def update_run_status(
    run_id: str,
    status: str,
    message: Optional[str] = None,
    db: Database = Depends(get_db)
):
    """Update run status (used by tray manager for remote execution transitions)

    Status transitions:
    - queued → running (tray accepts command and starts CLI)
    - queued → failed (tray fails to start CLI)
    - queued → rejected (tray rejects command - invalid signature, etc.)
    """

    # Validate status
    valid_statuses = ['queued', 'running', 'succeeded', 'failed', 'stopped', 'rejected']
    if status not in valid_statuses:
        raise HTTPException(400, f"Invalid status: {status}")

    # Update status
    await db.execute(
        """UPDATE runs SET status = :status, updated_at = NOW()
           WHERE id = :run_id""",
        {"run_id": run_id, "status": status}
    )

    # Record status change event
    if message:
        await db.execute(
            """INSERT INTO run_events (run_id, type, level, message, ts)
               VALUES (:run_id, 'status_changed', :level, :message, NOW())""",
            {
                "run_id": run_id,
                "level": "error" if status in ['failed', 'rejected'] else "info",
                "message": message
            }
        )

    return {"status": "updated", "run_id": run_id, "new_status": status}

# --- Artifact Upload/Download ---

@router.post("/runs/{run_id}/files")
async def upload_artifacts_batch(
    run_id: str,
    manifest: str = Form(...),
    files: list[UploadFile] = File(...),
    db: Database = Depends(get_db),
    storage: ArtifactStorage = Depends(get_artifact_storage)
):
    """Batch upload run artifacts (idempotent via SHA256 manifest)

    Accepts multipart/form-data with:
    - manifest: JSON string array with file metadata (path, sha256, size_bytes, content_type)
    - files: Multiple file fields (field names match paths in manifest)

    HTTP automatically handles gzip compression in transit via Accept-Encoding header.
    """

    # Verify run exists and get project_id
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

    # Create lookup for uploaded files by filename
    files_by_name = {f.filename: f for f in files}

    uploaded_results = []

    for file_meta in manifest_data:
        path = file_meta["path"]
        sha256 = file_meta["sha256"]
        size_bytes = file_meta["size_bytes"]
        content_type = file_meta.get("content_type", "application/octet-stream")

        # Check if file already exists with same SHA256 (idempotency)
        existing = await db.fetch_one(
            "SELECT sha256 FROM run_files WHERE run_id = :run_id AND path = :path",
            {"run_id": run_id, "path": path}
        )

        if existing and existing["sha256"] == sha256:
            uploaded_results.append({"path": path, "status": "skipped", "reason": "unchanged"})
            continue

        # Find corresponding uploaded file
        file_data = files_by_name.get(path)
        if not file_data:
            uploaded_results.append({"path": path, "status": "missing", "reason": "file not in upload"})
            continue

        # Build storage key
        storage_key = f"runs/{project_id}/{run_id}/{path}"

        # Upload to storage
        await storage.put(
            key=storage_key,
            content=file_data.file,
            content_type=content_type,
            metadata={
                "sha256": sha256,
                "size_bytes": str(size_bytes),
                "run_id": run_id
            }
        )

        # Determine file kind
        kind = "log" if path.endswith(".log") else "artifact"

        # Record in database (upsert)
        await db.execute(
            """INSERT INTO run_files (run_id, path, kind, storage_key, size_bytes, sha256,
                                      content_type, updated_at)
               VALUES (:run_id, :path, :kind, :storage_key, :size_bytes, :sha256,
                       :content_type, NOW())
               ON CONFLICT (run_id, path) DO UPDATE SET
                   storage_key = EXCLUDED.storage_key,
                   size_bytes = EXCLUDED.size_bytes,
                   sha256 = EXCLUDED.sha256,
                   content_type = EXCLUDED.content_type,
                   updated_at = NOW()""",
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

        uploaded_results.append({"path": path, "status": "uploaded", "size_bytes": size_bytes})

    return {
        "run_id": run_id,
        "files": uploaded_results,
        "total": len(manifest_data),
        "uploaded": len([r for r in uploaded_results if r["status"] == "uploaded"]),
        "skipped": len([r for r in uploaded_results if r["status"] == "skipped"])
    }

@router.get("/runs/{run_id}/files")
async def list_run_files(
    run_id: str,
    db: Database = Depends(get_db)
):
    """List all files for a run"""

    files = await db.fetch_all(
        """SELECT path, kind, size_bytes, sha256, content_type, updated_at
           FROM run_files
           WHERE run_id = :run_id
           ORDER BY
               CASE kind WHEN 'artifact' THEN 0 ELSE 1 END,
               path""",
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
        """SELECT storage_key, size_bytes, path, content_type
           FROM run_files
           WHERE run_id = :run_id AND path = :file_path""",
        {"run_id": run_id, "file_path": file_path}
    )

    if not file_record:
        raise HTTPException(404, "File not found in database")

    # Check if artifact exists in storage
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
    after: Optional[int] = None,  # Event ID cursor
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

### SSE Streaming Endpoint (Future)

Create `app/backend/routers/streams.py`:

```python
from fastapi import APIRouter
from fastapi.responses import StreamingResponse
import asyncio
import json

router = APIRouter(prefix="/api", tags=["streams"])

# In-memory pubsub for SSE (replace with Redis/Postgres LISTEN later)
subscribers = {}

async def publish_event(run_id: str, event: dict):
    """Publish event to all subscribed SSE clients"""
    if run_id in subscribers:
        for queue in subscribers[run_id]:
            await queue.put(event)

@router.get("/runs/{run_id}/stream")
async def stream_run_events(run_id: str):
    """Server-Sent Events stream for run updates

    WARNING: In-memory pubsub does not scale across multiple backend instances.
    For production with load balancing, replace with:
    - Redis PUBSUB (redis.pub/sub with message broadcasting)
    - Postgres LISTEN/NOTIFY (pg async notifications)
    - Or simple DB polling per client (may be sufficient for <100 concurrent streams)
    """

    async def event_generator():
        # Create queue for this client
        queue = asyncio.Queue()

        if run_id not in subscribers:
            subscribers[run_id] = []
        subscribers[run_id].append(queue)

        try:
            # TODO: Send historical events first

            # Stream new events
            while True:
                event = await queue.get()
                yield f"data: {json.dumps(event)}\n\n"
        except asyncio.CancelledError:
            # Client disconnected
            subscribers[run_id].remove(queue)
            if not subscribers[run_id]:
                del subscribers[run_id]

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no"  # Disable nginx buffering
        }
    )
```

---

## Phase 6: Frontend Integration

### API Client Updates

Update `app/frontend/services/felixApi.ts`:

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

export const felixApi = {
  // ... existing methods ...

  async getRunFiles(
    runId: string,
  ): Promise<{ run_id: string; files: RunFile[] }> {
    const response = await fetch(`${API_BASE_URL}/api/runs/${runId}/files`);
    if (!response.ok) throw new Error("Failed to fetch run files");
    return response.json();
  },

  async getRunFile(runId: string, filePath: string): Promise<string> {
    const response = await fetch(
      `${API_BASE_URL}/api/runs/${runId}/files/${encodeURIComponent(filePath)}`,
    );
    if (!response.ok) throw new Error(`Failed to fetch file: ${filePath}`);
    return response.text();
  },

  async getRunEvents(
    runId: string,
    after?: number,
  ): Promise<{ run_id: string; events: RunEvent[]; has_more: boolean }> {
    const url = new URL(`${API_BASE_URL}/api/runs/${runId}/events`);
    if (after !== undefined) url.searchParams.set("after", after.toString());

    const response = await fetch(url.toString());
    if (!response.ok) throw new Error("Failed to fetch run events");
    return response.json();
  },

  streamRunEvents(
    runId: string,
    onEvent: (event: RunEvent) => void,
  ): () => void {
    const eventSource = new EventSource(
      `${API_BASE_URL}/api/runs/${runId}/stream`,
    );

    eventSource.onmessage = (message) => {
      const event = JSON.parse(message.data);
      onEvent(event);
    };

    eventSource.onerror = (error) => {
      console.error("SSE connection error:", error);
      eventSource.close();
    };

    // Return cleanup function
    return () => eventSource.close();
  },
};
```

### Run Detail Component

Update `app/frontend/components/AgentDashboard.tsx`:

```typescript
const RunDetailSlideOut: React.FC<RunDetailSlideOutProps> = ({
  projectId,
  runId,
  onClose
}) => {
  const [files, setFiles] = useState<RunFile[]>([]);
  const [events, setEvents] = useState<RunEvent[]>([]);
  const [selectedFile, setSelectedFile] = useState<string | null>(null);
  const [fileContent, setFileContent] = useState<string>('');
  const [loading, setLoading] = useState(true);

  // Fetch files on mount
  useEffect(() => {
    if (!runId) return;

    setLoading(true);
    felixApi.getRunFiles(runId)
      .then(data => {
        setFiles(data.files);
        // Auto-select report.md if available
        const report = data.files.find(f => f.path === 'report.md');
        if (report) setSelectedFile(report.path);
      })
      .catch(console.error)
      .finally(() => setLoading(false));
  }, [runId]);

  // Stream events via SSE
  useEffect(() => {
    if (!runId) return;

    const cleanup = felixApi.streamRunEvents(runId, (event) => {
      setEvents(prev => [...prev, event]);
    });

    return cleanup;
  }, [runId]);

  // Fetch selected file content
  useEffect(() => {
    if (!runId || !selectedFile) return;

    felixApi.getRunFile(runId, selectedFile)
      .then(content => setFileContent(content))
      .catch(console.error);
  }, [runId, selectedFile]);

  if (loading) {
    return <PageLoading message="Loading run details..." />;
  }

  return (
    <div className="flex h-full">
      {/* Sidebar: Files + Events */}
      <div className="w-80 border-r flex flex-col">
        {/* Files */}
        <div className="flex-1 overflow-y-auto">
          <h3 className="px-4 py-3 font-bold text-sm border-b">
            Artifacts
          </h3>
          {files.filter(f => f.kind === 'artifact').map(file => (
            <button
              key={file.path}
              onClick={() => setSelectedFile(file.path)}
              className={cn(
                "w-full text-left px-4 py-2 text-sm hover:bg-[var(--bg-surface-100)]",
                selectedFile === file.path && "bg-[var(--bg-surface-200)]"
              )}
            >
              <div className="flex items-center justify-between">
                <span>{file.path}</span>
                <span className="text-xs text-[var(--text-muted)]">
                  {(file.size_bytes / 1024).toFixed(1)}KB
                </span>
              </div>
            </button>
          ))}
        </div>

        {/* Events Timeline */}
        <div className="flex-1 border-t overflow-y-auto">
          <h3 className="px-4 py-3 font-bold text-sm border-b sticky top-0 bg-[var(--bg-base)]">
            Timeline
          </h3>
          {events.map(event => (
            <div key={event.id} className="px-4 py-2 text-xs border-b">
              <div className="flex items-center gap-2">
                <span className={cn(
                  "w-1.5 h-1.5 rounded-full",
                  event.level === 'error' ? 'bg-red-500' :
                  event.level === 'warn' ? 'bg-yellow-500' :
                  'bg-blue-500'
                )} />
                <span className="font-mono text-[var(--text-muted)]">
                  {new Date(event.ts).toLocaleTimeString()}
                </span>
              </div>
              <p className="mt-1 text-[var(--text)]">{event.message}</p>
            </div>
          ))}
        </div>
      </div>

      {/* Main: File Viewer */}
      <div className="flex-1 p-6 overflow-y-auto custom-scrollbar">
        {selectedFile && (
          <>
            <h2 className="text-lg font-bold mb-4">{selectedFile}</h2>
            {selectedFile.endsWith('.md') ? (
              <div className="prose prose-invert max-w-none">
                <ReactMarkdown>{fileContent}</ReactMarkdown>
              </div>
            ) : (
              <pre className="text-xs bg-[var(--bg-surface-100)] p-4 rounded-lg overflow-x-auto">
                {fileContent}
              </pre>
            )}
          </>
        )}
      </div>
    </div>
  );
};
```

---

## Phase 7: Migration & Rollout

### Migration Steps

1. **Database Schema**

   ```bash
   # Apply migrations
   psql -U postgres -d felix -f scripts/migrations/007_run_events_and_files.sql
   ```

2. **Backend Configuration**

   ```json
   // config/storage.json
   {
     "storage": {
       "type": "filesystem",
       "base_path": "storage/runs"
     }
   }
   ```

3. **Enable Sync for Test Agent**

   ```powershell
   # On one developer machine
   $env:FELIX_SYNC_ENABLED = "true"
   $env:FELIX_SYNC_URL = "http://localhost:8080"

   # Run a requirement
   .\.felix\felix.ps1 run S-0042

   # Verify outbox files created
   ls .felix\outbox
   ```

4. **Verify in UI**
   - Navigate to Agent Dashboard
   - View run in list (should show from database)
   - Click run to open detail panel
   - Verify artifacts load
   - Check timeline shows events

5. **Gradual Rollout**
   - Week 1: One dev machine with sync enabled
   - Week 2: CI agents with sync enabled
   - Week 3: All dev machines opt-in
   - Week 4: Make sync default (with fallback)

### Backwards Compatibility

During migration, support both filesystem and database:

```python
# app/backend/routers/runs.py

@router.get("/api/runs")
async def list_runs(project_id: str, db: Database):
    # Try database first
    db_runs = await db.fetch_all(
        "SELECT * FROM runs WHERE project_id = :project_id ORDER BY created_at DESC LIMIT 100",
        {"project_id": project_id}
    )

    if db_runs:
        return {"runs": [dict(r) for r in db_runs]}

    # Fallback to filesystem scan (legacy)
    runs = scan_filesystem_runs(project_id)
    return {"runs": runs}
```

### Cleanup Old Runs

After successful migration:

```python
# scripts/cleanup_old_runs.py

import shutil
from pathlib import Path
from datetime import datetime, timedelta

def cleanup_old_runs(days: int = 30):
    """Archive runs older than N days from filesystem"""

    runs_dir = Path("runs")
    cutoff = datetime.now() - timedelta(days=days)

    for run_dir in runs_dir.iterdir():
        if not run_dir.is_dir():
            continue

        # Parse timestamp from folder name
        try:
            run_date = datetime.strptime(run_dir.name.split('-')[0:3], "%Y%m%d")
            if run_date < cutoff:
                # Check if run exists in database
                run_id = run_dir.name
                # If in DB, safe to delete from filesystem
                print(f"Archiving {run_dir}")
                shutil.rmtree(run_dir)
        except Exception as e:
            print(f"Skipping {run_dir}: {e}")
```

---

## Success Criteria

### Phase 1 (Plugin Architecture)

- [ ] Core interface defined in `.felix/core/sync-interface.ps1`
- [ ] NoOp default implementation works (no behavior change)
- [ ] Config flag `sync.enabled=false` by default
- [ ] All tests pass with sync disabled

### Phase 2 (Plugin Implementation)

- [ ] FastAPI reporter plugin created
- [ ] Outbox pattern writes `.jsonl` files
- [ ] Manual test: events queued when server is down
- [ ] Manual test: events sent when server comes back up

### Phase 3 (Database Schema)

- [ ] Migration script creates tables: `run_events`, `run_files`
- [ ] Extends `runs` with new columns
- [ ] Indexes created for query performance
- [ ] Rollback script exists

### Phase 4 (Storage Abstraction)

- [ ] FilesystemStorage implementation works
- [ ] Factory pattern allows config-based selection
- [ ] Unit tests for storage operations
- [ ] S3Storage scaffolded (not fully implemented yet)

### Phase 5 (Backend Endpoints)

- [ ] POST `/api/agents/register` - idempotent agent registration
- [ ] POST `/api/runs` - create run, return run_id
- [ ] POST `/api/runs/{id}/events` - batch event append
- [ ] POST `/api/runs/{id}/finish` - mark complete
- [ ] POST `/api/runs/{id}/files` - batch artifact upload with manifest
- [ ] GET `/api/runs/{id}/files` - list artifacts
- [ ] GET `/api/runs/{id}/files/{path}` - download artifact
- [ ] GET `/api/runs/{id}/events` - fetch timeline
- [ ] All endpoints have tests

### Phase 6 (Frontend Integration)

- [ ] API client methods added to `felixApi.ts`
- [ ] RunDetailSlideOut shows file list from API
- [ ] File content loads and renders (markdown + plain text)
- [ ] Timeline displays events in chronological order
- [ ] SSE connection establishes and receives live updates

### Phase 7 (Migration & Rollout)

- [ ] One developer machine successfully syncs runs
- [ ] Artifacts viewable in UI from database
- [ ] Filesystem fallback works when sync disabled
- [ ] Performance acceptable (< 500ms to load run details)
- [ ] Documentation updated: HOW_TO_USE.md, AGENTS.md

---

## Future: Remote Agent Control (Phase 8+)

### Overview

Beyond mirroring local runs to the server, we want the server to remotely trigger runs on registered agents. This enables centralized orchestration: web UI dispatches work to agents across the infrastructure.

**Key Principle:** Keep CLI local-first. Remote control should live in a separate, always-running component (Tray Manager) that acts as a bridge.

### Architecture: Tray Manager as Control Plane

**Why Tray Manager, Not CLI:**

1. **Always Running:** Tray app runs as background service, can receive commands anytime
2. **Security Boundary:** User explicitly installs and authorizes tray to accept remote commands
3. **UI Feedback:** Tray can show notifications when server dispatches work
4. **Graceful Degradation:** If tray isn't running, server commands fail safely without affecting local CLI
5. **Separation of Concerns:** CLI stays pure (local execution only), tray handles networking

### Communication Flow

```
Web UI (Browser)              FastAPI Backend              Tray Manager (Local)              Felix CLI
─────────────────            ─────────────────            ────────────────────            ─────────────

User clicks
"Start Run" on    ─────1. POST─────►  /api/agents/{id}/dispatch
agent card                              ├─ Validate user has permission
                                        ├─ Create run record (status: queued)
                                        └─ Push to agent's command queue

                                                           ◄────2. WS Listen────
                                                           Tray maintains WebSocket
                                                           connection to backend for
                                                           dispatched commands

                                        ─────3. WS Push───► { type: "start_run",
                                                              run_id: "abc-123",
                                                              requirement_id: "S-0042" }

                                                           Tray receives command
                                                           ├─ Validate signature
                                                           ├─ Show notification
                                                           └─ Spawn CLI process    ────────────► felix.ps1 run S-0042
                                                                                                 (Normal local execution)

                                                                                                 ◄──── CLI writes files ──
                                                                                                 ◄──── Sync plugin uploads ──►
                                                                                                 Backend receives events
                                                                                                 via HTTP ingest (Phase 2)

                                        ◄────4. SSE Stream─── Browser receives real-time
Browser shows                          live updates via SSE
live console
```

### WebSocket Protocol (Server → Tray)

**Connection Establishment:**

```typescript
// Tray Manager (C# or Electron)
const ws = new WebSocket(`wss://felix.company.com/ws/agents/${agentId}`);

ws.onopen = () => {
  // Authenticate
  ws.send(
    JSON.stringify({
      type: "auth",
      token: getAuthToken(),
      agent_id: agentId,
    }),
  );
};
```

**Command Message Structure:**

```json
{
  "type": "start_run",
  "command_id": "cmd-uuid-123",
  "run_id": "run-uuid-456",
  "requirement_id": "S-0042",
  "params": {
    "branch": "feature/new-ui",
    "scenario": "planning",
    "max_iterations": 5
  },
  "dispatched_by": "user@company.com",
  "timestamp": "2026-02-16T14:30:00Z",
  "signature": "sha256:abc123..." // HMAC to prevent tampering
}
```

**Tray Response:**

```json
{
  "command_id": "cmd-uuid-123",
  "status": "accepted|rejected|failed",
  "message": "CLI process spawned: PID 12345",
  "error": null
}
```

### Backend Implementation

**WebSocket Endpoint** (`app/backend/routers/agent_control.py`):

```python
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends
from typing import Dict
import asyncio
import json

router = APIRouter()

# Active agent connections: agent_id -> WebSocket
agent_connections: Dict[str, WebSocket] = {}

@router.websocket("/ws/agents/{agent_id}")
async def agent_control_socket(
    websocket: WebSocket,
    agent_id: str
):
    """WebSocket for server → agent command dispatch"""

    await websocket.accept()

    # Authenticate (validate token)
    try:
        auth_msg = await websocket.receive_json()
        if not validate_agent_token(auth_msg.get('token'), agent_id):
            await websocket.close(code=1008, reason="Authentication failed")
            return
    except Exception:
        await websocket.close(code=1008, reason="Auth required")
        return

    # Register connection
    agent_connections[agent_id] = websocket

    try:
        # Keep connection alive, send heartbeats
        while True:
            # Wait for disconnect or send keepalive
            await asyncio.sleep(30)
            await websocket.send_json({"type": "ping"})

    except WebSocketDisconnect:
        # Clean up on disconnect
        if agent_id in agent_connections:
            del agent_connections[agent_id]

@router.post("/api/agents/{agent_id}/dispatch")
async def dispatch_run(
    agent_id: str,
    command: RunDispatchCommand,
    db: Database = Depends(get_db)
):
    """Dispatch a run command to agent (pushes via WebSocket)"""

    # Verify agent is online
    if agent_id not in agent_connections:
        raise HTTPException(503, "Agent not connected")

    # Create run record (status: queued)
    run_id = str(uuid.uuid4())
    await db.execute(
        """INSERT INTO runs (id, agent_id, project_id, requirement_id,
                            status, created_at)
           VALUES (:id, :agent_id, :project_id, :requirement_id,
                   'queued', NOW())""",
        {
            "id": run_id,
            "agent_id": agent_id,
            "project_id": command.project_id,
            "requirement_id": command.requirement_id
        }
    )

    # Build command message
    command_msg = {
        "type": "start_run",
        "command_id": str(uuid.uuid4()),
        "run_id": run_id,
        "requirement_id": command.requirement_id,
        "params": command.params,
        "dispatched_by": get_current_user(),  # From auth context
        "timestamp": datetime.utcnow().isoformat(),
    }

    # Sign command to prevent tampering
    command_msg["signature"] = sign_command(command_msg)

    # Push to agent via WebSocket
    try:
        ws = agent_connections[agent_id]
        await ws.send_json(command_msg)

        return {
            "status": "dispatched",
            "run_id": run_id,
            "command_id": command_msg["command_id"]
        }

    except Exception as e:
        # Mark run as failed if dispatch fails
        await db.execute(
            "UPDATE runs SET status = 'failed', error_summary = :error WHERE id = :run_id",
            {"run_id": run_id, "error": str(e)}
        )
        raise HTTPException(500, "Failed to dispatch to agent")
```

### Tray Manager Implementation

**WebSocket Handler** (C# WPF or Electron):

```csharp
// TrayManager/Services/AgentControlService.cs

public class AgentControlService
{
    private ClientWebSocket _webSocket;
    private string _agentId;
    private string _authToken;

    public async Task ConnectAsync()
    {
        _webSocket = new ClientWebSocket();
        var uri = new Uri($"wss://felix.company.com/ws/agents/{_agentId}");

        await _webSocket.ConnectAsync(uri, CancellationToken.None);

        // Authenticate
        var authMsg = new { type = "auth", token = _authToken, agent_id = _agentId };
        await SendJsonAsync(authMsg);

        // Start listening for commands
        _ = Task.Run(ListenForCommandsAsync);
    }

    private async Task ListenForCommandsAsync()
    {
        var buffer = new byte[8192];

        while (_webSocket.State == WebSocketState.Open)
        {
            var result = await _webSocket.ReceiveAsync(
                new ArraySegment<byte>(buffer),
                CancellationToken.None
            );

            if (result.MessageType == WebSocketMessageType.Text)
            {
                var json = Encoding.UTF8.GetString(buffer, 0, result.Count);
                var command = JsonConvert.DeserializeObject<CommandMessage>(json);

                await HandleCommandAsync(command);
            }
        }
    }

    private async Task HandleCommandAsync(CommandMessage command)
    {
        if (command.Type == "start_run")
        {
            // Validate signature
            if (!VerifySignature(command))
            {
                await SendResponseAsync(command.CommandId, "rejected", "Invalid signature");
                return;
            }

            // Show notification
            ShowNotification($"Starting run: {command.RequirementId}",
                           $"Dispatched by {command.DispatchedBy}");

            // Spawn CLI process
            try
            {
                var process = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = "powershell.exe",
                        Arguments = $"-File .felix\\felix.ps1 run {command.RequirementId}",
                        WorkingDirectory = GetProjectPath(),
                        UseShellExecute = false,
                        CreateNoWindow = false  // Show console for visibility
                    }
                };

                process.Start();

                await SendResponseAsync(command.CommandId, "accepted",
                    $"Started process PID {process.Id}");

                // Update run status on server: queued → running
                await UpdateRunStatusAsync(command.RunId, "running",
                    $"Accepted by agent, CLI started (PID {process.Id})");
            }
            catch (Exception ex)
            {
                await SendResponseAsync(command.CommandId, "failed", ex.Message);

                // Update run status on server: queued → failed
                await UpdateRunStatusAsync(command.RunId, "failed",
                    $"Agent failed to start CLI: {ex.Message}");
            }
        }
    }

    private async Task SendResponseAsync(string commandId, string status, string message)
    {
        var response = new { command_id = commandId, status, message };
        await SendJsonAsync(response);
    }

    private async Task UpdateRunStatusAsync(string runId, string status, string message)
    {
        // POST to backend to update run status
        var payload = new {
            status,
            message
        };

        using var client = new HttpClient();
        client.DefaultRequestHeaders.Add("Authorization", $"Bearer {_authToken}");

        var content = new StringContent(
            JsonConvert.SerializeObject(payload),
            Encoding.UTF8,
            "application/json"
        );

        await client.PatchAsync(
            $"https://felix.company.com/api/runs/{runId}/status",
            content
        );
    }
}
```

### Security Considerations

1. **Authentication:**
   - Tray authenticates with API key or machine token
   - Tokens scoped to specific agent_id
   - Rotation policy (monthly)

2. **Authorization:**
   - Server checks user permissions before dispatching
   - Agent validates command signature (HMAC-SHA256)
   - Prevents replay attacks with timestamp + nonce

3. **Network Security:**
   - WSS only (WebSocket over TLS)
   - Certificate pinning in tray app
   - Rate limiting on dispatch endpoint

4. **User Consent:**
   - Tray shows notification before starting run
   - Settings UI to disable remote control
   - Audit log of all dispatched commands

### User Experience

**In Web UI:**

1. User navigates to Agent Dashboard
2. Sees list of registered agents with "online" status
3. Clicks "Start Run" on an online agent
4. Modal: "Select Requirement" → picks S-0042
5. Server dispatches command → agent starts → UI shows live console via SSE

**In Tray Manager:**

1. Tray icon shows green dot when connected to server
2. Notification appears: "Felix: Starting run S-0042 (requested by user@company.com)"
3. Console window opens showing CLI execution
4. Tray icon animates while run is active
5. Notification on completion: "Run S-0042 succeeded in 3m 42s"

### Phasing

**Not in this spec:** Remote control is Phase 8+ (future work). Current spec (Phases 1-7) focuses on:

- Agent → Server: HTTP ingest for run mirroring
- Server → Browser: SSE for live updates

**When ready for remote control:**

1. Implement WebSocket endpoint in backend
2. Add dispatch command API with permissions
3. Extend tray manager with WS client
4. Add "Start Run" button in frontend agent dashboard
5. Security audit and penetration testing

### Alternative Architectures Considered

**Option A: CLI listens on WebSocket**

- ❌ Requires CLI to be always running (defeats local-first principle)
- ❌ Security risk: CLI must handle auth and network attacks
- ❌ Complexity: CLI becomes server, needs port management

**Option B: Polling (CLI checks server for commands)**

- ❌ Latency: Polling interval adds delay (30s-60s typical)
- ❌ Inefficient: Constant polling wastes resources
- ❌ Still requires CLI to run in background (not local-first)

**Option C: Tray Manager + WebSocket** ✅ (Recommended)

- ✅ CLI stays local-only, no network concerns
- ✅ Real-time dispatch (WebSocket push, <1s latency)
- ✅ Secure: Tray is separate, user-installed component
- ✅ Optional: Users can run CLI locally without tray
- ✅ Visible: Tray icon shows connection status

---

## Design Refinements

Following architectural review, these implementation details were tightened to improve reliability and performance:

### 1. Event Batching

**Issue:** Plugin was sending events one-at-a-time to `/api/runs/{run_id}/events`, but backend expects `list[RunEvent]`.

**Solution:**

- Plugin now batches events per run in `run-{runId}.jsonl` outbox file
- `FlushRunOutbox()` sends all accumulated events as single batch request
- Reduces HTTP calls and DB writes significantly
- Called automatically before `FinishRun()`

**Code:** See `AppendToRunOutbox()` and `FlushRunOutbox()` in Phase 2

### 2. Outbox File Granularity

**Issue:** Creating one `.jsonl` file per event generates hundreds of tiny files per run.

**Solution:**

- One outbox file per run: `run-{runId}.jsonl`
- Events appended as lines to same file
- File deleted only when fully delivered
- Reduces file system overhead dramatically

**Code:** See `AppendToRunOutbox()` method in Phase 2

### 3. Multipart File Upload

**Issue:** PowerShell `-InFile` parameter does NOT send multipart/form-data automatically.

**Solution:**

- Use `-Form @{ file = Get-Item $path }` for proper multipart encoding
- Backend receives proper `UploadFile` object from FastAPI
- Maintains compatibility with FastAPI's `File(...)` dependency

**Code:** See `UploadFile()` method in Phase 2

### 4. Dispatch Status Transitions

**Issue:** When tray accepts/rejects remote command, run status remains 'queued' without feedback.

**Solution:**

- Tray calls new `PATCH /api/runs/{run_id}/status` endpoint after handling command
- Status transitions: `queued` → `running` (accepted) or `failed`/`rejected` (failed)
- Records status_changed event with reason message
- Provides visibility into remote execution lifecycle

**Code:** See `UpdateRunStatusAsync()` in tray manager (Phase 8) and `PATCH /runs/{run_id}/status` endpoint (Phase 5)

### 5. SSE Pubsub Scalability

**Issue:** In-memory `subscribers = {}` dict only works for single backend instance.

**Solution (Future):**

- For production with load balancing, replace with:
  - **Redis PUBSUB:** Message broadcasting across instances
  - **Postgres LISTEN/NOTIFY:** Native async notifications
  - **DB Polling:** Simple fallback for <100 concurrent streams
- Added warning comment in code for Phase 6+ implementation

**Code:** See comment in `stream_run_events()` endpoint (Phase 6)

---

## Production Hardening Considerations

These are refinements for production maturity, not blockers for initial implementation. Consider for Phase 2+ hardening.

### 1. Event Batch Idempotency

**Current Risk:** If `FlushRunOutbox()` times out after server commits but before deleting outbox file, retry will duplicate events in database.

**Hardening Solution:**

```sql
-- Add client-side event ID for deduplication
ALTER TABLE run_events ADD COLUMN event_id UUID;
CREATE UNIQUE INDEX idx_run_events_dedup ON run_events(run_id, event_id);
```

**Plugin Change:**

```powershell
[void] AppendEvent([hashtable]$event) {
    # Generate client-side event ID for idempotency
    $event.event_id = [guid]::NewGuid().ToString()
    $this.AppendToRunOutbox($event.run_id, @{
        type = "event"
        data = $event
    })
}
```

**Backend Change:**

```python
# In append_events endpoint
for event in events:
    try:
        await db.execute(
            """INSERT INTO run_events (run_id, event_id, type, level, message, payload, ts)
               VALUES (:run_id, :event_id, :type, :level, :message, :payload, NOW())
               ON CONFLICT (run_id, event_id) DO NOTHING""",  # Ignore duplicates
            {**event}
        )
    except:
        pass  # Duplicate event, already inserted
```

**Benefit:** Network timeouts and retries become safe. At-least-once delivery without duplication.

### 2. Atomic Outbox File Handling

**Current Risk:** Crash after successful HTTP send but before deleting outbox file causes re-send on restart.

**Hardening Pattern:**

```powershell
hidden [void] FlushRunOutbox([string]$runId) {
    $filename = "run-$runId.jsonl"
    $filepath = "$($this.OutboxPath)/$filename"
    $tempfile = "$($this.OutboxPath)/.processing-$runId.jsonl"

    if (-not (Test-Path $filepath)) { return }

    try {
        # Atomic rename: marks file as in-flight
        Move-Item $filepath $tempfile -Force

        $lines = Get-Content $tempfile
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

        # Success - delete temp file
        Remove-Item $tempfile -Force
    }
    catch {
        # Restore original file for retry
        if (Test-Path $tempfile) {
            Move-Item $tempfile $filepath -Force
        }
        throw
    }
}
```

**Benefit:** Crash recovery is clean. File states are unambiguous (pending, processing, done).

### 3. Server-Side Artifact Integrity Verification

**Current Gap:** Server stores SHA256 from client header but doesn't verify content matches.

**Hardening Implementation:**

```python
@router.put("/runs/{run_id}/files/{file_path:path}")
async def upload_artifact(
    run_id: str,
    file_path: str,
    file: UploadFile = File(...),
    x_sha256: Optional[str] = Header(None),
    x_size_bytes: Optional[int] = Header(None),
    db: Database = Depends(get_db),
    storage: ArtifactStorage = Depends(get_artifact_storage)
):
    """Upload run artifact with integrity verification"""

    # Read file content
    content = await file.read()

    # Verify integrity if hash provided
    if x_sha256:
        computed_hash = hashlib.sha256(content).hexdigest()
        if computed_hash != x_sha256.lower():
            raise HTTPException(
                400,
                f"SHA256 mismatch: expected {x_sha256}, got {computed_hash}"
            )

    # Verify size if provided
    actual_size = len(content)
    if x_size_bytes and actual_size != x_size_bytes:
        raise HTTPException(
            400,
            f"Size mismatch: expected {x_size_bytes}, got {actual_size}"
        )

    # Upload to storage
    await storage.put(
        key=storage_key,
        content=BytesIO(content),
        content_type=file.content_type or "application/octet-stream",
        metadata={
            "sha256": x_sha256 or computed_hash,
            "size_bytes": str(actual_size)
        }
    )

    # ... rest of endpoint
```

**Benefit:** Detects corruption during upload. SHA256 becomes meaningful, not decorative.

### 4. SSE Event Bootstrap

**Current Gap:** SSE endpoint has `# TODO: Send historical events first`. Without this, users miss events before connecting.

**Hardening Implementation:**

```python
@router.get("/runs/{run_id}/stream")
async def stream_run_events(run_id: str, after: Optional[int] = None):
    """Server-Sent Events stream with historical bootstrap"""

    async def event_generator():
        queue = asyncio.Queue()

        if run_id not in subscribers:
            subscribers[run_id] = []
        subscribers[run_id].append(queue)

        try:
            # Bootstrap: Send all historical events first
            cursor = after or 0
            historical = await db.fetch_all(
                """SELECT id, ts, type, level, message, payload
                   FROM run_events
                   WHERE run_id = :run_id AND id > :cursor
                   ORDER BY id ASC
                   LIMIT 1000""",
                {"run_id": run_id, "cursor": cursor}
            )

            for event in historical:
                yield f"data: {json.dumps(dict(event))}\n\n"

            # Now stream new events
            while True:
                event = await queue.get()
                yield f"data: {json.dumps(event)}\n\n"

        except asyncio.CancelledError:
            subscribers[run_id].remove(queue)
            if not subscribers[run_id]:
                del subscribers[run_id]

    return StreamingResponse(event_generator(), media_type="text/event-stream")
```

**Frontend Pattern:**

```typescript
// 1. Load historical events first (with spinner)
const { events } = await felixApi.getRunEvents(runId);
setEvents(events);

// 2. Then open SSE for new events only
const unsubscribe = felixApi.streamRunEvents(
  runId,
  events[events.length - 1]?.id, // Resume after last historical event
  (newEvent) => {
    setEvents((prev) => [...prev, newEvent]);
  },
);
```

**Benefit:** No race condition. Users see complete timeline immediately.

### 5. Concurrent Run Outbox Isolation

**Current Risk:** If multiple runs execute concurrently, `TrySendOutbox()` loops all `.jsonl` files and may interleave flushes.

**Hardening Options:**

**Option A: Separate Outbox Per Run**

```powershell
FastApiReporter([hashtable]$config) {
    $this.BaseUrl = $config.base_url
    $this.ApiKey = $config.api_key
    # One outbox directory per run for isolation
    $runId = [guid]::NewGuid().ToString()
    $this.OutboxPath = ".felix/outbox/$runId"
    New-Item -ItemType Directory -Path $this.OutboxPath -Force | Out-Null
}
```

**Option B: File Locking During Flush**

```powershell
hidden [void] TrySendOutbox() {
    $lockFile = "$($this.OutboxPath)/.flush.lock"

    # Try acquire lock (non-blocking)
    try {
        $lock = [System.IO.File]::Open($lockFile, 'CreateNew', 'Write')

        # Lock acquired - flush files
        $files = Get-ChildItem -Path $this.OutboxPath -Filter "*.jsonl"
        # ... process files ...

        $lock.Close()
        Remove-Item $lockFile -Force
    }
    catch {
        # Lock held by another run - skip this flush
        return
    }
}
```

**Recommendation:** Option A (separate outbox per run) is cleaner for Felix's multi-run concurrency model.

**Benefit:** Concurrent runs don't interfere with each other's sync operations.

---

## Scale Testing & Staged Rollout

### Load Scenario: 10 Agents / 1K Runs Per Day

**Assumptions:**

- 10 active agents across dev/staging/prod infrastructure
- Average 100 runs per agent per day (1 every 15 minutes during work hours)
- Average run: 30 events, 5 artifacts, 200KB total storage
- Peak load: 5 concurrent runs across all agents

**Database Load:**

```
Events per day: 1000 runs × 30 events = 30,000 inserts
Files per day: 1000 runs × 5 files = 5,000 inserts
Storage per day: 1000 runs × 200KB = 200MB
Storage per month: ~6GB

DB writes per second (peak): 5 concurrent runs × 30 events / 180s avg duration = ~0.8 writes/sec
```

**Verdict:** Easily handled by single Postgres instance. No sharding needed.

**HTTP Load:**

```
Assuming batch size of 10 events per flush:
Event batches per run: 30 events / 10 = 3 requests
File uploads per run: 5 requests
Total HTTP per run: 8 requests

Peak HTTP: 5 concurrent runs × 8 requests / 180s = ~0.2 req/sec
```

**Verdict:** Trivial load. Single FastAPI instance sufficient.

**SSE Connections:**

```
Assume 10 concurrent viewers watching live runs:
10 open SSE connections × ~1 event/sec = 10 messages/sec
```

**Verdict:** No stress. In-memory pubsub acceptable until 50+ concurrent viewers.

### Bottlenecks to Monitor

1. **Storage I/O:** If switching to S3, ensure upload bandwidth sufficient for artifact ingest
2. **DB Connection Pool:** Default asyncpg pool (10 connections) sufficient for this scale
3. **SSE Memory:** Each connection holds ~8KB buffer. 100 viewers = <1MB overhead

### Staged Implementation Plan

#### Stage 1: Local-Only Sync Testing (Week 1)

**Goal:** Validate plugin architecture and outbox pattern without server dependency.

**Implementation:**

- Core sync interface (`IRunReporter`, `NoOpReporter`)
- FastAPI reporter plugin with outbox queue
- Mock HTTP endpoints (return 200 OK immediately)
- Run Felix CLI with sync enabled, verify outbox files generated

**Success Criteria:**

- [ ] Outbox files created per run
- [ ] Events batched correctly
- [ ] Outbox cleaned on success
- [ ] Retries work after simulated network failure

#### Stage 2: Backend Schema & Ingest (Week 2)

**Goal:** Database schema and HTTP ingest endpoints operational.

**Implementation:**

- Extend `runs` table with new columns
- Create `run_events` and `run_files` tables
- Implement `/api/runs`, `/api/runs/{id}/events`, `/api/runs/{id}/finish`
- Filesystem storage only (no cloud storage yet)

**Success Criteria:**

- [ ] Runs appear in database with correct metadata
- [ ] Events insert in correct order
- [ ] Duplicate events ignored (idempotency)
- [ ] File uploads stored locally

#### Stage 3: Frontend Read-Only (Week 3)

**Goal:** View run history and artifacts in web UI.

**Implementation:**

- Agent dashboard shows run history
- Run detail view with event timeline
- Artifact download links
- SSE streaming (with bootstrap) for live runs

**Success Criteria:**

- [ ] Historical runs display correctly
- [ ] Live run console updates in real-time
- [ ] Artifacts downloadable (PDF, Markdown, logs)
- [ ] SSE reconnects gracefully

#### Stage 4: Multi-Agent Production Trial (Week 4)

**Goal:** Deploy to 3 real agents, monitor for 1 week.

**Implementation:**

- Enable sync on 3 development machines
- Monitor DB growth, outbox behavior, HTTP errors
- Collect feedback from developers using web UI

**Success Criteria:**

- [ ] No outbox file accumulation (delivery working)
- [ ] No duplicate events (idempotency working)
- [ ] <5 second lag from CLI event to web UI display
- [ ] Zero data loss during network interruptions

#### Stage 5: Storage Migration to Supabase (Week 5+)

**Goal:** Move artifact storage from local filesystem to Supabase Storage for cloud hosting and scalability.

**Implementation:**

- Create Supabase project and configure storage bucket
- Update backend config to use `SupabaseStorage`
- Migrate existing artifacts with background job
- Verify integrity with SHA256 checks

**Success Criteria:**

- [ ] New artifacts stored in Supabase
- [ ] Downloads proxied correctly
- [ ] <2 second upload time for 1MB artifact
- [ ] Integrity verification passes 100%

#### Stage 6: Remote Control (Future)

**Goal:** Enable server-initiated runs via tray manager.

**Implementation:**

- Tray manager WebSocket client
- Backend dispatch endpoints with permissions
- Frontend "Start Run" button on agent dashboard
- Security audit and penetration testing

**Success Criteria:**

- [ ] Dispatch latency <1 second
- [ ] Tray shows notification on remote trigger
- [ ] Status transitions tracked correctly
- [ ] Command signatures prevent tampering

### Rollback Plan

**If Stage 3 or 4 fails:**

1. Set `sync.enabled = false` in `.felix/config.json`
2. CLI continues working with local filesystem only
3. Investigate backend issues without blocking development
4. Re-enable sync after fixes deployed

**Data Loss Protection:**

- Outbox pattern ensures no data loss if server unavailable
- Local filesystem remains canonical
- Backend can be rebuilt from local run folders if needed

---

## Open Questions

1. **Authentication for Runner**
   - Use API keys? JWT tokens? Service accounts?
   - How to distribute securely to dev machines?

2. **Retention Policy**
   - How long to keep runs in database?
   - When to delete artifacts from storage?
   - Per-org or per-project settings?

3. **Storage Sizing**
   - Estimate: 100 runs/day × 50KB average = 5MB/day = ~150MB/month
   - When to switch from filesystem to Supabase? (Threshold: ~1GB local storage)

4. **SSE vs WebSocket**
   - Start with SSE for read-only streaming?
   - Add WebSocket later for bidirectional control?

5. **Event Schema Evolution**
   - How to version event types?
   - Backwards compatibility strategy?

---

## References

- [PowerShell Classes](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_classes)
- [FastAPI Background Tasks](https://fastapi.tiangolo.com/tutorial/background-tasks/)
- [Server-Sent Events](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events)
- [Supabase Storage](https://supabase.com/docs/guides/storage)
- [Supabase Python Client](https://supabase.com/docs/reference/python/introduction)
