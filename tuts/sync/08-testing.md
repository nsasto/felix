# Chapter 8: Testing Distributed Systems

Testing sync is hard. You're testing:

- PowerShell client (CLI)
- HTTP networking (unreliable)
- Python backend (FastAPI)
- PostgreSQL database (stateful)
- Filesystem storage (stateful)

And all of these must work together, survive failures, and retry correctly.

## The Testing Philosophy

### What NOT to Do

**Anti-pattern: Unit test everything**

```powershell
Describe "QueueRequest" {
    It "writes file to outbox" {
        $reporter.QueueRequest($request)
        Test-Path ".felix\outbox\request.jsonl" | Should -Be $true
    }
}
```

This test is useless. It tests that PowerShell's `Set-Content` works. We know it does.

**What you actually care about:**

- Does the queue survive process crashes?
- Does retry work when backend is down?
- Does deduplication prevent duplicate uploads?
- Does rate limiting protect the server?

**Unit tests can't answer these questions.**

### What TO Do

**E2E tests that exercise the full stack:**

```powershell
# test-sync-happy-path.ps1

# 1. Start backend (real process)
Start-Process python -ArgumentList "app/backend/main.py"

# 2. Enable sync (real config)
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "http://localhost:8080"

# 3. Run agent (real execution)
felix run S-0000

# 4. Verify upload (real API query)
$response = Invoke-RestMethod -Uri "http://localhost:8080/api/runs"
$response.runs.Count | Should -BeGreaterThan 0

# 5. Verify database (real SQL query)
$result = psql -U postgres -d felix -c "SELECT COUNT(*) FROM runs"
$result | Should -Match "1"

# 6. Verify files (real filesystem)
Test-Path "storage/runs/$runId/plan-S-0000.md" | Should -Be $true
```

**This test is valuable.** It proves the entire system works end-to-end.

## The Test Suite

### 1. Happy Path Test

**File:** `scripts/test-sync-happy-path.ps1`

**What it tests:**

- Backend starts successfully
- Agent registers with backend
- Run artifacts upload successfully
- Database contains correct data
- Filesystem contains uploaded files
- Frontend can query runs

**Expected result:** Everything works, no errors.

**Why it matters:** If this fails, something fundamental is broken.

### 2. Network Failure Test

**File:** `scripts/test-sync-network-failure.ps1`

**What it tests:**

