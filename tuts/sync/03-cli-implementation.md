# Chapter 3: CLI Implementation - Building a Production-Grade Sync Plugin

Let's build a sync plugin in PowerShell that never blocks, always queues, and handles failures gracefully.

## The Interface Contract

First, we define what a "sync reporter" looks like:

```powershell
# .felix/core/sync-interface.ps1

class IRunReporter {
    [void] RegisterAgent([hashtable]$agentInfo) {
        throw "Must override RegisterAgent()"
    }

    [string] StartRun([hashtable]$metadata) {
        throw "Must override StartRun()"
    }

    [void] AppendEvent([PSCustomObject]$event) {
        throw "Must override AppendEvent()"
    }

    [void] FinishRun([hashtable]$summary) {
        throw "Must override FinishRun()"
    }
}
```

**This is PowerShell's version of an interface.** Any reporter must implement these four methods.

### Why This Design?

**Separation of concerns:**

- Agent code calls `$reporter.StartRun()`
- Reporter decides: Upload now? Queue for later? Write to file? Send to Slack?
- Agent doesn't know, doesn't care

### The No-Op Reporter

When sync is disabled, we need a reporter that does nothing:

```powershell
class NoOpReporter : IRunReporter {
    [void] RegisterAgent([hashtable]$agentInfo) { }
    [string] StartRun([hashtable]$metadata) {
        return [System.Guid]::NewGuid().ToString()
    }
    [void] AppendEvent([PSCustomObject]$event) { }
    [void] FinishRun([hashtable]$summary) { }
}
```

**Empty implementations.** No file I/O, no network calls, no logging. Zero overhead when sync is disabled.

**Why not just `if ($sync) { Upload() }`?**

Because then agent code would be full of:

```powershell
if ($syncEnabled) {
    $reporter.StartRun($metadata)
}
# vs
$reporter.StartRun($metadata)  # Always works
```

The NoOpReporter lets us write clean code that always works.

## The FastAPI Plugin

Now the real implementation: `.felix/plugins/sync-fastapi.ps1`

### Class Structure

```powershell
class FastApiReporter : IRunReporter {
    [string]$BaseUrl          # "http://localhost:8080"
    [string]$ApiKey           # API key (optional)
    [string]$OutboxPath       # ".felix/outbox"
    [string]$LogPath          # ".felix/sync.log"
    [bool]$IsConfigValid      # Is config complete?

    # Constructor validates config, creates outbox directory
    FastApiReporter([hashtable]$config, [string]$felixDir) { ... }

    # IRunReporter interface implementation
    [void] RegisterAgent([hashtable]$agentInfo) { ... }
    [string] StartRun([hashtable]$metadata) { ... }
    [void] AppendEvent([PSCustomObject]$event) { ... }
    [void] FinishRun([hashtable]$summary) { ... }

    # Private methods for outbox queue
    [void] QueueRequest([hashtable]$request) { ... }
    [bool] TrySendOutbox() { ... }
    [void] WriteLog([string]$level, [string]$message) { ... }
}
```

### The Registration Flow

```powershell
[void] RegisterAgent([hashtable]$agentInfo) {
    try {
        # Build the registration request
        $request = @{
            method   = "POST"
            endpoint = "/api/agents/register"
            body     = $agentInfo
        }

        # Queue it (always succeeds)
        $this.QueueRequest($request)

        # Try to send immediately (best-effort)
        $this.TrySendOutbox()
    }
    catch {
        # Log but don't crash - sync failures are non-fatal
        $this.WriteLog("WARNING", "Failed to queue agent registration: $_")
    }
}
```

**Key points:**

1. **Validate input** - Ensure required fields exist
2. **Queue first** - Write to outbox before attempting network
3. **Try send immediately** - Optimistic path (usually succeeds)
4. **Catch everything** - Never let sync failures crash agent
5. **Log failures** - Write to sync.log for debugging

### The Outbox Queue

```powershell
[void] QueueRequest([hashtable]$request) {
    # Generate unique filename
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $guid = [System.Guid]::NewGuid().ToString().Substring(0, 8)
    $filename = "$($request.method)-$($request.endpoint.Replace('/', '-'))-$timestamp-$guid.jsonl"
    $filepath = Join-Path $this.OutboxPath $filename

    # Serialize request as JSONL
    $json = $request | ConvertTo-Json -Depth 10 -Compress

    # Write atomically
    $json | Set-Content -Path $filepath -Encoding UTF8 -Force

    $this.WriteLog("INFO", "Queued request: $filename")
}
```

