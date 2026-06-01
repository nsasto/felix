# Phase F — Targeted Execution + Security (v2.5)

> **Status:** Planned
> **Version:** v2.5 (parallel with B–E)
> **Depends-On:** A
> **Unblocks:** H
> **Last-Touched:** 2026-05-29

Today's backpressure runs every command on every iteration. Editing a single C# file triggers the Python + npm test suites — wastes context, time, and money. Today's agent has unrestricted shell access — fine for solo dev, dangerous as the tool surface grows.

## Goals

1. Run only the gates that matter for the changes made.
2. Expose Felix state to agents via a stable JSON contract (not raw schema reads).
3. Define what the agent is allowed to call, audit what it does call.

## Deliverables

### F1 — Per-path backpressure

- `.felix/config.json`:
  ```json
  "backpressure": {
    "enabled": true,
    "commands": [
      {
        "name": "dotnet.test",
        "cmd": "dotnet test tests/Felix.Cli.Tests",
        "appliesTo": ["src/Felix.Cli/**", "tests/Felix.Cli.Tests/**"]
      },
      {
        "name": "pwsh.unit",
        "cmd": "pwsh -File ./run-test-spec.ps1",
        "appliesTo": ["felix/**", "scripts/**", ".felix/plugins/**/*.ps1"]
      },
      {
        "name": "py.test",
        "cmd": "py -3 -m pytest",
        "appliesTo": ["scripts/**/*.py"]
      }
    ],
    "max_retries": 3,
    "always_run": ["pwsh.lint"]
  }
  ```
- Iteration's `diff.patch` matched against `appliesTo` globs; only matched commands run
- `always_run` for cross-cutting gates (lint, doc-up-to-date)
- Backwards compat: missing `appliesTo` = run always (v1 behavior)

### F2 — Validation honors path-scoped criteria

- `felix validate <req-id>` filters validation criteria the same way
- Spec frontmatter `gates` (B5) names the relevant entries

### F3 — Structured-state tool

- `felix query <kind> [filters...] [--json]` returns stable, versioned JSON
- **Kinds limited to `requirements | runs | state`.** Other resources (`events`, `plugins`, `skills`, `memory`) already have first-class verbs (`felix event query`, `felix plugin list`, `felix skill list`, `felix memory view`) — duplicating them under `query` adds API surface without adding capability.
- Examples:
  ```
  felix query requirements --status planned --json
  felix query runs --since 24h --requirement S-0042
  felix query state --json
  ```
- Schema versioned (`"_v": 1`); breaking changes require major bump
- Decouples agent from raw `requirements.json` / `state.json` layout

### F4 — Exposed via tool surface (D5)

- `felix query` registered as an agent tool through Felix's MCP server (primary) and per-adapter fallback shim — the unified tool exposure introduced in D5
- Allowlist (F5) gates which `kind` an agent may query

### F5 — Agent tool allowlist

- `.felix/config.json`:
  ```json
  "tools": {
    "allow": ["search.*", "navigate.references", "navigate.definition", "query.requirements", "query.runs"],
    "deny": [],
    "default": "allow"
  }
  ```
- **Default-allow on v1→v2 upgrade.** `felix migrate` seeds `tools.allow` with the current agent's de-facto tool set so existing users aren't broken on first run. New repos created by `felix setup` also start `default: "allow"` with an audit-only log of every tool call.
- `felix tool harden` is the one-time opt-in that flips `default` to `"deny"`, prints the inferred allowlist from recent audit logs, and asks for confirmation. Power users / regulated repos opt in; everyone else gets the safe default and the audit trail. (Alias `felix tools harden` retained for one minor.)
- Glob matching on tool names
- D5 (MCP/shim) enforces at call time; denial returns structured error to agent

### F6 — Per-tool audit

- Every tool invocation emits Event Bus entry `kind=tool.call`:
  ```json
  {"kind":"tool.call","payload":{"tool":"navigate.references","args":{...},"allowed":true,"caller":"droid"}}
  ```
- Denials also audited (`allowed: false`)
- `felix event tail --kind tool.call` shows the live tool stream
- Doubles as input to `felix tool harden` for inferring the allowlist

> **F7 (`felix exec` sandbox) cut.** The original motivation — protect against destructive shellouts — is already covered by the agent tool allowlist (F5) + the audit trail (F6). Write-protection for paths like `.git/` is a single hook-layer deny-list, not a new CLI verb with timeout/network/cwd flags. If a future threat model demands capability-based sandboxing, revisit in v3.

### F8 — `felix gc` (owner: F; promoted from cross-cutting)

- Disk pressure cleanup; safe-by-default with explicit prompts for surprising deletes
- Prunes `runs/` older than `gc.retention_days` (default 30) while keeping the last-success run per requirement
- Prunes `.felix/events-*.jsonl` rotations beyond `events.retention_days`
- Prunes orphaned `.felix/worktrees/<run-id>/` (those without an active session in `.felix/sessions.json`)
- `--dry-run` and `--yes` flags; destructive paths gated by interactive confirmation otherwise

## Non-goals

- Multi-user/role permissions (single-user model through v2)
- Network-aware backpressure (HTTP/gRPC types — deferred)
- Capability-based security (the allowlist is name-based, not capability-based)

## Phase Contracts frozen here

- `backpressure.commands[].appliesTo` glob semantics
- `felix query` CLI + per-kind `--json` schema with `_v` field (kinds: `requirements | runs | state`)
- `tools` config block schema (default-allow on upgrade; `felix tool harden` for opt-in deny)
- `kind=tool.call` event payload schema
- `felix gc` CLI surface

## Verification

- Edit only `src/Felix.Cli/Program.cs` → only `dotnet.test` + `always_run` gates execute; `py.test` skipped (logged)
- `felix query requirements --status planned --json` schema matches contract; `_v` present
- `felix query` with kind `events` returns an actionable error pointing at `felix event query`
- v1→v2 migrated repo runs with `tools.default = "allow"`; no tool calls broken; audit log populated
- `felix tool harden` proposes an allowlist from recent audit; user confirms; subsequent unknown tool is denied with structured error
- Backwards compat: a v1 config with no `appliesTo` runs all commands as before
- `felix gc --dry-run` reports what would be pruned without modifying disk

## Dogfood specs

- `specs/S-2F01-per-path-backpressure.md`
- `specs/S-2F02-validate-path-scoped.md`
- `specs/S-2F03-query-tool.md`
- `specs/S-2F04-query-tool-exposure.md`
- `specs/S-2F05-tool-allowlist.md`
- `specs/S-2F06-tool-audit.md`
- `specs/S-2F08-gc.md`

## Anchor files

- [felix/felix-agent.ps1](../../felix/felix-agent.ps1), [felix/felix-loop.ps1](../../felix/felix-loop.ps1) — backpressure dispatcher
- [src/Felix.Cli/Program.Commands.cs](../../src/Felix.Cli/Program.Commands.cs) — `query`, `tool harden`, `gc`, `validate`
- [.felix/config.json](../../.felix/config.json) — `tools`, `backpressure.commands[].appliesTo`, `gc.retention_days`
- [scripts/validate-requirement.py](../../scripts/validate-requirement.py), [scripts/validate-requirement.ps1](../../scripts/validate-requirement.ps1) — path-scoped filtering
