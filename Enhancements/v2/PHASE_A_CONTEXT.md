# Phase A — Context Foundation (v2.0)

> **Status:** Planned
> **Version:** v2.0
> **Depends-On:** —
> **Unblocks:** A.5, B, C, D, E, F, H, G
> **Last-Touched:** 2026-05-29

The substrate for every later phase. Until A lands, the layered context, ignore policy, and budget accounting required by B–G don't exist.

## Goals

1. Replace single-root `AGENTS.md` + `CONTEXT.md` with a hierarchical, walk-up loader.
2. Give Felix an authoritative ignore policy (`.felixignore`) that survives across agents, with per-user override.
3. Establish per-source token budgeting so subsequent phases don't blow the context window.
4. Own the v1→v2 migration substrate so every later phase plugs its transforms into one tool.

## Deliverables

### A1 — Hierarchical AGENTS.md loader

- Walk from `cwd` (or requirement-implied path) up to repo root
- Concatenate every `AGENTS.md` found, **deepest first** (most local wins) with section headers
- Per-level budget (default 4 KB); overflow logs warning + truncates with marker
- Output a deterministic "layered context blob" with a hash for snapshot/replay

### A2 — Repo Map convention

- Root `AGENTS.md` gains a `## Map` section (one line per top-level folder, plain text)
- `felix repo-map build` scans top-level + key second-level dirs, infers descriptions from existing READMEs / first heading of `AGENTS.md`, writes/refreshes the `## Map` block (idempotent, marker-delimited)
- Staleness detection (new top-level folder without map entry) is **folded into the cross-cutting `docs-up-to-date` backpressure gate** — no separate `felix repo-map check` verb

### A3 — `.felixignore` (layered)

- Default file shipped by `felix setup`:
  ```
  runs/
  publish-out/
  obj/
  bin/
  .locks/
  node_modules/
  __pycache__/
  *.min.js
  *.map
  ```
- Per-language addendum chosen from project signals (`.csproj` → `bin/`, `obj/`; `package.json` → `dist/`, `coverage/`)
- **Lookup order (deepest-pattern-wins within each layer, layers merged):**
  1. Per-directory `.felixignore` walked up to repo root
  2. Repo-root `.felixignore` (committed)
  3. `.felixignore.local` (gitignored; per-developer override of project-level exclusions)
  4. `%USERPROFILE%/.felix/ignore` (user scope, cross-repo)
- All Felix-owned search/read helpers honor it; raw-grep guard (D6) enforces later

### A4 — Prompt injection refactor

- `[.felix/prompts/planning.md](../../.felix/prompts/planning.md)` and `[.felix/prompts/building.md](../../.felix/prompts/building.md)` consume the layered context blob, not a single `CONTEXT.md`
- Prompt templates gain explicit placeholders: `{{LAYERED_AGENTS}}`, `{{REPO_MAP}}`, `{{SPEC}}`, `{{PLAN}}`, `{{CONTEXT_MAP}}` (filled by C), `{{SKILLS}}` (filled by B), `{{MEMORY}}` (filled by E)
- Placeholders not yet wired return empty strings so v2.0 ships standalone

### A5 — Context Budgeter (gating)

- Token estimate per source (cheap tiktoken-ish heuristic; per-agent override)
- Config in `.felix/config.json`:
  ```json
  "context": {
    "budget_tokens": 32000,
    "weights": {
      "layered_agents": 0.15,
      "repo_map": 0.05,
      "spec": 0.20,
      "plan": 0.15,
      "context_map": 0.20,
      "skills": 0.10,
      "memory": 0.10,
      "extras": 0.05
    },
    "eviction_order": ["extras", "memory", "context_map", "skills", "layered_agents", "repo_map", "plan", "spec"]
  }
  ```
- `felix context inspect [--requirement S-NNNN]` prints token table + what would be evicted
- Loop emits a `budget` event on the Event Bus (AS2) per iteration

### A6 — `felix migrate` registry (formerly: run-ID format change)