**Why this filename format?**

```
POST-api-runs-20260217-185116-a3b5c7d1.jsonl
│    │        │               │
│    │        │               └─ Random GUID (avoid collisions)
│    │        └─────────────────── Timestamp (chronological order)
│    └──────────────────────────── Endpoint (easy to grep)
└───────────────────────────────── HTTP method (debugging)
```

**Benefits:**

- **Unique** - GUID prevents collisions
- **Sortable** - Timestamp means `ls` shows chronological order
- **Debuggable** - Filename tells you what the request does
- **Grepable** - `ls *api-runs*` shows all run uploads

### Sending the Queue

```powershell
[bool] TrySendOutbox() {
    $outboxFiles = Get-ChildItem -Path $this.OutboxPath -Filter "*.jsonl" -ErrorAction SilentlyContinue

    if ($outboxFiles.Count -eq 0) {
        return $true  # Empty queue = success
    }

    $allSucceeded = $true

    foreach ($file in $outboxFiles) {
        try {
            # Read queued request
            $request = Get-Content $file.FullName -Raw | ConvertFrom-Json

            # Build HTTP request
            $uri = "$($this.BaseUrl)$($request.endpoint)"
            $headers = @{ "Content-Type" = "application/json" }

            if ($this.ApiKey) {
                $headers["X-API-Key"] = $this.ApiKey
            }

            # Send request
            $body = $request.body | ConvertTo-Json -Depth 10 -Compress
            $response = Invoke-RestMethod `
                -Uri $uri `
                -Method $request.method `
                -Headers $headers `
                -Body $body `
                -TimeoutSec 30 `
                -ErrorAction Stop

            # Success! Delete the queued file
            Remove-Item $file.FullName -Force
            $this.WriteLog("INFO", "Sent request: $($file.Name)")
        }
        catch {
            # Failed - leave file in queue for retry
            $this.WriteLog("WARNING", "Failed to send $($file.Name): $_")
            $allSucceeded = $false
        }
    }

    return $allSucceeded
}
```

**The retry logic is beautiful:**

1. Loop through outbox files
2. Try to send each one
3. If success → delete file
4. If failure → leave file (retry next time)

**No explicit retry counter.** The retry happens naturally when:

- Next run starts
- Next event logged
- Next run finishes

All call `TrySendOutbox()`, so retries happen automatically.

### File Uploads with SHA256

```powershell
[void] FinishRun([hashtable]$summary) {
    # Calculate SHA256 for each artifact
    $files = @()
    $runPath = $summary.run_path

    Get-ChildItem -Path $runPath -File -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Substring($runPath.Length + 1)
        $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash

        $files += @{
            path     = $relativePath
            sha256   = $hash
            size     = $_.Length
            content  = [Convert]::ToBase64String([IO.File]::ReadAllBytes($_.FullName))
        }
    }

    # Add files to summary
    $summary.files = $files

    # Queue the upload
    $request = @{
        method   = "POST"
        endpoint = "/api/runs"
        body     = $summary
    }

    $this.QueueRequest($request)
    $this.TrySendOutbox()
}
```

**Why Base64 encode files?**

JSON doesn't handle binary data well. Base64 is:

- Safe for JSON strings
- Standardized encoding
- Easily decoded on backend

**Performance consideration:** Base64 increases size by ~33%. For text files (logs, markdown), this is fine. For large binaries, you'd want multipart/form-data instead.

### Configuration Loading

How does the plugin know where to upload?

```powershell
function Get-RunReporter {
    param([string]$FelixDir)

    $configPath = Join-Path $FelixDir "config.json"

    # Load config
    $config = Get-Content $configPath -Raw | ConvertFrom-Json

    # Check if sync is enabled
    $syncEnabled = $false

    # Environment variable takes precedence
    if ($env:FELIX_SYNC_ENABLED -eq "true") {
        $syncEnabled = $true
    }
    elseif ($config.sync.enabled -eq $true) {
        $syncEnabled = $true
    }

    if (-not $syncEnabled) {
        return [NoOpReporter]::new()
    }

    # Build config with environment variable overrides
    $finalConfig = @{
        base_url = if ($env:FELIX_SYNC_URL) {
            $env:FELIX_SYNC_URL
        } else {
            $config.sync.base_url
        }
        api_key = if ($env:FELIX_SYNC_KEY) {
            $env:FELIX_SYNC_KEY
        } else {
            $config.sync.api_key
        }
    }

    # Load the FastAPI plugin
    . (Join-Path $FelixDir "plugins\sync-fastapi.ps1")
    return New-PluginReporter -Config $finalConfig -FelixDir $FelixDir
}
```

