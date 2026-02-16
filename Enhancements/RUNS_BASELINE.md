# Run Artifact Sync - Baseline Documentation

## Overview

This document captures the baseline state before implementing run artifact syncing. It serves as a reference point for the migration and provides context for the sync implementation.

**Preparation Phase:** S-0057  
**Implementation Reference:** [RUNS_MIGRATION.md](./RUNS_MIGRATION.md)

---

## Current State Baseline

### Local Run Directory Statistics

**Captured:** 2026-02-16

| Metric | Value |
|--------|-------|
| Total run directories | 593 |
| Location | **runs/** |
| Naming convention (legacy) | YYYY-MM-DDTHH-mm-ss |
| Naming convention (current) | S-{id}-YYYYMMDD-HHmmss-it{N} |

**Typical Run Artifacts:**

- **requirement_id.txt** - Requirement ID being processed
- **plan.md** - Implementation plan (if planning mode)
- **report.md** - Run summary report
- **diff.patch** - Git diff of changes
- **output.log** - Console output capture
- **backpressure.log** - Test/lint results
- **commit.txt** - Commit message (if committed)

---

## Database Schema Baseline

### Existing Tables (from 001_initial_schema.sql)

#### agents

```sql
CREATE TABLE IF NOT EXISTS agents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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

#### runs

```sql
CREATE TABLE IF NOT EXISTS runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
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

#### run_artifacts

```sql
CREATE TABLE IF NOT EXISTS run_artifacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    artifact_type TEXT NOT NULL,
    file_path TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Existing Indexes

```sql
CREATE INDEX IF NOT EXISTS idx_agents_project_id ON agents(project_id);
CREATE INDEX IF NOT EXISTS idx_agents_status ON agents(status);
CREATE INDEX IF NOT EXISTS idx_runs_project_id ON runs(project_id);
CREATE INDEX IF NOT EXISTS idx_runs_agent_id ON runs(agent_id);
CREATE INDEX IF NOT EXISTS idx_runs_status ON runs(status);
CREATE INDEX IF NOT EXISTS idx_run_artifacts_run_id ON run_artifacts(run_id);
```

---

## Preparation Phase Deliverables (S-0057)

### Configuration

- [x] **.felix/config.json** - Added sync section with:
  - enabled: false (default)
  - provider: fastapi
  - base_url: http://localhost:8080
  - api_key: null

### Database Migration Scaffold

- [x] **app/backend/migrations/014_run_artifact_mirroring.sql** - Placeholder migration for run artifact sync (actual schema changes in S-0058)

### Backend Environment

- [x] **app/backend/.env.example** - Added storage settings:
  - STORAGE_TYPE=filesystem
  - STORAGE_BASE_PATH=storage/runs

### Documentation

- [x] **Enhancements/RUNS_BASELINE.md** - This file (baseline documentation)
- [x] **Enhancements/RUNS_MIGRATION.md** - Full architecture and implementation plan

---

## Development Workflow

### Branch Strategy

- **Feature branch:** feature/run-artifact-sync
- **Base branch:** main
- **Merge strategy:** Squash merge after all phases complete
- **Remote status:** Push manually with `git push -u origin feature/run-artifact-sync`
  - Note: RUNS_MIGRATION.md contains example API key placeholders that may trigger secret detection

### Enabling Sync for Local Testing

**Environment Variables (recommended for testing):**

```powershell
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "http://localhost:8080"
$env:FELIX_SYNC_KEY = "fsk_your_api_key_here"  # Optional
```

**Config File (.felix/config.json):**

```json
{
  "sync": {
    "enabled": true,
    "provider": "fastapi",
    "base_url": "http://localhost:8080",
    "api_key": null
  }
}
```

### Related Spec IDs

| Spec ID | Title | Phase |
|---------|-------|-------|
| S-0057 | Run Artifact Sync - Preparation and Foundation | Preparation |
| S-0058 | Run Artifact Sync - Database Schema | Phase 3 |
| S-0059 | Run Artifact Sync - Storage Abstraction | Phase 4 |
| S-0060 | Run Artifact Sync - Plugin Architecture | Phase 1 |
| S-0061 | Run Artifact Sync - Plugin Implementation | Phase 2 |
| S-0062 | Run Artifact Sync - Backend API Endpoints | Phase 5 |
| S-0063 | Run Artifact Sync - Frontend Integration | Phase 6 |
| S-0064 | Run Artifact Sync - Migration & Rollout | Phase 7 |

---

## Sync Architecture Summary

### Design Principles

1. **Local First** - Runner always writes artifacts to local filesystem first
2. **Server as Mirror** - Server acts as audit mirror, not source of truth
3. **Eventual Consistency** - Outbox pattern ensures delivery despite network failures
4. **Idempotent** - SHA256 checksums prevent duplicate uploads

### Data Flow

```
Runner (PowerShell)
    ↓
Local Filesystem (runs/)
    ↓
Sync Plugin (optional)
    ↓
Outbox Queue (.felix/outbox/*.jsonl)
    ↓
HTTP Ingest → Backend API
    ↓
Database + Storage
    ↓
Frontend UI
```

### Key Files

| File | Purpose |
|------|---------|
| **.felix/config.json** | Sync configuration |
| **.felix/outbox/*.jsonl** | Pending sync requests |
| **.felix/plugins/sync-fastapi.ps1** | FastAPI sync plugin |
| **.felix/core/sync-interface.ps1** | Plugin interface definition |

---

## Notes

- **No existing synced runs** - This is a greenfield implementation
- **Backwards compatibility** - Frontend will fall back to filesystem reads during migration
- **Migration consideration** - 593 existing run directories may need batch migration