- Run-ID format change **cut** — current `S-NNNN-YYYYMMDD-HHMMSS-itK` is unique enough; H disambiguates via `worker_id`. If parallel uniqueness later becomes a problem, append `-<ulid8>` then (backwards-compatibly).
- `felix migrate` is the permanent v1→v2 transform tool. A owns the **registry**; later phases register their transforms here:
  - A: `.felixignore` seed, AGENTS.md `## Map` block initialization
  - B: `spec fix --apply` (frontmatter), prompts→skills move
  - F: `tools.allow` seed from current agent's de-facto tool set
- Flags: `--dry-run`, `--only <transform-id>`, `--revert`
- Migration is idempotent; re-running on a v2 repo is a no-op
- Recognition of v1 layouts is permanent — `felix migrate` never sunset

### A7 — `felix replay` (owner: A; promoted from cross-cutting)

- Per-run snapshot manifest written under `runs/<run-id>/replay.json` capturing: layered context blob hash, prompt template hashes, agent profile, config snapshot
- `felix replay <run-id>` re-injects the exact context for debugging; does not re-execute the agent
- Lives in A because the snapshot fields are A's contracts (layered context blob + config block)

### A8 — `felix config explain <path>`

- New config blocks land in A and grow through F. Without provenance, deeply-nested values become opaque.
- `felix config explain context.budget_tokens` prints: current value, source (default | `.felix/config.json` line N | env `FELIX_*` | CLI flag), and the inheritance chain
- Small surface, large usability payoff; gates every later phase that adds a config block

## Non-goals

- Tool-call shim for agents (D′)
- Per-path backpressure (F)
- Subagent split (C)
- Skill on-demand loading (B)

## Phase Contracts frozen here

See [CONTRACTS.md](CONTRACTS.md) for the registry. A freezes:

- Layered context blob format (header structure, hash field, level markers)
- `.felixignore` syntax (gitignore-compatible subset) + layered lookup order
- `context` config block schema
- `context inspect --json` output schema
- `felix migrate` transform-registry interface (other phases register transforms via it)
- `runs/<run-id>/replay.json` snapshot manifest schema
- `felix config explain --json` output schema

## Verification

- Test repo with nested `AGENTS.md` files at root + `src/Felix.Cli/` + `tests/` → assert concatenated layered context appears in the iteration prompt in the expected order
- `.felixignore` honored: `felix search` (D) returns no hits under `publish-out/`; `.felixignore.local` override of `publish-out/` re-includes it for the local developer only
- Token budget enforced: oversized memory tree (E preview) is evicted per `eviction_order`
- `felix context inspect` JSON matches schema
- `docs-up-to-date` gate fails when a new top-level folder is added without map update
- `felix migrate --dry-run` on a v1 fixture lists every transform that would run; `--apply` is idempotent on second invocation
- `felix replay <run-id>` rehydrates the prompt context that produced a given run
- `felix config explain context.budget_tokens` reports `default | config | env | flag` provenance correctly

## Dogfood specs

- `specs/S-2A01-hierarchical-agents-loader.md`
- `specs/S-2A02-repo-map-command.md`
- `specs/S-2A03-felixignore-layered.md`
- `specs/S-2A04-prompt-placeholders.md`
- `specs/S-2A05-context-budgeter.md`
- `specs/S-2A06-migrate-registry.md`
- `specs/S-2A07-replay.md`
- `specs/S-2A08-config-explain.md`

## Anchor files

- [felix/felix-agent.ps1](../../felix/felix-agent.ps1) — context assembly
- [.felix/prompts/planning.md](../../.felix/prompts/planning.md), [.felix/prompts/building.md](../../.felix/prompts/building.md)
- [.felix/config.json](../../.felix/config.json)
- [src/Felix.Cli/Program.Commands.cs](../../src/Felix.Cli/Program.Commands.cs) — add `repo-map`, `context`, `migrate`, `replay`, `config explain`
- [scripts/install.ps1](../../scripts/install.ps1), [scripts/setup-dev-environment.ps1](../../scripts/setup-dev-environment.ps1) — wire `.felixignore` generation
- [AGENTS.md](../../AGENTS.md) — gains `## Map` section
