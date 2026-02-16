# S-0060: Run Artifact Sync - Backend Sync Endpoints

**Priority:** High  
**Tags:** Backend, API, Sync

## Description

As a Felix developer, I need backend API endpoints for run artifact syncing so that the CLI agent can register itself, create run records, log events, upload artifacts, and mark runs complete via HTTP requests.

## Dependencies

- S-0058 (Database Schema Extensions) - requires run_events and run_files tables
- S-0059 (Storage Abstraction Layer) - requires storage interface and filesystem implementation
- S-0036 (Backend Database Integration Layer) - requires database connection

## Acceptance Criteria

### Sync Router Module

- [ ] Router file `app/backend/routers/sync.py` created
- [ ] Router registered in `app/backend/main.py` with /api prefix
- [ ] Router tagged with "sync" for API documentation
- [ ] All endpoints appear in OpenAPI docs at /docs

### Pydantic Models

- [ ] `AgentRegistration` model with agent_id, hostname, platform, version fields
- [ ] `RunCreate` model with id (optional), requirement_id, agent_id, project_id, branch, commit_sha, scenario, phase fields
- [ ] `RunEvent` model with type, level, message, payload fields
- [ ] `RunCompletion` model with status, exit_code, duration_sec, error_summary, summary_json fields

### Agent Registration Endpoint

- [ ] POST /api/agents/register endpoint exists
- [ ] Accepts AgentRegistration JSON body
- [ ] Uses INSERT ... ON CONFLICT for idempotent upsert
- [ ] Updates hostname, platform, version, last_seen_at on conflict
- [ ] Returns {status: "registered", agent_id: string}
- [ ] Returns 500 with error message on database failure

### Run Creation Endpoint

- [ ] POST /api/runs endpoint exists
- [ ] Accepts RunCreate JSON body
- [ ] Generates UUID run_id if not provided by client
- [ ] Verifies agent_id exists in agents table (returns 404 if not found)
- [ ] Verifies project_id exists in projects table (returns 404 if not found)
- [ ] Inserts run record with status 'running'
- [ ] Inserts initial run_started event
- [ ] Returns {run_id: string, status: "created"}

### Event Append Endpoint

- [ ] POST /api/runs/{run_id}/events endpoint exists
- [ ] Accepts list of RunEvent objects
- [ ] Verifies run exists (returns 404 if not)
- [ ] Batch inserts all events with execute_many
- [ ] Returns {status: "appended", count: number}
- [ ] Handles empty event list gracefully

### Run Completion Endpoint

- [ ] POST /api/runs/{run_id}/finish endpoint exists
- [ ] Accepts RunCompletion JSON body
- [ ] Updates runs table with status, exit_code, duration_sec, error_summary, summary_json
- [ ] Sets finished_at and completed_at to NOW()
- [ ] Inserts run_finished event with appropriate level (info or error)
- [ ] Returns {status: "finished", run_id: string}

### Artifact Upload Endpoint

- [ ] POST /api/runs/{run_id}/files endpoint exists
- [ ] Accepts multipart/form-data with manifest field (JSON string) and file fields
- [ ] Verifies run exists and fetches project_id (returns 404 if not)
- [ ] Parses manifest JSON (returns 400 if invalid)
- [ ] Creates files_by_name lookup from uploaded files
- [ ] For each file in manifest checks existing SHA256 for idempotency
- [ ] Skips unchanged files (status: "skipped", reason: "unchanged")
- [ ] Uploads new/changed files to storage with key format runs/{project_id}/{run_id}/{path}
- [ ] Inserts/updates run_files records with ON CONFLICT upsert
- [ ] Determines kind (log vs artifact) based on path extension
- [ ] Returns {run_id, files: [{path, status, size_bytes}], total, uploaded, skipped}

### Artifact List Endpoint

- [ ] GET /api/runs/{run_id}/files endpoint exists
- [ ] Queries run_files table for given run_id
- [ ] Orders by kind (artifact first) then path
- [ ] Returns {run_id, files: [{path, kind, size_bytes, sha256, content_type, updated_at}]}

### Artifact Download Endpoint

- [ ] GET /api/runs/{run_id}/files/{file_path:path} endpoint exists
- [ ] Fetches storage_key from run_files table (returns 404 if not found)
- [ ] Checks storage.exists() before attempting download (returns 404 if missing)
- [ ] Streams content from storage using StreamingResponse
- [ ] Sets Content-Type from content_type field
- [ ] Sets Content-Disposition header with filename
- [ ] Sets Content-Length header

### Event Query Endpoint

- [ ] GET /api/runs/{run_id}/events endpoint exists
- [ ] Accepts optional `after` query parameter for cursor-based pagination
- [ ] Accepts optional `limit` query parameter (defaults to 100)
- [ ] Orders events by id ASC for timeline order
- [ ] Returns {run_id, events: [{id, ts, type, level, message, payload}], has_more: bool}

### Authentication

- [ ] All endpoints accept optional Authorization header
- [ ] `verify_api_key()` dependency function exists
- [ ] Auth validation stubbed for now (accepts any Bearer token)
- [ ] TODO comment indicates proper validation needed later

## Validation Criteria

- [ ] Backend starts without errors - `python app/backend/main.py` (exit code 0)
- [ ] `curl http://localhost:8080/docs` returns OpenAPI docs including sync endpoints
- [ ] `curl -X POST http://localhost:8080/api/agents/register -H "Content-Type: application/json" -d '{"agent_id":"test-001","hostname":"test","platform":"windows","version":"0.8.0"}'` returns status registered
- [ ] Manual test - create run, append events, upload files, download file (verify full workflow)
- [ ] `cd app/backend && pytest tests/test_sync_endpoints.py -v` shows all tests passed

## Technical Notes

**Architecture:** RESTful HTTP endpoints with idempotent operations. Batch event insert reduces database round trips. Multipart upload allows single request for multiple files with metadata manifest.

**Idempotency:** Upload endpoint checks SHA256 hash before uploading. Repeated uploads of unchanged files are skipped, returning status "skipped". This allows clients to retry safely without duplicating storage.

**Storage Integration:** Endpoints use dependency injection to get storage instance via `Depends(get_artifact_storage)`. This allows easy testing with mock storage and future storage backend changes.

**Don't assume not implemented:** Check if app/backend/routers/sync.py exists or if similar endpoints exist in other routers. May need to merge rather than replace.

## Non-Goals

- Server-Sent Events (SSE) streaming (Phase 6 with frontend)
- WebSocket support for real-time updates
- Proper API key authentication (stub only for now)
- Rate limiting or throttling
- Webhook notifications
