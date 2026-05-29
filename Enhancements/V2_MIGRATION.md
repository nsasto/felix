# Felix v2 — Context Layer Modernization

> **Status:** Active
> **Last-Touched:** 2026-05-29

Major-version upgrade aligning Felix's context-delivery layer with the patterns Anthropic documents for large-codebase Claude Code deployments ([reference](https://claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start)), while preserving Felix's differentiators: autonomous loop, hard backpressure, multi-vendor agents, requirement lifecycle.

This is the **umbrella plan**. Per-phase deep-dives live in [v2/](v2/).

## Why

Felix's gates and artifacts are best-in-class for an autonomous loop, but the context-delivery layer is a generation behind:

- Single root `AGENTS.md` + `CONTEXT.md` (no hierarchy)
- All prompts loaded every iteration (no on-demand skills)
- One agent does both exploration and editing (no subagent split)
- Grep-only navigation across multi-language codebases (no LSP)
- No `.felixignore`, no per-path backpressure, no memory, no event bus
- No bench harness — every change is "I think this is better"

## Themes

1. **Layered context** — hierarchical AGENTS.md + skills + repo map + memory
2. **Split exploration from editing** — subagent phase + search + LSP-backed navigation
3. **Self-improving harness** — stop hooks, prompt review cadence, memory, bench
4. **Targeted execution** — per-path backpressure, ignore policy, structured-state tool surface
5. **Distribution substrate** — plugin install + signed manifests + event bus + context budgeter (foundational, not last)
6. **Safety & observability** — secrets redaction, cost guardrails, replay, doctor, gc, i18n guard
7. **Tool exposure via MCP** — Felix exposes `search`, `navigate`, `query` through a single MCP server (D′), with per-adapter shims only for non-MCP clients. We do **not** host or consume third-party MCP servers; Felix wraps CLI agents, not the other way around.

## Phases

Each phase is independently releasable. Later phases ship reference plugins through Phase A.5.

| Phase | Version | Title                         | Plan                                                             |
| ----- | ------- | ----------------------------- | ---------------------------------------------------------------- |
| A     | v2.0    | Context Foundation            | [v2/PHASE_A_CONTEXT.md](v2/PHASE_A_CONTEXT.md)                   |
| A.5   | v2.0.x  | Distribution Substrate        | [v2/PHASE_A5_DISTRIBUTION.md](v2/PHASE_A5_DISTRIBUTION.md)       |
| B     | v2.1    | Skills & Spec Frontmatter     | [v2/PHASE_B_SKILLS.md](v2/PHASE_B_SKILLS.md)                     |
| C     | v2.2    | Exploration Subagent          | [v2/PHASE_C_EXPLORE.md](v2/PHASE_C_EXPLORE.md)                   |
| D     | v2.3    | Search                        | [v2/PHASE_D_SEARCH.md](v2/PHASE_D_SEARCH.md)                     |
| D′    | v2.4    | Navigation (LSP)              | [v2/PHASE_D_PRIME_NAVIGATION.md](v2/PHASE_D_PRIME_NAVIGATION.md) |
| E     | v2.4    | Self-Improving Loop + Memory  | [v2/PHASE_E_LEARNING.md](v2/PHASE_E_LEARNING.md)                 |
| F     | v2.5    | Targeted Execution + Security | [v2/PHASE_F_TARGETED.md](v2/PHASE_F_TARGETED.md)                 |
| H     | v2.6    | Concurrency & Worktrees       | [v2/PHASE_H_CONCURRENCY.md](v2/PHASE_H_CONCURRENCY.md)           |
| G     | v2.7    | Marketplace                   | [v2/PHASE_G_MARKETPLACE.md](v2/PHASE_G_MARKETPLACE.md)           |

## Dependency graph

```
A ──► A.5 ──► B ──► C ──► D ──► D′
       │              │
       ├──► E ────────┘
       │
       ├──► F ──► H
       │
       └──► G (last)
```