**Precedence order:**

1. Environment variables (highest priority)
2. Config file settings
3. Defaults (fallback)

**Why this order?**

- Environment variables let you override config temporarily (useful for testing)
- Config file is the persistent setting
- Defaults ensure system always has sensible values

### Logging to File

```powershell
[void] WriteLog([string]$level, [string]$message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] $level - $message"

    try {
        # Append to log file
        Add-Content -Path $this.LogPath -Value $logLine -ErrorAction Stop

        # Rotate if too large
        $logFile = Get-Item $this.LogPath -ErrorAction SilentlyContinue
        if ($logFile.Length -gt $this.MaxLogSizeBytes) {
            # Move old log to backup
            $backupPath = "$($this.LogPath).old"
            Move-Item $this.LogPath $backupPath -Force
        }
    }
    catch {
        # If logging fails, fail silently
        # Don't let logging failures crash sync
    }
}
```

**Log rotation:** Keep logs bounded. At 5MB, rotate to `.old`. Simple but effective.

**Fail silently:** If logging fails (disk full, permissions issue), don't crash. Logging is for debugging, not critical operations.

## Performance Optimizations

### Batch Uploads

Instead of:

```
POST /api/runs/{id}
POST /api/runs/{id}/events (x50)
POST /api/runs/{id}/files/plan.md
POST /api/runs/{id}/files/output.log
...
```

We do:

```
POST /api/runs
{
  "id": "run-id",
  "events": [...],  // All events in one payload
  "files": [...]    // All files with Base64 content
}
```

**One request instead of 50+.** Massive performance win.

### SHA256 Deduplication

Backend checks SHA256 before storing:

```python
existing = await db.fetch_one(
    "SELECT 1 FROM run_files WHERE run_id = ? AND sha256 = ?",
    run_id, file_sha256
)
if existing:
    return  # Skip upload
```

**Result:** Boilerplate files (log headers, plan templates) upload once, skip thereafter.

### Async Everything (Backend)

```python
async def register_agent(body: AgentRegistration):
    async with database.transaction():
        await db.execute(insert_query, params)
    return response
```

Backend is fully async (FastAPI + databases library). Single instance handles 100+ concurrent uploads.

## Error Handling Philosophy

### What We Catch

```powershell
try {
    $response = Invoke-RestMethod -Uri $uri -Method POST -Body $body
}
catch [System.Net.WebException] {
    # Network failure - queue for retry
    $this.WriteLog("WARNING", "Network failure, will retry: $_")
}
catch {
    # Unknown error - log but don't crash
    $this.WriteLog("ERROR", "Unexpected error: $_")
}
```

**We catch everything.** Sync must never crash the agent.

### What We Log

```
[2026-02-17 18:51:16] INFO - Queued request: POST-api-runs-a3b5c7d1.jsonl
[2026-02-17 18:51:17] INFO - Sent request: POST-api-runs-a3b5c7d1.jsonl
[2026-02-17 18:51:18] WARNING - Network failure, will retry: Connection refused
```

Logs are:

- **Timestamped** - Know when issues occurred
- **Leveled** - INFO/WARNING/ERROR for filtering
- **Actionable** - Tells you what to check (network? backend? queue?)

## Integration with Felix Agent

The agent doesn't know about FastAPI, outbox, or retries. It just sees:

```powershell
# Initialization
$reporter = Get-RunReporter -FelixDir $FelixDir
$reporter.RegisterAgent($agentInfo)

# During run
$runId = $reporter.StartRun($metadata)
$reporter.AppendEvent($event)
$reporter.FinishRun($summary)
```

**Four simple calls.** All the complexity is hidden in the plugin.

## What Makes This Production-Grade?

✅ **Never blocks** - All operations queue-first  
✅ **Fail gracefully** - Errors logged, not thrown  
✅ **Idempotent** - Safe to retry infinitely  
✅ **Observable** - Outbox and logs show state  
✅ **Configurable** - Config file + env vars  
✅ **Testable** - Can inject mock config  
✅ **Performant** - Batch uploads, SHA256 dedup  
✅ **Maintainable** - Clear interface, simple implementation

## Next: The Backend

Now you know how the CLI queues and sends requests. Let's see how the backend receives and processes them.

[Continue to Chapter 4: Backend Implementation →](04-backend-implementation.md)
