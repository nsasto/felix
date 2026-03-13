# Chapter 1: The Big Picture

## The Problem We're Solving

You're sitting at your desk. Felix is running on your machine, autonomously working through requirements. It's writing plans, running tests, generating diffs. Everything is local, everything is fast, everything works offline.

But your teammate across the office has no idea what Felix just accomplished. Your manager can't see progress. When you go home, those run artifacts are trapped on your work laptop.

**Classic problem:** Local tools need to share data with a team.

## How Most People Solve This (And Why They're Wrong)

### The Naive Approach

```powershell
# After completing a task, upload it
Write-RunArtifacts
Upload-ToServer  # ← This line ruins everything
```

**What happens when the server is down?** The agent crashes. Or hangs. Or retries forever while the user watches a spinner.

You just turned a perfectly good local tool into a distributed system with all the failure modes that implies.

### The "Just Use a Message Queue" Approach

Some people say: "Use RabbitMQ! Use Kafka! Problem solved!"

Except now you need to:

- Run a message broker (another service to maintain)
- Handle broker failures (what if RabbitMQ is down?)
- Manage queue persistence (disk full? lost messages?)
- Deal with consumer lag (queue backlogged? data delayed?)

You traded one distributed system problem for five distributed system problems.

### The Webhook Approach

"Just POST to a webhook when done!"

```powershell
Invoke-RestMethod -Method POST -Uri $WebhookUrl -Body $data
```

Looks simple. But:

- If the POST fails, did you log it? Retry it? Queue it?
- If the POST times out (30 seconds? 60? forever?), does the agent wait?
- If the server returns 500, do you retry? How many times?
- What if the network is flaky and succeeds on retry #4?

You just built an outbox queue pattern... badly.

## The Right Way: Outbox Pattern

Here's the insight that makes everything work:

**Separate writing from sending.**

Felix works like this:

```
1. Agent writes files locally        ← Always succeeds (local disk)
2. Plugin queues sync request         ← Always succeeds (local file)
3. Background process sends queue     ← Eventually succeeds (retries forever)
```

The agent never waits. The agent never fails because of sync. The agent doesn't even know if sync succeeded.

**This is the outbox pattern**, and it's how every major distributed system actually works under the hood:

- Kafka itself uses it (write to local log, then replicate)
- Databases use it (write to WAL, then sync to replicas)
- Email uses it (write to outbox, then SMTP sends)

## Felix Sync Architecture

```
┌─────────────────────────────────────────────────────┐
│  Developer's Machine                                 │
│                                                      │
│  ┌──────────────────────────────────────┐          │
│  │  Felix Agent (PowerShell)             │          │
│  │                                       │          │
│  │  1. Run requirement                   │          │
│  │  2. Write artifacts to runs/          │          │
│  │  3. Call: $reporter.FinishRun()       │          │
│  └──────────────┬───────────────────────┘          │
│                 │                                    │
│                 ▼                                    │
│  ┌──────────────────────────────────────┐          │
│  │  Sync Plugin (sync-http.ps1)          │          │
│  │                                       │          │
│  │  • Queue request → .felix/outbox/*.jsonl │       │
│  │  • SHA256 hash artifacts               │          │
│  │  • Try send immediately                │          │
│  │  • If fails: retry later               │          │
│  └──────────────┬───────────────────────┘          │
│                 │                                    │
│                 │ HTTP POST                          │
│                 │ (with retries)                     │
└─────────────────┼────────────────────────────────────┘
                  │
                  │ Internet (maybe?)
                  │
┌─────────────────▼────────────────────────────────────┐
│  Team Server                                          │
│                                                       │
│  ┌──────────────────────────────────────┐           │
│  │  FastAPI Backend                      │           │
│  │                                       │           │
│  │  • POST /api/runs                     │           │
│  │  • Verify API key                     │           │
│  │  • Rate limit (100/min)               │           │
│  │  • Dedupe by SHA256                   │           │
│  │  • Store in PostgreSQL + filesystem   │           │
│  └──────────────┬───────────────────────┘           │
│                 │                                     │
│                 ▼                                     │
│  ┌──────────────────────────────────────┐           │
│  │  Storage Layer                        │           │
│  │                                       │           │
│  │  • PostgreSQL: runs, events, files    │           │
│  │  • Filesystem: storage/runs/{run-id}  │           │
│  └───────────────────────────────────────┘           │
│                                                       │
└───────────────────────────────────────────────────────┘
                  │
                  │ HTTP GET
                  ▼
┌─────────────────────────────────────────────────────┐
│  React Frontend (any browser)                        │
│                                                      │
│  • View runs list                                    │
│  • Browse artifacts (split-view file explorer)       │
│  • Event timeline                                    │
│  • Markdown rendering                                │
└──────────────────────────────────────────────────────┘
```

## Key Architectural Decisions

### 1. **CLI is the Source of Truth**

The agent writes `runs/` directory first. Always. The backend is just a mirror.

**Why?** If the backend loses data, you can re-sync from local runs. If local disk fails, that machine's work is lost anyway (standard developer risk).

### 2. **Idempotent Uploads**

Every file has a SHA256 hash. Backend checks: "Do I already have this exact file?" If yes, skip upload.

**Why?** Network failures happen mid-upload. Retries shouldn't duplicate data. Plus, most runs have identical log headers – deduplication saves bandwidth.

### 3. **No Acknowledgment Required**

Agent never waits for "upload successful." It queues the request and moves on.

**Why?** The agent's job is to build software, not wait for networks. If sync fails, that's an ops problem, not a development blocker.

### 4. **Outbox Queue Lives in Filesystem**

Queue is `.felix/outbox/*.jsonl` – plain NDJSON files.

**Why?** Simple. Debuggable. No dependencies. Survives process crashes. Easy to inspect: `cat .felix/outbox/*.jsonl`

### 5. **Registration Before Runs**

Agent registers (sends metadata: platform, adapter, model) before starting work.

**Why?** Backend needs to know which agent created which runs. Plus, registration acts as a heartbeat – backend knows which agents are alive.

### 6. **Batch Uploads**

One run = one HTTP request with all artifacts + events.

**Why?** 50 small requests = 50× rate-limit consumption + 50× network overhead. One batch = one transaction, faster and more reliable.

## What This Architecture Gets You

✅ **Works offline** - Agent continues when server is down  
✅ **Resilient** - Network failures don't crash the agent  
✅ **Eventually consistent** - Data arrives when network recovers  
✅ **Idempotent** - Safe to retry infinitely  
✅ **Observable** - Queue files show what's pending  
✅ **Testable** - Can simulate failures with `.jsonl` files  
✅ **Simple** - No message brokers, no complex dependencies

## What This Architecture Costs You

⚠️ **Not real-time** - Delays possible if network is down  
⚠️ **Eventual consistency** - Server might lag behind local state  
⚠️ **Storage overhead** - Outbox queue uses disk space  
⚠️ **No delivery guarantees** - If you delete outbox, uploads lost

**Trade-off:** We chose developer experience over real-time consistency. For a development tool, this is the right trade-off.

## The Mental Model

Think of sync like email:

1. You write an email (agent writes artifacts)
2. Click "Send" (plugin queues upload)
3. Outbox sends it when it can (background retry loop)
4. You never wait to see if Gmail is up

Your email client doesn't crash if Gmail is down. Neither should Felix.

## What's Next?

Now you understand _why_ we built it this way. Next, let's dive into _how_ the outbox pattern actually works in practice.

[Continue to Chapter 2: The Outbox Pattern →](02-outbox-pattern.md)
