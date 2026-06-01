# Phase A.5 — Distribution Substrate (v2.0.x)

> **Status:** Planned
> **Version:** v2.0.x (ships with A)
> **Depends-On:** A
> **Unblocks:** B, C, D, D′, E, F, H, G
> **Last-Touched:** 2026-05-29

Foundational. Every later phase distributes its reference plugin through A.5, emits to the Event Bus from A.5, and freezes its contracts in the registry A.5 hosts. Without A.5, those phases each grow their own ad-hoc install/observability story and Phase G inherits a moving target.

## Goals

1. Make installing a plugin from a path / URL / git repo a first-class CLI operation with signature verification.
2. Give Felix a single append-only event stream that every component (loop, hooks, plugins, CLI) writes to.
3. Codify the per-phase interface contracts so v2.7 isn't a renegotiation of v2.0.

## Deliverables

### AS1 — `felix plugin install`

- `felix plugin install <name|path|url|git>` — supports:
  - `./local/path` (filesystem copy)
  - `https://...zip` (download + verify checksum)
  - `git+https://...` (clone + checkout tag/commit)
  - `<name>` resolves later via G's marketplace (NotFound until G ships)
- Verifies against `.felix/plugins/manifest-hashes.json` (already exists in repo — formalize the schema)
- `felix plugin list|remove|info <id>`
- Plugins land in `.felix/plugins/<id>/`; tests run via `felix plugin test` (G workstream)
- Conservative defaults: prompt user on first untrusted source; configurable allowlist of source hosts

### AS2 — Event Bus (gating)

- Append-only JSONL at `.felix/events.jsonl`
- Schema (frozen contract):
  ```json
  {"ts":"2026-06-01T14:22:33.123Z","run_id":"S-0042-...","phase":"build","kind":"backpressure.fail","payload":{...},"plugin":"sync-http"}
  ```
- Rotation: 5 MB → `.felix/events-YYYYMMDDTHHMMSS.jsonl`; total retention `events.retention_days` (default 30)
- Emitted from: loop phase transitions, every plugin hook entry/exit, every CLI command with `--audit`, backpressure pass/fail, budget warn/halt
- Consumers: E (learning-capture reads from bus, not log scraping), F (tool audit), Bench (results)
- CLI: `felix event tail [--kind ...] [--run-id ...] [--since 1h]`, `felix event query <jq-like>` (alias `events` retained one minor)

### AS3 — Phase Contracts registry

- Lives at `[v2/CONTRACTS.md](CONTRACTS.md)` — markdown table per phase listing frozen file layouts, JSON schemas, hook signatures, CLI flags
- **A.5 ships the document only.** `felix contracts check` enforcement is deferred until the first phase actually breaks a contract; until then CONTRACTS.md is reviewer-enforced (PR checklist). Avoids paying for a gate that has no consumer.
- **A.5's frozen schemas are candidate v1**: B/C/D/E may amend additively (new optional fields, new event kinds, new hook params) through v2.3 without `BREAKING:`. Real consumers don't exist yet; pretending the contract is final encourages a misclassified breaking change later.
- Adding to a contract: free
- Changing/removing from a contract (post-v2.3): requires explicit `BREAKING:` annotation + bumped major (i.e., v3)

### AS4 — `felix doctor` (owner: A.5; promoted from cross-cutting)

- Single diagnostic command surfacing the most common operational failures and absorbing checks other phases would otherwise own as separate verbs:
  - Stale lease files (`.felix/.locks/*.lock` past `lease_until`) — see H2
  - Orphaned worktrees (`.felix/worktrees/*` not in any active session) — see H1
  - Corrupt event log (truncated last line, bad JSON)
  - Plugin manifest hash mismatches
  - Memory entries failing heuristic checks (length, no frontmatter)
  - **Repo-map staleness** — new top-level folder without entry in `AGENTS.md ## Map` (absorbs A2's `repo-map check` verb; `--fix` regenerates the block)
  - **Spec frontmatter** — required fields, gate name resolution, skill name resolution, `applyTo` not empty on non-trivial specs (absorbs B7's `spec lint` verb)
  - **Stale prompt-review** — `.felix/state.json#last_review` > 90 days (absorbs E3's reminder hook)
  - **`.felixignore` debug** — `felix doctor --explain <path>` reports which pattern in which layer matched
- `--fix` flag attempts non-destructive repairs (delete stale leases/worktrees, regenerate `## Map` block); destructive repairs prompt
- Phase-specific checks register into `doctor` here; later phases extend without owning the verb

## Non-goals

- Marketplace / curated remote index (deferred to G)
- Remote plugin updates (`felix plugin update --remote` is G)
- Per-language plugin runtimes (out of scope; PowerShell only)

## Phase Contracts frozen here

- `.felix/events.jsonl` line schema (immutable required fields; `payload` is open)
- `manifest-hashes.json` schema
- `plugin.json` v1 manifest (already in use — formalize and pin)
- Hook contract signatures (extension of existing `hook-contracts.ps1`)
- `felix plugin install|list|remove|info` CLI surface (flags + JSON output)
- `felix event tail|query` CLI surface (singular noun; `events` alias kept for back-compat)
- `felix doctor` extension-point: phase-specific checks register into a single doctor command

## Verification

- Install a local plugin: `felix plugin install ./samples/hello-plugin` → present in `plugin list`
- Corrupted manifest hash → install rejected with actionable error
- Reference plugin emits `kind=hello` on `OnPreIteration`; `felix event tail --kind hello` shows it
- Rotation triggers at 5 MB; old files prune past 30 days
- `felix doctor` detects an injected stale lease and reports it; `--fix` removes it
- CONTRACTS.md changes flagged by reviewer checklist when a phase silently widens a contract

## Dogfood specs

- `specs/S-2AS1-plugin-install.md`
- `specs/S-2AS2-event-bus.md`
- `specs/S-2AS3-contracts-registry.md`
- `specs/S-2AS4-doctor.md`

## Anchor files

- [src/Felix.Cli/Program.Commands.cs](../../src/Felix.Cli/Program.Commands.cs) — add `plugin install/list/remove/info`, `event tail/query`, `doctor`
- [.felix/plugins/manifest-hashes.json](../../.felix/plugins/manifest-hashes.json) — formalize schema
- [.felix/plugins/hook-contracts.ps1](../../.felix/plugins/hook-contracts.ps1) — extend with event emission helpers
- [docs/PLUGINS.md](../../docs/PLUGINS.md) — install/event docs
- New: `.felix/events.jsonl`, `[v2/CONTRACTS.md](CONTRACTS.md)`
