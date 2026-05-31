# Phase D — Search (v2.3)

> **Status:** Planned
> **Version:** v2.3
> **Depends-On:** C
> **Unblocks:** D′
> **Last-Touched:** 2026-05-29

Search quality is currently a property of whichever CLI agent is configured. Different agents give different results, none of them know about Felix artifacts (`specs/`, `runs/`), and none of them honor a shared ignore policy. Felix should own the search surface.

## Goals

1. Give every agent the same, Felix-aware search tool.
2. Surface Felix-only knowledge (prior runs, related specs) that no upstream agent can provide.
3. Stop agents from burning context on raw grep results with no scoping.

## Deliverables

### D1 — `felix search`

- Ripgrep-backed (or equivalent .NET impl); `.felixignore`-aware (A3); layered-AGENTS.md-aware (A1) so it auto-scopes to the nearest subdirectory by default
- `felix search "<pattern>" [--scope file|symbol] [--in code|specs|runs|all] [--max N] [--json]`
- JSON output is the frozen contract:
  ```json
  {
    "matches": [
      {
        "path": "src/Felix.Cli/Program.cs",
        "line": 42,
        "col": 18,
        "text": "…",
        "symbol": "Main",
        "rank": 0.74,
        "context": ["…", "…"]
      }
    ],
    "truncated": false,
    "total": 12,
    "ignored_globs": [".felixignore", "layered:src/AGENTS.md"]
  }
  ```

### D2 — Spec/Run-aware search

- `--in=specs` greps `specs/`
- `--in=runs` greps `runs/` (last N runs by default)
- `--related-to S-NNNN` — assembles files referenced in that requirement's plans, diffs, validation reports, prior context-maps; returns ranked file list
- This is the killer query — no upstream agent can do it

### D3 — Per-run search memoization

- Cache file: `runs/<run-id>/search-cache.json`
- Keyed by query + flags hash; entries TTL'd to the iteration
- Avoids paying twice for the same grep within a single iteration
- Deleted with the run (no cross-iteration staleness)
- This is the one real cache in v2 (per [V2_MIGRATION.md](../V2_MIGRATION.md) decisions)

### D6 — Raw-grep guard rail _(cut)_

**Cut.** Once `felix search` is registered as a tool via D5/MCP, agents use it natively. A `pre-bash` interceptor that rewrites `grep`/`rg`/`Select-String` is belt-on-suspenders complexity that complicates the hook surface. Reopen if bench shows agents continue to raw-grep at scale after MCP exposure.

> **D7 (prompt-augmentation fallback) cut.** For adapters without tool calling, Phase C's `context-map.md` (produced eagerly every iteration) already gives the building prompt a curated file list. A second eager search would duplicate that work and double the token cost. Universal coverage = the context map.

## Non-goals

- LSP/symbol resolution (D′)
- Tool-call shim for full bidirectional tool use (D′ D5)
- Cross-repo / workspace search (deferred to v3)

## Phase Contracts frozen here

- `felix search` CLI flags + `--json` output schema
- `runs/<run-id>/search-cache.json` schema (consumers can read; format owned by Felix)

## Verification

- `felix search --related-to S-0001 --json` returns files referenced in S-0001's plans/diffs
- Wide grep for "Program" excludes `publish-out/` due to `.felixignore`
- Same query within one iteration hits the memoization cache (logged on Event Bus)

## Dogfood specs

- `specs/S-2D01-felix-search.md`
- `specs/S-2D02-spec-run-aware-search.md`
- `specs/S-2D03-search-memoization.md`

## Anchor files

- [src/Felix.Cli/Program.Commands.cs](../../src/Felix.Cli/Program.Commands.cs) — `search` command
- [.felix/config.json](../../.felix/config.json) — `search` block (`default_in`)
- New: `runs/<run-id>/search-cache.json`
