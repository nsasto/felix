# Chapter 2: The Outbox Pattern

## The Pattern That Powers Everything

Remember email? You hit "Send," close your laptop, and trust that your email client will eventually deliver the message. You don't sit there watching a progress bar.

**That's the outbox pattern.** And it's everywhere once you start looking:

- **PostgreSQL** - Write to WAL (Write-Ahead Log), then sync to replicas
- **Kafka** - Write to local log, then replicate to brokers
- **Mobile apps** - Queue actions locally, sync when connected
- **Your email client** - Outbox folder, literally

The pattern is simple: **Write locally, send asynchronously.**

## Why This Pattern Wins

### Compared to Synchronous Upload

```powershell
# Synchronous (bad)
Write-Artifacts
Upload-ToServer  # Blocks until complete (or fails)
Continue-Work    # Only if upload succeeded

# Outbox (good)
Write-Artifacts
Queue-Upload     # Non-blocking, always succeeds
Continue-Work    # Happens immediately
# Background: Send-Queue (retries until success)
```

**The difference:** In the outbox pattern, `Queue-Upload` never fails. It writes a file to disk. Disks don't randomly refuse writes the way networks randomly refuse connections.

### Compared to Message Queues

**RabbitMQ approach:**

```
Agent → RabbitMQ → Consumer → Database
```

**What can fail:**

- RabbitMQ connection
- RabbitMQ broker (disk full, crashed, misconfigured)
- Consumer connection
- Consumer processing logic

**Outbox approach:**

```
Agent → Filesystem → (same process) → Database
```

**What can fail:**

- Network (but we retry)
- Database (but we retry)

Notice: **No external dependencies.** The queue lives in the same filesystem the agent already depends on. If the filesystem is dead, the agent is already dead.

## Felix's Implementation

### The Queue Structure

```
.felix/
  outbox/
    register-agent-20260217-185116.jsonl
    run-a7b3c9d1-20260217-185117.jsonl
    run-f2e4a6b8-20260217-185125.jsonl
```

Each file is a queued HTTP request:

```json
{
  "method": "POST",
  "endpoint": "/api/runs",
  "body": {
    "id": "a7b3c9d1-5f2e-4a89-b3d1-8e9c7f5a4b2c",
    "requirement_id": "S-0001",
    "started_at": "2026-02-17T18:51:17Z",
    "finished_at": "2026-02-17T18:53:42Z",
    "exit_code": 0
  },
  "files": [
    { "path": "plan-S-0001.md", "sha256": "a3b5c7...", "size": 1024 },
    { "path": "output.log", "sha256": "d4e6f8...", "size": 4096 }
  ]
}
```

**Why JSONL (newline-delimited JSON)?**