A.5 is the foundation (install + bus + budgeter) every later phase consumes.

## Cross-cutting workstreams

Documented in detail elsewhere; summary here:

- **[Bench harness](v2/BENCH.md)** _(non-negotiable)_ — frozen reference repos; gates phase merges (>10% iteration regression or >20% token regression blocks)
- **[Phase Contracts](v2/CONTRACTS.md)** — registry that freezes interfaces per phase; reviewer-enforced through v2.3, automated `felix contracts check` deferred until first break
- **Cost guardrails** — `budget.daily_tokens` / `budget.daily_usd` with two-tier `warn_at` + `hard_stop_at`. Defaults: warn at 70% of agent profile's documented daily quota, hard-stop at 100%; if profile has no quota, warn at $5/day, stop at $20/day. Override via config.
- **Secrets redaction** — regex + entropy heuristics on every artifact write; `.felix/redaction.json`; `felix scan-secrets`
- **Failure-mode commands have owning phases** (no floating cross-cutting promises):
  - `felix replay` — owned by Phase A (snapshot manifest is A's contract)
  - `felix doctor` — owned by Phase A.5 (extensible; phases register checks)
  - `felix gc` — owned by Phase F (disk pressure surfaces after runs/events/worktrees grow)
  - `felix recover` — owned by Phase H (lease + worktree state is H's contract)
- **i18n guard** — English-locked agent contract strings; post-LLM hook assertion; non-English-locale bench run
- **Docs lifecycle** — `docs/CLI.md` and `docs/PLUGINS.md` generated from registries; `docs-up-to-date` backpressure gate for `src/Felix.Cli/` changes; **AGENTS.md `## Map` staleness folded into this gate** (no separate `repo-map check`)
- **Plugin testing & CI** — required `tests/` in manifest; `felix plugin test`. (Certification pipeline cut from v2; reopen when ≥3 external plugins exist.)
- **Migration tooling** _(permanent, owned by Phase A as A6)_ — `felix migrate` recognizes v1 forever; `--dry-run`, `--only`, `--revert`. Later phases register transforms with A's registry (B: spec frontmatter + prompts→skills; F: tools.allow seed).
- **TUI command registry** — TUI shells out to `felix <cmd> --json` for any registered command; new commands auto-surface
- **CLI verb naming convention** — nouns are singular when naming a kind (`skill`, `plugin`, `memory`, `event`, `prompt`, `learning`), plural only in collective queries. Aliases kept for back-compat on any rename.

## Scope boundaries

### In scope (v2.0–v2.7)

- All phases A–H + G above
- Cross-cutting workstreams listed
- Reference plugins for each new extension point, distributed via A.5

### Deferred to v2.x or v3 (with rationale)

- **Model-response cache** — near-zero hit rate in real loops (timestamps/IDs/diffs leak into every context); correctness risk outweighs benefit
- **Monorepo workspace (`.felix/workspace.json`)** — current "one repo, one .felix/" works for most users; multi-service coordination is a v3 concern
- **Prompt A/B framework** — bench harness gives 80% of the value; A/B is polish
- **Network-aware backpressure (HTTP/gRPC gate types)** — user-supplied shell commands with `Invoke-WebRequest` already cover the case
- **Bidirectional sync with runfelix.io** — v3 roadmap; Phase G's minimal index fills the gap meanwhile
- **Plugin packs, skill packs, certification pipeline, GitHub Action template** — cut from v2's Phase G; reopen when ≥3 external plugins exist
- **`felix exec` sandbox proxy** — originally F7; cut. Tool allowlist (F5) + audit (F6) cover the security surface; write-protection is a hook-layer deny-list, not a new CLI verb.
- **Run-ID format change** — originally A6; cut. Current format is unique enough; H disambiguates via `worker_id`.
- **Multi-user/role permissions** — single-user model is sufficient through v2
- **Air-gapped / offline operation, non-git VCS** — explicit v3 themes
- **TUI redesign** — registry pattern keeps TUI alive; full redesign is v3
- **Non-PowerShell plugin runtimes** — out of scope; PowerShell remains the runtime
- **Hosting/consuming third-party MCP servers** — out of scope. Felix _exposes_ its own tools via MCP (D′); it does not connect to external MCP servers. The article's MCP "connect to internal tools" pattern is for organizations, not for a wrapper like Felix.
- **Organizational ownership patterns** (DRI, agent manager, governance working groups) — article-motivated but Felix is the tool, not the org. Documented in tutorials, not enforced by the loop.

## Decisions

- v2.0 = Phase A; phases ship as minor bumps under v2 line through v2.7
- **A.5 ships with A**: install mechanics + event bus + budgeter are foundational
- **`felix migrate` is permanent and owned by Phase A** (A6): later phases register transforms with A's registry
- **Phase Contracts** registry freezes interfaces per phase; reviewer-enforced through v2.3
- **Bench harness gates phase merges**: >10% iteration regression or >20% token regression blocks
- PowerShell remains the plugin runtime
- LSP servers are external dependencies; installer prompts but doesn't require
- No cloud-protocol break; new artifacts sync as opaque files
- Each phase ships with `specs/S-2XXX-*` requirements Felix runs to build itself (dogfood)
- **One real cache only**: per-run search memoization (D3). Model-response cache rejected.
- **Repo overrides user scope** for skills and memory
- **Exploration phase default-off** with auto-enable based on `auto_enable_when` repo signal (e.g., ≥500 tracked files post-`.felixignore`); per-invocation override via `--explore`/`--no-explore`
- **LSP transport**: stdio per-language under supervised `lsp-bridge` daemon
- **Tool exposure is MCP-first** (`felix mcp serve` in D′); per-adapter shim only as fallback for non-MCP clients
- **Tool allowlist defaults to `allow`** on v1→v2 migrated and new `felix setup` repos, with full audit logging; `felix tools harden` is the one-time opt-in that flips to default-deny
- **No new lifecycle states for failure modes**; `status: blocked` + `block_reason` (free-form string) absorbs `merge-conflict`, `budget`, future cases
- **Agent output language locked to English** for contract strings; user-facing strings localizable

## Resolved defaults

- **Bench harness location**: sibling `bench/` repo (won't bloat main repo); minimal in-tree smoke fixtures live in `tests/bench-smoke/` for PR signal without the sibling checkout
- **Event Bus retention**: 30 days, configurable via `events.retention_days`
- **Cost guardrails**: enabled by default with two-tier `warn_at` + `hard_stop_at`; warn at 70% of agent profile's documented daily quota, hard-stop at 100%; if profile has no quota, warn at $5/day, stop at $20/day

## Anchor files (high-touch areas)

- [felix/felix-agent.ps1](../felix/felix-agent.ps1), [felix/felix-loop.ps1](../felix/felix-loop.ps1) — explore phase, layered-context loader, parallel worker support
- [.felix/prompts/planning.md](../.felix/prompts/planning.md), [.felix/prompts/building.md](../.felix/prompts/building.md) — consume layered context + skills + context-map + memory
- [.felix/prompts/](../.felix/prompts/) — most files become skills under new `/skills` tree
- [.felix/plugins/](../.felix/plugins/) — add `lsp-bridge`, `learning-capture`; formalize `manifest-hashes.json`
- [.felix/config.json](../.felix/config.json) — new sections: `context`, `skills`, `explore`, `budget`, `tools`, `backpressure.commands[].appliesTo`
- [src/Felix.Cli/](../src/Felix.Cli/) — new commands enumerated per phase
- [AGENTS.md](../AGENTS.md) — gains "## Map" section
- **New trees**: `bench/`, `.felix/memory/`, `.felix/events.jsonl`, `.felix/migrations/`
- **Release notes**: `release_notes/RELEASE_NOTES_v2.{0..7}.md`
