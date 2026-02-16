# S-0061: Run Artifact Sync - CLI Plugin Implementation

**Priority:** High  
**Tags:** CLI, PowerShell, Sync, Plugin

## Description

As a Felix developer, I need a PowerShell sync plugin so that the CLI agent can optionally push run data to the server via an outbox queue pattern with automatic retry on network failures, without blocking agent execution.

## Dependencies

- S-0060 (Backend Sync Endpoints) - requires server API endpoints
- S-0057 (Run Artifact Sync Preparation) - requires config schema with sync section

## Acceptance Criteria

### Sync Interface Module

- [ ] File `.felix/core/sync-interface.ps1` created
- [ ] `IRunReporter` abstract class defined with lifecycle methods
- [ ] Method `RegisterAgent([hashtable]$agentInfo)` declared
- [ ] Method `StartRun([hashtable]$metadata)` declared returning string
- [ ] Method `AppendEvent([hashtable]$event)` declared
- [ ] Method `FinishRun([string]$runId, [hashtable]$result)` declared
- [ ] Method `UploadArtifact([string]$runId, [string]$relativePath, [string]$localPath)` declared
- [ ] Method `UploadRunFolder([string]$runId, [string]$runFolderPath)` declared
- [ ] Method `Flush()` declared for forcing delivery
- [ ] `NoOpReporter` class implements IRunReporter with empty methods
- [ ] `Get-RunReporter` factory function loads plugin from config

### NoOp Reporter Default

- [ ] `NoOpReporter` constructor logs "Sync disabled" at verbose level
- [ ] All `NoOpReporter` methods are no-ops (do nothing)
- [ ] `Get-RunReporter` returns NoOpReporter when sync not enabled
- [ ] `Get-RunReporter` returns NoOpReporter when config file missing
- [ ] `Get-RunReporter` checks FELIX_SYNC_ENABLED environment variable

### FastAPI Plugin Module

- [ ] File `.felix/plugins/sync-fastapi.ps1` created
- [ ] Sources sync-interface.ps1 at top
- [ ] `FastApiReporter` class implements IRunReporter
- [ ] Constructor accepts config hashtable (base_url, api_key)
- [ ] Constructor creates `.felix/outbox` directory if not exists
- [ ] Constructor stores BaseUrl, ApiKey, OutboxPath properties

### Agent Registration

- [ ] `RegisterAgent()` queues POST /api/agents/register request
- [ ] Calls `TrySendOutbox()` after queueing
- [ ] Agent info includes agent_id, hostname, platform, version, felix_root

### Run Lifecycle

- [ ] `StartRun()` generates client-side UUID for run_id
- [ ] `StartRun()` queues POST /api/runs request with metadata
- [ ] `StartRun()` calls TrySendOutbox and returns run_id
- [ ] `AppendEvent()` appends to run-specific outbox file (run-{runId}.jsonl)
- [ ] `FinishRun()` flushes pending events then queues finish request
- [ ] `FinishRun()` calls Flush() to ensure delivery

### Artifact Upload

- [ ] `UploadArtifact()` calculates SHA256 hash of file
- [ ] `UploadArtifact()` queues file metadata for batch upload
- [ ] `UploadRunFolder()` checks for standard artifacts (plan.md, report.md, output.log, etc.)
- [ ] `UploadRunFolder()` collects metadata for all found files
- [ ] `UploadRunFolder()` calls QueueBatchUpload with files array
- [ ] Batch upload queued as single request with all file metadata

### Outbox Queue Pattern

- [ ] `QueueRequest()` writes JSONL entry with timestamp
- [ ] Outbox filename format: {timestamp}.jsonl
- [ ] Batch upload filename format: {timestamp}-batch-upload.jsonl
- [ ] Run-specific events use filename: run-{runId}.jsonl
- [ ] `AppendToRunOutbox()` appends event lines to run file

### Outbox Delivery

- [ ] `TrySendOutbox()` lists all .jsonl files in outbox sorted by name
- [ ] Processes files in order (oldest first)
- [ ] Detects batch upload requests by checking for files property
- [ ] Calls `UploadBatch()` for file uploads
- [ ] Calls `SendJsonRequest()` for regular JSON requests
- [ ] Deletes outbox file after successful send
- [ ] Breaks loop on error, preserves remaining files for retry
- [ ] Logs warning on sync failure without throwing

### HTTP Communication

- [ ] `SendJsonRequest()` uses Invoke-RestMethod with POST method
- [ ] Includes Authorization header if api_key configured
- [ ] Sets Content-Type: application/json header
- [ ] 10 second timeout for regular requests
- [ ] Logs request failure but doesn't throw

### Batch File Upload

- [ ] `UploadBatch()` builds manifest array from files property
- [ ] Manifest includes path, sha256, size_bytes, content_type per file
- [ ] Creates PowerShell form hashtable for multipart upload
- [ ] Adds each file to form by relative_path as field name
- [ ] Adds manifest as JSON string to form.manifest field
- [ ] Uses Invoke-RestMethod with -Form parameter
- [ ] 120 second timeout for batch upload
- [ ] Skips missing files with warning (file deleted after queuing)

### Content Type Detection

- [ ] `Get-ContentType()` function returns appropriate MIME type
- [ ] .md files return "text/markdown"
- [ ] .log files return "text/plain; charset=utf-8"
- [ ] .txt files return "text/plain; charset=utf-8"
- [ ] .patch files return "text/x-patch"
- [ ] .json files return "application/json"
- [ ] Default returns "application/octet-stream"

### Plugin Factory

- [ ] `New-PluginReporter()` function creates FastApiReporter instance
- [ ] Accepts config hashtable parameter
- [ ] Returns configured reporter object

### Agent Integration

- [ ] `.felix/felix-agent.ps1` sources sync-interface.ps1 at startup
- [ ] Calls `Get-RunReporter` to initialize global $SyncReporter
- [ ] Calls `RegisterAgent()` with agent metadata
- [ ] Wraps registration in try/catch to handle failures gracefully

## Validation Criteria

- [ ] `. .felix/core/sync-interface.ps1; $r = Get-RunReporter; Write-Host $r.GetType().Name` outputs NoOpReporter (when disabled)
- [ ] Set sync enabled in config, verify `Get-RunReporter` returns FastApiReporter
- [ ] Manual test - run agent with sync enabled, verify `.felix/outbox/*.jsonl` files created
- [ ] Manual test - verify outbox files disappear after successful sync
- [ ] Manual test - stop backend, run agent, verify outbox files persist
- [ ] Manual test - restart backend, run agent again, verify old outbox files sent

## Technical Notes

**Architecture:** Plugin pattern with interface abstraction allows future sync providers (e.g., webhook, S3 upload). Outbox queue provides reliability without blocking agent execution.

**Reliability:** JSONL format allows appending events without parsing entire file. Timestamp-based filenames ensure ordering. Network failures leave files in outbox for eventual delivery.

**Performance:** Batch upload reduces HTTP requests from 7-10 per run to 1 request. Automatic gzip compression via Accept-Encoding header handled by PowerShell.

**Don't assume not implemented:** Check if .felix/core/ or .felix/plugins/ already have sync-related files. May need to merge with existing plugin infrastructure.

## Non-Goals

- Sync plugin for other languages (Python, C#)
- Webhook or push-based sync (pull-based only)
- Encryption of artifacts in transit (relies on HTTPS)
- Compression of individual files (HTTP gzip only)
- Progress indication for uploads
