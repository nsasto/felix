# Phase C — Exploration Subagent (v2.2)

> **Status:** Planned
> **Version:** v2.2
> **Depends-On:** B
> **Unblocks:** D, D′
> **Last-Touched:** 2026-05-29

Today the loop has two phases (`plan`, `build`) and one agent does both. The agent re-discovers structure every iteration from scratch. The article's recommended pattern: split **exploration** (read-only, write findings to disk) from **editing** (consumes findings).

## Goals

1. Add an `explore` loop phase that runs a read-only subagent before plan/build.
2. Produce a structured `context-map.md` per iteration that downstream phases consume.
3. Reduce token usage on editing-phase iterations by avoiding rediscovery.

## Deliverables

### C1 — `explore` loop phase

- New first phase in the iteration: `explore → plan → build → validate`
- Configurable in `.felix/config.json`:
  ```json
  "explore": {
    "enabled": false,
    "auto_enable_when": { "min_tracked_files": 500 },
    "skip_on_iteration_gt": 1,
    "agent_override": null,
    "max_tokens": 8000
  }
  ```
- **Default OFF.** `felix setup` and `felix migrate` flip `enabled: true` only when the repo signal in `auto_enable_when` is met (default: ≥500 tracked files post-`.felixignore`). Rationale: bench fixture `py-flask` is small and exploration is net-negative there; `legacy-mono` is large and net-positive. A global default doesn't fit either; a signal does.
- `felix run --explore` / `--no-explore` overrides per-invocation

### C2 — Read-only subagent

- Spawns the configured CLI agent with a `--read-only` flag (or wrapper that refuses writes)
- Loaded context: layered AGENTS.md (A1) + repo map (A2) + spec + relevant skills (B) — **no** plan, **no** prior diffs
- Output contract: writes `runs/<run-id>/context-map.md`:

  ```markdown
  # Context Map — S-0042 it3

  ## Files likely to change

  - src/Felix.Cli/Program.Commands.cs (cmd registration)
  - src/Felix.Cli/SpecCommands.cs (spec subcommand)

  ## Files to read for context

  - .felix/config.json
  - docs/CLI.md

  ## Symbols of interest

  - `RegisterCommands` (Program.Commands.cs:42)
  - `SpecLint` (SpecCommands.cs:118)

  ## Related tests

  - tests/Felix.Cli.Tests/SpecCommandsTests.cs

  ## Prior runs

  - runs/S-0042-...-it2 (failed: backpressure on pwsh.lint)
  ```

- Natural ordering within each section is the ranking signal; subagent emits most-relevant first
- Strictly markdown; schema enforced by post-LLM hook

### C3 — Building prompt consumes context-map

- `{{CONTEXT_MAP}}` placeholder in `[.felix/prompts/building.md](../../.felix/prompts/building.md)` filled by C
- Building prompt instructs: "Use the Context Map as your starting point. Do not re-discover what's listed there."
- Planning prompt also consumes (cheaper plans)

### C4 — New hooks

- `OnPreExplore(run_id, requirement)` — plugins can pre-warm
- `OnPostExplore(run_id, context_map_path)` — plugins can amend (e.g., E's learning-capture appends prior-failure notes)

### C5 — Ranking _(cut)_

**Cut.** Natural ordering within each `context-map.md` section is the ranking signal in v2.2. Numeric rank suffixes deferred until a bench fixture demonstrates rank-driven eviction is net-positive over presentation order.

## Non-goals

- Parallel exploration of multiple requirements (H)
- LSP-aware exploration (D′ enhances symbol-of-interest accuracy once available)
- Cross-iteration context-map caching (intentional: fresh map per iteration mirrors live state)

## Phase Contracts frozen here

- `context-map.md` markdown schema (section headers, natural ordering = rank)
- `explore` config block schema
- `OnPreExplore` / `OnPostExplore` hook signatures
- Phase ordering: `explore → plan → build → validate`

## Verification

- `context-map.md` produced before plan/build in every iteration; missing/malformed map fails the iteration cleanly with actionable error
- Building prompt token count reduced ≥ 15% vs v1 on bench harness Python-flask fixture
- `felix run --no-explore` skips phase, falls back to v1.x behavior (escape hatch)
- A plugin registered for `OnPostExplore` can append a section; section appears in editing-phase prompt

## Dogfood specs

- `specs/S-2C01-explore-phase.md`
- `specs/S-2C02-read-only-subagent.md`
- `specs/S-2C03-context-map-schema.md`
- `specs/S-2C04-explore-hooks.md`

## Anchor files

- [felix/felix-agent.ps1](../../felix/felix-agent.ps1) — phase orchestration
- [felix/felix-loop.ps1](../../felix/felix-loop.ps1) — wire explore between selection and plan
- [.felix/prompts/building.md](../../.felix/prompts/building.md), [.felix/prompts/planning.md](../../.felix/prompts/planning.md) — `{{CONTEXT_MAP}}` placeholder
- [.felix/config.json](../../.felix/config.json) — `explore` block
- New: `runs/<run-id>/context-map.md` per iteration