- Agent runs with backend DOWN
- Artifacts queue in outbox
- Agent completes successfully (doesn't crash)
- Backend starts later
- Next agent run triggers retry
- Queued artifacts upload successfully

**Expected result:** Outbox contains .jsonl files, then empties after backend recovery.

**The setup:**

```powershell
# Start agent with backend down
Stop-Process -Name "python" -Force  # Kill backend
felix run S-0000

# Verify queue populated
$queue = Get-ChildItem .felix\outbox\*.jsonl
$queue.Count | Should -BeGreaterThan 0

# Start backend
Start-Process python -ArgumentList "app/backend/main.py"
Start-Sleep -Seconds 5

# Run agent again (triggers retry)
felix run S-0001

# Verify queue drained
$queue = Get-ChildItem .felix\outbox\*.jsonl
$queue.Count | Should -Be 0
```

**Why it matters:** This is the core value of sync - resilience to network failures.

### 3. Idempotency Test

**File:** `scripts/test-sync-idempotency.ps1`

**What it tests:**

- Upload same run twice
- Backend handles duplicate gracefully
- No duplicate records in database
- Second upload is fast (skips duplicate files)

**The setup:**

```powershell
# First upload
felix run S-0000
$firstUploadTime = Measure-Command {
    felix run S-0000  # Same run
}

# Second upload (should be fast)
$secondUploadTime = Measure-Command {
    felix run S-0000  # Same run again
}

# Verify second upload was faster (skipped duplicates)
$secondUploadTime | Should -BeLessThan ($firstUploadTime / 2)

# Verify only one run in database
$count = psql -U postgres -d felix -c "SELECT COUNT(*) FROM runs WHERE requirement_id = 'S-0000'"
$count | Should -Be "1"
```

**Why it matters:** Proves SHA256 deduplication works, prevents data corruption on retry.

### 4. Concurrent Upload Test

**File:** `scripts/test-sync-concurrent.ps1`

**What it tests:**

- Multiple agents upload simultaneously
- No race conditions in database
- No corrupted files in storage
- All uploads complete successfully

**The setup:**

```powershell
# Start 5 agents simultaneously
$jobs = 1..5 | ForEach-Object {
    Start-Job -ScriptBlock {
        param($reqId)
        felix run $reqId
    } -ArgumentList "S-000$_"
}

# Wait for all to complete
$jobs | Wait-Job

# Verify all 5 runs in database
$count = psql -U postgres -d felix -c "SELECT COUNT(*) FROM runs"
$count | Should -Be "5"

# Verify no HTTP 500 errors in logs
$errors = Select-String -Path .felix\sync.log -Pattern "500"
$errors.Count | Should -Be 0
```

**Why it matters:** Real deployments have multiple agents running. Must handle concurrency correctly.

### 5. Rate Limit Test

**File:** `scripts/test-sync-rate-limit.ps1`

**What it tests:**

- Backend enforces 100 req/min limit
- Client receives 429 status
- Client retries after rate limit expires
- No data loss during rate limiting

**The setup:**

```powershell
# Send 120 requests rapidly
1..120 | ForEach-Object {
    $response = Invoke-WebRequest -Uri "http://localhost:8080/api/runs" -Method GET -ErrorAction SilentlyContinue
    if ($response.StatusCode -eq 429) {
        Write-Host "Rate limited at request $_"
    }
}

# Verify some requests were rate limited
$rateLimited = $responses | Where-Object { $_.StatusCode -eq 429 }
$rateLimited.Count | Should -BeGreaterThan 0

# Wait for rate limit to reset
Start-Sleep -Seconds 60

# Retry queued requests
felix run S-0000

# Verify request succeeded
$queue = Get-ChildItem .felix\outbox\*.jsonl
$queue.Count | Should -Be 0
```

**Why it matters:** Rate limiting protects backend from abuse. Must not lose data.

### 6. Large File Test

**File:** `scripts/test-sync-large-files.ps1`

**What it tests:**

- Upload runs with large log files (10MB+)
- Verify upload completes within timeout
- Verify SHA256 hash matches
- Verify Base64 encoding/decoding works

**The setup:**

```powershell
# Create run with large log file
$logPath = "runs\test-run\output.log"
1..100000 | ForEach-Object {
    "[2026-02-17 18:51:$_] INFO - Processing iteration $_" | Out-File $logPath -Append
}

# Verify file is large
$fileSize = (Get-Item $logPath).Length
$fileSize | Should -BeGreaterThan 10MB

# Upload run
$uploadTime = Measure-Command {
    felix run S-0000
}

# Verify completed within reasonable time (60s)
$uploadTime.TotalSeconds | Should -BeLessThan 60

# Verify uploaded file matches local file
$localHash = (Get-FileHash $logPath -Algorithm SHA256).Hash
$remoteHash = Invoke-RestMethod -Uri "http://localhost:8080/api/runs/test-run/files/output.log/hash"
$localHash | Should -Be $remoteHash
```

**Why it matters:** Real runs generate large logs. Must handle them efficiently.

### 7. Database Migration Test

**File:** `scripts/test-sync-migration.ps1`

**What it tests:**

- Old schema → new schema migration
- Existing data preserved
- New columns have correct defaults
- Rollback works if needed

**The setup:**

```powershell
# Create test data with old schema
psql -U postgres -d felix_test -c "INSERT INTO agents (id, name, hostname) VALUES (0, 'test', 'localhost')"

# Run migration 017
psql -U postgres -d felix_test -f app/backend/migrations/017_agent_adapter_metadata.sql

# Verify new columns exist
$columns = psql -U postgres -d felix_test -c "\d agents"
$columns | Should -Match "adapter"
$columns | Should -Match "executable"
$columns | Should -Match "model"

# Verify old data preserved
$result = psql -U postgres -d felix_test -c "SELECT name FROM agents WHERE id = 0"
$result | Should -Match "test"

# Verify new columns are NULL for old rows (default)
$result = psql -U postgres -d felix_test -c "SELECT adapter FROM agents WHERE id = 0"
$result | Should -Match "NULL"
```

**Why it matters:** Schema evolution must not break production.

## Testing Against Real Services

### Local Backend

Tests use a real FastAPI backend, not mocks:

```powershell
# Start backend in test mode
$env:DATABASE_URL = "postgresql://postgres:postgres@localhost/felix_test"
$env:STORAGE_PATH = "test_storage"
python app/backend/main.py &
```

**Why real backend?**

- Tests actual API contracts
- Tests actual database queries
- Tests actual error handling
- Tests actual performance

**Cost:** Tests are slower. Worth it.

### Test Database

Separate database for tests:

```bash
createdb felix_test
psql -U postgres -d felix_test -f app/backend/migrations/*.sql
```

**Between test runs:**

```bash
# Clean database
psql -U postgres -d felix_test -c "TRUNCATE runs, run_events, run_files, agents CASCADE"

# Or drop and recreate
dropdb felix_test
createdb felix_test
```

**Why separate database?**

- Can destroy without fear
- Can test migrations
- Parallel test runs possible

### Test Storage

Separate storage directory:

```powershell
$env:STORAGE_PATH = "test_storage"
```

**After tests:**

```powershell
Remove-Item -Recurse -Force test_storage
```

**Why separate storage?**

- Can delete without fear
- Can verify file structure
- No conflicts with dev data

## What We DON'T Test

### Things Covered by Framework Tests

- FastAPI routing (FastAPI tests this)
- Pydantic validation (Pydantic tests this)
- PostgreSQL queries (PostgreSQL tests this)
- PowerShell cmdlets (Microsoft tests this)

**We test our logic, not the frameworks.**

### Things Too Hard to Test Reliably

- Random network blips (too inconsistent)
- Database deadlocks (too rare)
- Disk full errors (too destructive)
- Security vulnerabilities (use scanners, not unit tests)

**We handle these with:**

- Retry logic (for transient failures)
- Transaction isolation (for deadlocks)
- Disk space monitoring (for disk full)
- Security reviews (for vulnerabilities)

## Test Automation

Tests run in CI/CD:

```yaml
# .github/workflows/test-sync.yml
name: Test Sync
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Start PostgreSQL
        run: |
          docker run -d \
            -e POSTGRES_PASSWORD=postgres \
            -e POSTGRES_DB=felix_test \
            -p 5432:5432 \
            postgres:15

      - name: Install dependencies
        run: |
          pip install -r app/backend/requirements.txt
          cd app/frontend && npm install

      - name: Run migrations
        run: |
          psql -U postgres -h localhost -d felix_test -f app/backend/migrations/*.sql

      - name: Run backend tests
        run: |
          pytest app/backend/tests/

      - name: Run E2E tests
        run: |
          pwsh scripts/test-sync-all.ps1
```

**Every commit runs tests.** Catches regressions early.

## Debugging Failed Tests

### When Tests Fail

1. **Check logs:**

   ```powershell
   cat .felix\sync.log
   cat app/backend/logs/app.log
   ```

2. **Check outbox:**

   ```powershell
   Get-Content .felix\outbox\*.jsonl | ConvertFrom-Json | Format-List
   ```

3. **Check database:**

   ```sql
   SELECT * FROM runs ORDER BY started_at DESC LIMIT 5;
   SELECT * FROM run_events WHERE run_id = '...';
   ```

4. **Check backend health:**

   ```powershell
   curl http://localhost:8080/health
   ```

5. **Enable verbose logging:**
   ```powershell
   $env:FELIX_LOG_LEVEL = "debug"
   felix run S-0000
   ```

### Common Test Failures

**"Connection refused"**

- Backend not started
- Wrong port (8080 vs 8000?)
- Firewall blocking

**"Database does not exist"**

- Forgot to create test database
- Wrong DATABASE_URL
- Migrations not run

**"Rate limit exceeded"**

- Previous test run didn't clean up
- Too many requests in test
- Rate limit too low for tests

**"Outbox not empty"**

- Previous test left files
- Network genuinely down
- Backend not processing queue

## Next: Operations Guide

You've seen how to test sync. Now let's see how to run it in production.

[Continue to Chapter 9: Operations Guide →](09-operations.md)