- Each line is independent (partial reads don't corrupt data)
- Easy to stream (process line by line)
- Easy to debug (just `cat` the file)
- Standard format (works with `jq`, `grep`, etc.)

### The Lifecycle of a Queued Request

```
1. QUEUED     → File written to outbox/
2. SENDING    → HTTP request in flight
3. SUCCEEDED  → File deleted from outbox/
4. FAILED     → File remains, retry later
```

**Key insight:** The outbox is self-documenting. If a file exists, it hasn't been sent yet.

## The Retry Logic

Here's where it gets interesting. How often do you retry? Forever? Exponentially? With jitter?

### Felix's Strategy

```powershell
# Try immediately (optimistic path)
$success = Send-QueuedRequest $request

if (-not $success) {
    # Leave in outbox, will retry next time
    # "Next time" = start of next run
}
```

**Wait, that's it?** No exponential backoff? No retry loop?

Correct. Here's why:

**Felix runs are frequent.** If you're running Felix every few minutes, the retry happens naturally. No need for a background daemon polling the outbox.

**Felix runs are short-lived.** Each run is 1-3 minutes. A 5-second exponential backoff doesn't help – by the time you hit retry #3, the run is over.

**Felix failures are binary.** Either the backend is up (retry succeeds immediately) or it's down (retry fails immediately). It's not a 50% packet loss scenario.

### When Would You Need Exponential Backoff?

If Felix runs were:

- **Long-lived** (hours per run) - Need to retry within same run
- **Infrequent** (once per day) - Can't wait for next run to retry
- **High-rate** (hundreds per second) - Need to throttle retries

But Felix is none of these. So we keep it simple.

### The Upload Flow

```powershell
[void] FinishRun([hashtable]$summary) {
    # 1. Queue the request locally (always succeeds)
    $request = @{
        method   = "POST"
        endpoint = "/api/runs"
        body     = $summary
    }
    $this.QueueRequest($request)

    # 2. Try to send immediately (best-effort)
    $this.TrySendOutbox()

    # 3. Return immediately (don't wait for network)
}
```

**Critical detail:** `FinishRun()` returns before `TrySendOutbox()` completes. The agent continues while uploads happen in the background.

Well, "background" – it's the same process, but it's non-blocking from the agent's perspective. If the POST takes 5 seconds, the agent is already writing the next plan.

## Idempotency: The Secret Sauce

Here's a problem: What if a request times out, but actually succeeded?

```
1. Agent: POST /api/runs (request sent)
2. Backend: Writes to database (success!)
3. Network: Timeout before response arrives
4. Agent: "Failed, retry later"
5. Next run: POST /api/runs (duplicate?)
```

**Solution: SHA256 hashing**

Every file gets a SHA256 hash:

```powershell
$hash = (Get-FileHash $filePath -Algorithm SHA256).Hash
```

Backend checks before storing:

```sql
SELECT 1 FROM run_files
WHERE run_id = $1 AND path = $2 AND sha256 = $3
```

If exists: **Skip upload, return success.**

**Why this works:**

- Same file = same hash (cryptographically guaranteed)
- Backend can instantly check existence (indexed query)
- No duplicate storage
- Safe to retry infinitely

### The Hash Check Flow

```
Agent                           Backend
  |                               |
  |--- POST /api/runs ----------->|
  |    (includes SHA256s)         |
  |                               |
  |                        Check: Already have
  |                        a7b3c9d1.../plan.md?
  |                               |
  |                        YES: Skip upload
  |                        NO:  Store file
  |                               |
  |<-- 200 OK -------------------|
  |    { "uploaded": 2,           |
  |      "skipped": 1 }           |
```

**This is why our uploads are so fast.** Most files (boilerplate logs, standard headers) are duplicates. We only upload what's actually new.

## Handling Edge Cases

### What if the agent crashes mid-upload?

The outbox file remains. Next run picks it up and retries.

### What if the user deletes `.felix/outbox/`?

Those uploads are lost. This is acceptable – the local `runs/` directory still has everything.

### What if two agents run simultaneously?

Each agent has its own outbox files (timestamped filenames). No conflicts.

### What if the backend loses data?

Re-sync from local `runs/` directory. CLI is source of truth.

### What if disk is full?

Agent crashes anyway (can't write `runs/`). Sync failure is the least of your problems.

## The Beautiful Part

The outbox pattern makes network failures invisible to the agent. From the agent's perspective:

```powershell
$reporter.StartRun($metadata)      # Always succeeds
$reporter.AppendEvent($event)      # Always succeeds
$reporter.FinishRun($summary)      # Always succeeds
```

**There is no error handling** in the agent. No try/catch. No retry logic. No timeouts.

The sync plugin handles all of that, and the agent never knows the difference between:

- Upload succeeded immediately
- Upload queued for later
- Upload failed and will retry next run

**This is the power of separation of concerns.** The agent builds software. The plugin handles networks.

## The Pattern in Other Systems

Once you understand this pattern, you see it everywhere:

**Git:** You commit locally (outbox), then push when ready (send queue).

**Docker:** You build locally (outbox), then push to registry (send queue).

**Your IDE:** You edit in RAM (outbox), then save to disk (send queue).

**Eventual consistency is the default mode of the universe.** Distributed systems just make it explicit.

## What We Learned

### Lesson 1: Don't Fight the Network

Early implementations tried to guarantee delivery within the same run. This led to:

- Timeout hell (how long to wait?)
- Retry hell (how many times?)
- Complexity hell (what if partial success?)

**Solution:** Accept eventual consistency. Queue it and move on.

### Lesson 2: Embrace the Filesystem

We initially considered:

- SQLite database for queue
- In-memory queue with periodic flush
- Named pipes to background daemon

All of these are **more complex** than writing files. Files are:

- Easy to debug (`ls`, `cat`)
- Easy to monitor (file count)
- Easy to recover (copy files)
- Easy to test (create fake files)

**Solution:** Use the filesystem. It's not sexy, but it works.

### Lesson 3: Idempotency Is Not Optional

We learned this the hard way (see Chapter 7). Without SHA256 checks, network timeouts created duplicate uploads.

**Solution:** Hash everything. Check hashes. Trust hashes.

## Next Up: Implementation

You understand the pattern. Now let's see how it's implemented in PowerShell.

[Continue to Chapter 3: PowerShell Plugin →](03-cli-implementation.md)
