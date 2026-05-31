# Phase H — Concurrency & Worktrees (v2.6)

> **Status:** Planned
> **Version:** v2.6 (parallel with G)
> **Depends-On:** F
> **Unblocks:** —
> **Last-Touched:** 2026-05-29

Felix's `felix loop` is serial. Two loops on the same repo today fight over `requirements.json`, `state.json`, `runs/`, and the working tree. With cost guardrails (cross-cutting workstream) and per-path backpressure (F) in place, parallel work becomes both safe and economically sensible.

## Goals

1. Let multiple workers safely process different requirements in the same repo.
2. Use git worktrees so workers don't trample each other's working tree.
3. Make claim/release atomic with TTL leases so crashed workers don't deadlock.

## Deliverables

### H1 — Per-iteration git worktree (opt-in)

- Each iteration of `felix run`/`felix loop` **optionally** runs in its own worktree at `.felix/worktrees/<run-id>/`
- Created from current `HEAD`; deleted after merge (success) or after retention window (failure, for debug)
- Plugins and gates see the worktree path, not the main checkout
- Commit-on-complete merges back to the main branch (fast-forward or merge commit per config)
- **Opt-in via `felix loop --parallel N --worktrees`** or `concurrency.worktrees: true`. Many users running parallel workers will accept single-tree contention in exchange for not learning git-worktree semantics. Worktrees are the right answer for power users; not the right default.

### H2 — Atomic requirement claim

- `.felix/.locks/<requirement-id>.lock` (folder already exists; formalize content)
- Lease file content:
  ```json
  {
    "worker_id": "felix-w7@hostname",
    "run_id": "S-0042-...",
    "claimed_at": "2026-06-01T14:22:33Z",
    "lease_until": "2026-06-01T14:52:33Z",
    "pid": 12345
  }
  ```
- Claim is `O_CREAT|O_EXCL`-equivalent (atomic)
- Lease TTL default 30 min; refreshed by worker every 5 min
- Expired lease → reclaimable by any worker; expiry event on Event Bus

### H3 — `felix loop --parallel N`

- Spawns N worker processes; each runs the loop, claiming unblocked requirements
- Each worker picks based on:
  - `status: planned`
  - dependencies satisfied
  - not currently leased
  - priority order
- Workers tracked in `.felix/sessions.json` (already exists; extend schema)
- `felix procs` (already exists) shows them with per-worker status

### H4 — Conflict-aware backpressure

- After two parallel worktrees merge back, cross-cutting gates (`always_run` from F1) re-run on the merged state
- If post-merge gate fails: last-merged worker reopens the requirement as `status: blocked` with `block_reason: "merge-conflict"` metadata in `requirements.json`. **No new lifecycle state value.** `block_reason` is a free-form string so future failure modes don't keep adding enum entries.
- **Pre-merge fast-forward check / non-FF re-plan cut.** Block + `block_reason` is the path; a planning round-trip on contention is more complexity than it earns. Reopen if bench shows merge churn dominates wall-time.

### H5 — `felix run recover` (owner: H; promoted from cross-cutting)

- Single command to recover from worker crashes / interrupted iterations:
  - `felix run recover --run <run-id>` — inspect the last known state, offer to resume, abort, or mark blocked
  - `felix run recover --all` — enumerate all incomplete runs, prompt per-run
  - Alias: `felix recover` (back-compat)
- Operates on lease files (H2), worktrees (H1), and partial commits
- Surfaces a structured plan before mutating anything; `--yes` to apply non-interactively
- Sits in H because the only meaningful recovery scenarios involve worktree / lease state introduced here

## Non-goals

- Distributed workers across machines (cloud orchestration — separate concern, not in this repo)
- Lock-free coordination via DB (we're file-based; single-host)
- Auto-resolving merge conflicts (humans handle that)

## Phase Contracts frozen here

- Worktree lifecycle (creation, naming, deletion, retention) when opted in
- Lease file schema + TTL semantics
- `felix loop --parallel N [--worktrees]` CLI flag + behavior
- `.felix/sessions.json` extension (worker fields)
- `block_reason` metadata field on requirements (free-form string; first documented values: `merge-conflict`, `budget`)
- `felix recover` CLI surface

## Verification

- Two `felix loop --parallel 2` workers on the same repo claim different requirements (no double-claim)
- Kill a worker mid-iteration → lease expires → another worker reclaims; `felix recover --run <id>` cleans up the orphaned worktree
- Two parallel completions trigger post-merge cross-cutting gates exactly once
- Pre-existing serial `felix loop` (no `--parallel`) behaves identically to v1.x (compat); no worktrees created unless `--worktrees` passed
- Forced merge conflict between two parallel requirements → second-merged requirement marked `status: blocked, block_reason: "merge-conflict"` with actionable error

## Dogfood specs

- `specs/S-2H01-worktree-lifecycle.md`
- `specs/S-2H02-atomic-claim-lease.md`
- `specs/S-2H03-loop-parallel.md`
- `specs/S-2H04-post-merge-gates.md`
- `specs/S-2H05-recover.md`

## Anchor files

- [felix/felix-agent.ps1](../../felix/felix-agent.ps1), [felix/felix-loop.ps1](../../felix/felix-loop.ps1) — worker model, worktree creation
- [.felix/sessions.json](../../.felix/sessions.json) — worker fields
- [.felix/.locks/](../../.felix/.locks/) — lease files
- [src/Felix.Cli/Program.Commands.cs](../../src/Felix.Cli/Program.Commands.cs) — `loop --parallel [--worktrees]`, `procs` extensions, `recover`
- New: `.felix/worktrees/` (only when `--worktrees` opted in)
