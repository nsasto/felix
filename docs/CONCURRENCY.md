# Parallel Execution & Concurrency

> **Quick links:** [Overview](#overview) · [felix loop --parallel](#felix-loop---parallel-n---worktrees) · [Lease Protocol](#lease-protocol) · [Git Worktrees](#git-worktrees) · [felix recover](#felix-recover) · [Configuration](#configuration) · [Operational Tips](#operational-tips)

---

## Overview

By default `felix loop` runs serially — one requirement at a time, in the main working tree. Phase H adds **parallel workers** so multiple requirements can be processed simultaneously, and **git worktrees** so those workers each have an isolated working directory.

**When to use parallel execution:**

- Large backlogs with many independent requirements
- Long-running requirements where idle I/O time can be overlapped
- Multi-core machines where you want to saturate CPU/API concurrency

**Prerequisites:** Per-path backpressure (Phase F) should be configured so that workers only run the gates that apply to their changes, avoiding redundant test suite runs.

---

## `felix loop --parallel N [--worktrees]`

```powershell
felix loop --parallel 4              # 4 parallel workers, shared working tree
felix loop --parallel 4 --worktrees  # 4 parallel workers, each in its own worktree
```

**How it works:**

1. Felix spawns N worker processes. Each runs the same loop logic.
2. Each worker scans `.felix/requirements.json` for `status: planned` requirements with satisfied dependencies that are not currently leased.
3. The worker atomically claims the requirement via a lease file (see [Lease Protocol](#lease-protocol)).
4. Processing proceeds normally: plan → build → backpressure → commit.
5. After completing, the worker releases the lease and picks the next available requirement.

Workers are tracked in `.felix/sessions.json`. View them with:

```powershell
felix procs
```

---

## Lease Protocol

Each worker claims a requirement by creating a lock file:

```
.felix/.locks/<requirement-id>.lock
```

### Lease file schema

```json
{
  "worker_id":    "felix-w1@hostname",
  "run_id":       "S-0042-20260601-143022-it1",
  "claimed_at":   "2026-06-01T14:22:33Z",
  "lease_until":  "2026-06-01T14:52:33Z",
  "pid":          12345
}
```

| Field | Description |
|---|---|
| `worker_id` | Unique identifier for the worker process. |
| `run_id` | Run directory name for the current iteration. |
| `claimed_at` | ISO 8601 timestamp when the claim was made. |
| `lease_until` | Claim is valid until this time. Default TTL: **30 minutes**. |
| `pid` | OS process ID of the worker (used for orphan detection). |

### Atomicity

The lock file is created with `O_CREAT|O_EXCL`-equivalent semantics (PowerShell: `FileMode.CreateNew`). Only one worker can successfully create the file; all others receive an error and skip to the next available requirement. There is no retry loop — if a claim fails, the worker immediately tries the next requirement.

### TTL and refresh

- Workers refresh the lease file every **5 minutes** by updating `lease_until` to `now + 30 min`.
- A lease is considered **expired** when `lease_until < utcNow`.
- Expired leases are reclaimable by any other worker.
- An expiry event is emitted on the event bus: `lease.expired`.

### Detecting stale leases

```powershell
felix doctor                    # Reports stale-leases check
felix recover --all --dry-run   # Shows all orphaned runs including expired leases
```

---

## Git Worktrees

When `--worktrees` is passed (or `concurrency.worktrees: true` in config), each worker creates a dedicated git worktree:

```
.felix/worktrees/<run-id>/
```

### Worktree lifecycle

1. **Created** from the current `HEAD` at the start of the run: `git worktree add .felix/worktrees/<run-id>`.
2. **Isolated execution**: the worker performs all file changes and backpressure gates within the worktree path.
3. **Merge-back** on completion:
   - `ok` — changes merged back to the main branch (fast-forward or merge commit per `concurrency.merge_strategy`).
   - `conflict` — merge conflict detected; requirement is marked `blocked` with `block_reason: "merge-conflict"`. A human resolves the conflict, then changes the status back to `planned`.
   - `error` — unexpected failure during merge; requirement marked `blocked`.
4. **Cleanup**: on success the worktree is removed. On failure it is retained for inspection until `concurrency.retention_days` expires.

### Worktree metadata

Each worktree contains a `.felix-worktree.json` file:

```json
{
  "run_id":        "S-0042-20260601-143022-it1",
  "requirement_id": "S-0042",
  "worker_id":     "felix-w2@hostname",
  "created_at":    "2026-06-01T14:22:33Z",
  "worktree":      ".felix/worktrees/S-0042-20260601-143022-it1"
}
```

### Post-merge cross-cutting gates

After two parallel worktrees merge back, the gates listed in `backpressure.always_run` re-run on the merged state. If a post-merge gate fails, the last-merged requirement is marked `blocked` with `block_reason: "merge-conflict"`.

---

## `felix recover`

Recover from crashed or interrupted worker runs.

```powershell
felix recover                          # Show usage
felix recover --all                    # Enumerate all orphaned runs, prompt per-run
felix recover --run S-0042-20260601    # Inspect and recover a specific run
felix recover --all --yes              # Apply recovery actions non-interactively
felix recover --all --dry-run          # Show what would happen; make no changes
```

Alias: `felix run recover [flags]`

### What counts as an orphaned run

A run is orphaned when:

- Its lease file exists but `lease_until` has passed (the worker crashed or was killed).
- Its worktree directory exists in `.felix/worktrees/` but there is no active session tracking it.

### Recovery actions (per orphaned run)

When prompted (interactive mode):

| Action | Key | Effect |
|---|---|---|
| **resume** | `r` | Releases the stale lease so the requirement can be claimed again. Does not automatically re-run. |
| **block** | `a` | Releases the lease, marks the requirement `status: blocked` with `block_reason: "recovered-from-crash"`, removes the orphaned worktree. |
| **skip** | `s` | Takes no action for this run; leaves it for manual handling. |

With `--yes`, `block` is applied to all orphaned runs without prompting.

---

## Configuration

The `concurrency` block in `.felix/config.json` controls all parallel execution settings:

```json
"concurrency": {
  "worktrees":      false,
  "parallel":       1,
  "merge_strategy": "merge",
  "retention_days": 3
}
```

| Key | Type | Default | Description |
|---|---|---|---|
| `worktrees` | `boolean` | `false` | Enable per-run worktrees. Overridden by `--worktrees` flag. |
| `parallel` | `integer` | `1` | Default number of workers. Overridden by `--parallel N`. |
| `merge_strategy` | `string` | `"merge"` | `"merge"` creates a merge commit; `"ff"` requires a fast-forward. |
| `retention_days` | `integer` | `3` | Days to keep abandoned/failed worktrees before `felix gc` removes them. |

---

## Operational Tips

### Recommended parallel count

Start with `--parallel 2` and validate that requirements do not conflict before increasing. The right number depends on:

- API rate limits of your LLM provider
- Whether requirements touch overlapping files (worktrees help but do not eliminate conflicts)
- Available disk space for worktrees

### Dealing with conflicts

A merge conflict leaves the requirement `blocked` with `block_reason: "merge-conflict"`. To unblock:

1. Inspect the worktree at `.felix/worktrees/<run-id>/` and resolve conflicts manually.
2. Or discard the worktree changes and re-plan from scratch.
3. Edit `.felix/requirements.json`: change `status` from `"blocked"` to `"planned"` and clear `block_reason`.
4. Re-run: `felix run S-NNNN`.

### Cleaning up orphaned worktrees

```powershell
felix gc --dry-run    # See orphaned worktrees
felix gc --yes        # Remove them
```

### Monitoring workers

```powershell
felix procs           # List active worker sessions
felix event tail --kind lease.expired   # Watch for lease expiry events
```

---

*See also: [CONFIGURATION.md](CONFIGURATION.md) for the `concurrency` config block · [CLI.md](CLI.md) for the full `felix loop` and `felix recover` reference · [CONTEXT.md](CONTEXT.md) for the event bus*
