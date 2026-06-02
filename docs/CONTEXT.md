# Context, Run History & Events

> **Quick links:** [Run Artifacts](#run-artifacts) · [Context Inspect](#felix-context-inspect) · [Run Replay](#felix-run-replay) · [Events System](#events-system) · [Event Types](#event-types-reference) · [Debugging with History](#debugging-with-run-history)

---

## Run Artifacts

Every requirement run writes a directory under `runs/`:

```
runs/
└── S-0001-20260601-143022-it1/
    ├── state.json            # Run outcome, iteration count, exit code
    ├── context-map.md        # Files the agent decided were relevant
    ├── plan-S-0001.md        # Agent's working plan for this requirement
    ├── diff.patch            # Git diff produced this iteration
    ├── report.md             # Human-readable run summary
    ├── agents-md-suggestions.md   # Learning proposals (Phase E)
    ├── search-cache.json     # Per-run search memoization cache (Phase D)
    ├── replay.json           # Snapshot manifest for replay (when present)
    └── iteration-1/
        ├── prompt.txt        # Exact prompt sent to the model
        ├── plan-*.md         # Plan artifact for this iteration
        └── output.log        # Raw model output
```

Run directories are named `<req-id>-<YYYYMMDD>-<HHMMSS>-it<N>`.

**Run retention** is controlled by `gc.retention_days` in `config.json` (default: 30 days). The most-recent successful run per requirement is always kept. Run `felix gc` to prune old runs.

---

## `felix context inspect`

Prints a token-budget breakdown showing how many tokens each context source consumes and which sources would be evicted if the budget were exceeded.

```powershell
felix context inspect
felix context inspect --requirement S-0001
```

Example output:

```
Context budget: 8,420 / 32,000 tokens

  Source           Tokens   Status
  ─────────────────────────────────
  layered_agents    1,240   ok
  repo_map            320   ok
  spec              2,100   ok
  plan              1,800   ok
  context_map         960   ok
  skills              880   ok
  memory              680   ok
  extras              440   ok

All sources fit within budget. Eviction order: extras → memory → context_map → ...
```

The token budget is configurable:

```json
"context": {
  "budget_tokens": 32000
}
```

A one-line summary (`tokens: N/M`) is printed at the start of every iteration in the agent log.

---

## `felix context build / show`

Build or display the project's context file.

```powershell
felix context build              # Analyze project and generate CONTEXT.md
felix context build --force      # Overwrite without confirmation
felix context show               # Print current CONTEXT.md to terminal
```

---

## `felix run replay`

Opens the prompt artifact for a previous run so you can inspect exactly what was sent to the model.

```powershell
felix run replay S-0001-20260601-143022-it1
felix run replay S-0001-20260601-143022-it1 --iteration 2
```

**What it does:**

- Locates `runs/<run-id>/iteration-<N>/prompt.txt`
- Opens the file in your `$EDITOR` (falls back to `notepad`)
- Does **not** re-execute the agent — it is a read-only inspection tool

**Why it's useful:** When an agent produces unexpected output, `replay` lets you read the exact context it received, making it straightforward to diagnose missing memory entries, wrong skill loading, or truncated specs.

When a full snapshot manifest (`runs/<run-id>/replay.json`) is present, it also shows the context hash, agent profile, and config snapshot used for that run.

---

## Events System

Felix emits structured events to `.felix/events.jsonl` throughout the agent lifecycle. Events are newline-delimited JSON (NDJSON), one event per line.

### `felix event tail`

Stream recent events from the log with optional filters.

```powershell
felix event tail                          # All events
felix event tail --kind agent.start       # Filter by event type
felix event tail --run-id S-0001-20260601 # Filter by run
felix event tail --since 30m              # Events from last 30 minutes
felix event tail --since 2h               # Events from last 2 hours
felix event tail --since 1d               # Events from last day
```

Output is raw NDJSON lines (one JSON object per line).

### `felix event query`

Filter events by a field=value expression.

```powershell
felix event query "type=log"
felix event query "run_id=S-0001-20260601-143022-it1"
```

---

## Event Types Reference

| Event type | Emitted when |
|---|---|
| `agent.start` | A new requirement run begins |
| `agent.complete` | A requirement run finishes (success or failure) |
| `iteration.start` | An iteration begins inside a run |
| `iteration.end` | An iteration completes |
| `iteration.error` | An uncaught error occurs during an iteration |
| `backpressure.start` | Backpressure gate evaluation begins |
| `backpressure.pass` | All gates passed |
| `backpressure.fail` | One or more gates failed |
| `validation.start` | `felix validate` begins evaluating a requirement |
| `validation.pass` | All acceptance criteria passed |
| `validation.fail` | One or more criteria failed |
| `requirement.complete` | A requirement transitions to `complete` status |
| `tool.call` | An agent tool was invoked (Phase F audit trail) |
| `lsp.fallback` | LSP was unavailable; fell back to text search (Phase D′) |
| `budget` | Context token summary emitted per iteration (Phase A5) |
| `search.cache_hit` | A search query was served from the per-run cache (Phase D3) |
| `lease.expired` | A worker lease TTL elapsed; requirement is now reclaimable (Phase H) |
| `worktree.created` | A git worktree was created for a run (Phase H) |
| `worktree.merged` | A worktree was merged back (result: ok / conflict / error) |

### Event schema

Each event line is a JSON object with at minimum:

```json
{
  "ts": "2026-06-01T14:30:22Z",
  "type": "agent.start",
  "run_id": "S-0001-20260601-143022-it1",
  "data": { ... }
}
```

The `tool.call` event has an extended payload:

```json
{
  "kind": "tool.call",
  "payload": {
    "tool": "navigate.references",
    "args": {},
    "allowed": true,
    "caller": "droid"
  }
}
```

---

## Debugging with Run History

### Find why a requirement failed

```powershell
# 1. Look at the last run for S-0003
Get-ChildItem runs -Filter "S-0003-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

# 2. Read the summary
Get-Content runs\S-0003-20260601-143022-it1\report.md

# 3. See what prompt was sent on iteration 2
felix run replay S-0003-20260601-143022-it1 --iteration 2

# 4. Check backpressure failures
felix event tail --kind backpressure.fail --run-id S-0003-20260601-143022-it1

# 5. See full context breakdown
felix context inspect --requirement S-0003
```

### Search across all past runs

```powershell
# Find all runs that mention a specific error
felix search "NullReferenceException" --in runs

# Find files that were touched in S-0001 runs
felix search --related-to S-0001
```

### Check memory proposals after a run

After each run completes, the `learning-capture` plugin writes proposals to `runs/<run-id>/agents-md-suggestions.md`. Review them with:

```powershell
felix review --learnings
```

---

*See also: [SEARCH.md](SEARCH.md) for search and query commands · [MEMORY.md](MEMORY.md) for the memory system · [CLI.md](CLI.md) for the full `felix context` and `felix event` reference*
