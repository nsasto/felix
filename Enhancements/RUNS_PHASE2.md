# Run Artifact Sync - Phase 2 Improvements

**Version:** 0.1.0  
**Status:** 🟡 Planned  
**Last Updated:** 2026-02-18

---

## Executive Summary

Phase 1 successfully implemented run artifact sync with outbox queue for eventual consistency. However, production usage has revealed a **stale outbox file problem**: permanent failures (401/403/404) remain in the outbox indefinitely, polluting logs on every sync attempt and creating confusion for users.

This document outlines the problem and proposed solutions for Phase 2.

---

## Problem Statement

### Current Behavior

When the sync plugin encounters a permanent error (HTTP 400/401/403/404/422), it:

1. **Logs an error** to console and sync.log
2. **Keeps the file in outbox** (line 701 in http-client.ps1: "Permanent API failure - file remains in outbox")
3. **Continues to next file** (doesn't block other operations)
4. **Retries on EVERY sync operation** (agent registration, run start, event flush)

**Example scenario:**

```powershell
# Old run created file with invalid data:
.felix/outbox/20260218135640494.jsonl
{
  "body": {
    "project_id": "default"  # Invalid - should be git_url
  }
}

# This file gets retried on EVERY TrySendOutbox() call:
# - Every agent startup (agent registration)
# - Every run start (StartRun)
# - Every 5 seconds (event flush timer)

# Result: Logs show "Sync permanently failed (HTTP 403)" even though current run works fine
```

### Why This Happens

1. **Schema evolution**: Early implementation used `project_id` before switching to `git_url` authentication
2. **Agent crashes**: Partial writes or interrupted serialization create corrupt JSON
3. **API changes**: Backend endpoint changes (e.g., `/api/runs` requires new field)
4. **Invalid credentials**: Revoked API keys, project permissions changed

### Impact

- **Log pollution**: Error messages on every sync operation confuse users
- **Performance**: Wasted CPU/network retrying requests that will never succeed
- **Debugging difficulty**: Real errors hidden among stale file errors
- **Storage waste**: Failed files accumulate over time

---

## Proposed Solutions

### Option 1: Dead Letter Queue (Recommended)

Move permanent failures to a separate directory after first failure.

**Implementation:**

```powershell
# After detecting permanent error (lines 694-708):
if ($isPermanentFailure) {
    $failedDir = Join-Path $this.OutboxPath "failed"
    New-Item -ItemType Directory -Path $failedDir -Force -ErrorAction SilentlyContinue
    
    $failedPath = Join-Path $failedDir $file.Name
    Move-Item -Path $file.FullName -Destination $failedPath -Force
    
    $this.WriteLog("WARNING", "Moved permanently failed request to: failed/$($file.Name)")
    
    # Only emit user-visible error ONCE (on move, not every retry)
    if (Get-Command Emit-Log -ErrorAction SilentlyContinue) {
        Emit-Log -Level "error" -Message "Sync permanently failed (HTTP $lastStatusCode): $lastError" -Component "sync" | Out-Null
    }
}
```

**Benefits:**

- ✅ Errors shown only once (when moved to failed/)
- ✅ Files preserved for debugging/investigation
- ✅ Main outbox stays clean (only active retries)
- ✅ Easy to implement (10 lines of code)
- ✅ Manual recovery: move file back to outbox/ if backend fixed

**Tradeoffs:**

- ⚠️ User must manually clean up `.felix/outbox/failed/` directory
- ⚠️ Could accumulate old failures over time

### Option 2: TTL-Based Cleanup

Delete files older than configurable threshold (default: 24 hours).

**Implementation:**

```powershell
# In TrySendOutbox(), before processing files:
$ttlHours = 24  # Configurable via config.json
$cutoffTime = (Get-Date).AddHours(-$ttlHours)

$staleFiles = Get-ChildItem -Path $this.OutboxPath -Filter "*.jsonl" -File |
    Where-Object { $_.CreationTime -lt $cutoffTime }

foreach ($stale in $staleFiles) {
    $this.WriteLog("INFO", "Deleting stale outbox file (older than ${ttlHours}h): $($stale.Name)")
    Remove-Item -Path $stale.FullName -Force
}
```

**Benefits:**

- ✅ Automatic cleanup (no manual intervention)
- ✅ Prevents unbounded storage growth
- ✅ Simple time-based policy

**Tradeoffs:**

- ⚠️ Deletes files that could have succeeded later (e.g., after network restored)
- ⚠️ Loses diagnostic data for troubleshooting
- ⚠️ Arbitrary TTL may delete files too soon or too late

### Option 3: Max Permanent Retry Limit

Delete after seeing same permanent error N consecutive times (default: 3).

**Implementation:**

```powershell
# Add retry counter to filename: 20260218135640494.jsonl.retry1
# Or maintain separate metadata file: .felix/outbox/.retry-counts.json

if ($isPermanentFailure) {
    $retryCount = $this.GetRetryCount($file.Name)
    $retryCount++
    
    if ($retryCount -ge $this.MaxPermanentRetries) {
        $this.WriteLog("INFO", "Deleting file after $retryCount permanent failures: $($file.Name)")
        Remove-Item -Path $file.FullName -Force
    }
    else {
        $this.SaveRetryCount($file.Name, $retryCount)
    }
}
```

**Benefits:**

- ✅ Gives multiple chances (handles flaky backend)
- ✅ Eventually cleans up persistent failures
- ✅ Configurable threshold per environment

**Tradeoffs:**

- ⚠️ More complex (requires metadata storage)
- ⚠️ Retry count persists across agent restarts (file-based state)
- ⚠️ Edge case: what if backend fixed after 2 failures? File deleted on 3rd try

### Option 4: Schema Validation Pre-Queue

Validate request structure BEFORE writing to outbox.

**Implementation:**

```powershell
# In StartRun() before QueueRequest():
if ($metadata.project_id -eq "default") {
    throw "Invalid project_id 'default' - use git_url for authentication"
}

if (-not $metadata.git_url -and -not $metadata.project_id) {
    throw "Either git_url or project_id must be provided"
}

# In QueueRequest():
if (-not $request.method -or -not $request.endpoint) {
    throw "Invalid request structure: missing method or endpoint"
}
```

**Benefits:**

- ✅ Prevents bad data from entering queue (fail fast)
- ✅ Better error messages at source (not buried in sync logs)
- ✅ No cleanup needed (never created)

**Tradeoffs:**

- ⚠️ Doesn't help with schema evolution (old files already queued)
- ⚠️ Requires maintaining validation rules (duplicate logic)
- ⚠️ Could break on API changes (tight coupling)

---

## Recommendation

**Implement Option 1 (Dead Letter Queue) + Option 4 (Schema Validation)**

**Rationale:**

1. **Option 1** solves the immediate problem (log pollution) and preserves diagnostic data
2. **Option 4** prevents future occurrences by catching errors early
3. Combined approach: prevent new bad files, isolate existing bad files
4. Low complexity, high value

**Future enhancement:** Add TTL cleanup (Option 2) for `.felix/outbox/failed/` directory to prevent unbounded growth.

---

## Implementation Plan

### Phase 2.1: Dead Letter Queue

**Changes:**

- Modify `TrySendOutbox()` in http-client.ps1 (lines 694-708)
- Move permanently failed files to `.felix/outbox/failed/`
- Emit user error only once (on move, not every retry)
- Update AGENTS.md troubleshooting section

**Testing:**

```powershell
# Create invalid request file
echo '{"method":"POST","endpoint":"/api/runs","body":{"project_id":"invalid"}}' > .felix/outbox/test.jsonl

# Start agent - should move to failed/ on first 403
felix run s-0000 --sync

# Verify file moved
Test-Path .felix/outbox/failed/test.jsonl  # Should be True
Test-Path .felix/outbox/test.jsonl         # Should be False
```

**Validation criteria:**

- [ ] Permanent failures moved to `failed/` subdirectory
- [ ] Error message shown once (not on every retry)
- [ ] Subsequent sync operations don't retry failed files
- [ ] Main outbox contains only active/transient failures
- [ ] Failed files can be manually moved back for retry

### Phase 2.2: Schema Validation

**Changes:**

- Add validation to StartRun() in http-client.ps1
- Add validation to AppendEvent()
- Add validation to QueueArtifactBatch()
- Validate before QueueRequest() call

**Testing:**

```powershell
# Try to start run with invalid project_id
$Data = @{
    Requirement = @{ id = "S-0001" }
    AgentConfig = @{ id = "39535ce5-e344-5a8c-9f3f-44776b998939" }
    Config = @{ sync = @{ enabled = $true } }
}

# Should throw before queuing
try {
    StartRun(@{ project_id = "default" })
    Write-Error "Should have thrown validation error"
}
catch {
    Write-Host "✅ Validation working: $_"
}
```

**Validation criteria:**

- [ ] Invalid `project_id` rejected before queuing
- [ ] Missing `git_url` and `project_id` rejected
- [ ] Invalid request structure rejected
- [ ] Validation errors surface to user immediately
- [ ] No invalid files created in outbox

### Phase 2.3: Documentation Updates

**Files to update:**

- **AGENTS.md**: Add section on failed outbox files
- **docs/SYNC_OPERATIONS.md**: Document dead letter queue
- **.felix/plugins/sync-http/README.md**: Explain failed/ directory
- **RELEASE_NOTES.md**: Document Phase 2 changes

---

## Success Metrics

**Before (Phase 1):**

- Stale outbox file causes error log every 5 seconds
- User sees "Sync permanently failed" on every run
- Support burden: "Why am I seeing sync errors?"

**After (Phase 2):**

- Permanent failures shown once, then silent
- Clean outbox = only active retries
- Failed files isolated for investigation
- Validation prevents new invalid files

**Metrics to track:**

- Count of files in `outbox/failed/` over time
- Frequency of schema validation errors
- User-reported sync error confusion (should decrease)

---

## Future Considerations

### Phase 3: Automated Recovery

- **Retry schedule**: Check failed/ directory on agent startup, retry if older than 6 hours
- **Backend health check**: Ping backend before retrying failed files
- **Smart validation**: Compare failed request schema to current API schema, auto-migrate if compatible

### Phase 4: Observability

- **Sync dashboard**: CLI command to show outbox status (`felix sync status`)
- **Metrics export**: Count of queued/failed/succeeded requests
- **Alerting**: Notify when failed/ directory exceeds threshold

---

## References

- **RUNS_IMPLEMENTATION.md**: Phase 1 implementation details
- **RUNS_BASELINE.md**: Original requirements and architecture
- **.felix/plugins/sync-http/http-client.ps1**: Outbox queue implementation (lines 556-730)
- **docs/SYNC_OPERATIONS.md**: Operational procedures for sync system
