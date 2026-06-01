# Phase Contracts Registry

> **Status:** Active
> **Owner:** v2 migration
> **Last-Touched:** 2026-05-29

Each phase freezes interfaces here when it ships. Later phases may **extend** (add optional fields, add new commands) but **cannot break** (remove fields, change semantics, rename flags) without a `BREAKING:` annotation and a major version bump.

Through v2.3 this registry is **reviewer-enforced** (PR checklist). Automated enforcement via `felix contracts check` is deferred until the first phase actually breaks a contract — see [PHASE_A5_DISTRIBUTION.md § AS3](PHASE_A5_DISTRIBUTION.md).

**A.5's frozen schemas (events, hooks, plugin manifest) are candidate v1:** B/C/D/E may amend additively without `BREAKING:` through v2.3, since those phases are the first real consumers.

---

## Phase A (v2.0) — Context Foundation

### Layered context blob

- Plain-text concatenation of `AGENTS.md` files walked from `cwd` to repo root
- Deepest file first; section header per level: `<!-- felix:layer path="<relpath>" hash="<sha8>" -->`
- Trailing footer: `<!-- felix:layered-context hash="<sha16>" tokens="<n>" -->`

### `.felixignore`

- Gitignore-compatible subset
- Layered lookup (two layers, deepest-pattern-wins within each):
  1. Repo-root `.felixignore` (committed)
  2. `%USERPROFILE%/.felix/ignore` (user scope, cross-repo)
- Per-directory walk-up and `.felixignore.local` deferred until a bench fixture demonstrates they pay

### `context` config block

```json
{
  "context": {
    "budget_tokens": 32000
  }
}
```

Required: `budget_tokens`. `weights` and `eviction_order` are code constants in v2.0; promoted to config when a bench-backed user request demands tuning.

### `felix context inspect --json`

```json
{
  "_v": 1,
  "budget_tokens": 32000,
  "sources": [
    {
      "name": "layered_agents",
      "tokens": 1240,
      "weight": 0.15,
      "evicted": false
    }
  ],
  "total_tokens": 8420,
  "would_evict": []
}
```

### `felix migrate` registry

- Permanent v1→v2 transform tool; recognition of v1 layouts never sunset
- Flags: `--dry-run`, `--apply`, `--only <transform-id>` (no `--revert`; recovery is `git revert` the migration commit — Felix migrations are forward-only)
- `--apply` is required for writes; without it, `felix migrate` previews planned transforms and exits without modifying the repo
- Later phases register transforms via this interface (B: spec fix, prompts→skills; F: tools.allow seed)
- Idempotent on second invocation

### `migrate-transform` registration shape

Phases register transforms with the registry above. Frozen shape:

```ts
{
  id: string,           // stable, kebab-case (e.g. "spec-frontmatter")
  name: string,         // human-readable
  applies(repo): bool,  // cheap precondition check; false = skip silently
  dryRun(repo): Diff,   // returns proposed file changes; no side effects
  apply(repo): void     // writes changes; idempotent
}
```

- **Idempotency contract:** a second `apply()` against an already-migrated repo is a no-op (no error, no diff). Tested by running `felix migrate --apply` twice in CI on each transform's fixture.
- `felix migrate --dry-run` renders by calling each registered transform's `dryRun()` and concatenating diffs in registration order.
- New transforms registered by later phases are additive; new ids do not bump the registry's `_v`.

### `felix run replay <run-id>` _(deferred)_

- Verb registered in A; snapshot manifest (`runs/<run-id>/replay.json`) deferred until one debugging session needs it
- Until then, `runs/<id>/iteration-N/prompt.txt` (already written) is the canonical "what fed the model" artifact
- When shipped: required snapshot fields are layered-context-blob hash, prompt-template hashes, agent profile, config snapshot, ignore-policy snapshot; does not re-execute the agent
- Alias: `felix replay` (back-compat)

### `felix config explain` _(cut)_

Deferred. Reopen when a user files a config-opacity issue.

### Run-ID grammar

- Current: `S-NNNN-YYYYMMDD-HHMMSS-itK` (unchanged in v2; H disambiguates parallel work via `worker_id`)

---

## Phase A.5 (v2.0.x) — Distribution Substrate

### `.felix/events.jsonl` line schema

Required fields (immutable):

```json
{
  "ts": "ISO8601",
  "run_id": "string",
  "phase": "string",
  "kind": "dotted.string",
  "payload": {}
}
```

Optional: `plugin`, `worker_id`, `correlation_id`, `severity`.

### `manifest-hashes.json`

```json
{
  "_v": 1,
  "plugins": {
    "<id>": {
      "version": "x.y.z",
      "sha256": "...",
      "installed_at": "ISO8601",
      "source": "<url|path>"
    }
  }
}
```

### `plugin.json` v1

Fields as documented in [docs/PLUGINS.md](../../docs/PLUGINS.md); A.5 pins the schema here. Required: `id`, `name`, `version`, `api_version`, `hooks`. Schema file: `.felix/plugins/plugin-manifest.schema.json`.

### Hook signatures

- Extension of existing `[.felix/plugins/hook-contracts.ps1](../../.felix/plugins/hook-contracts.ps1)`
- All hooks receive `$HookName`, `$RunId`, `$Data`, `$Config`
- All hooks return optional hashtable with `Success`, `Metadata`

### CLI

- `felix plugin install <source> [--no-verify] [--source-allowlist <host,...>]`
- `felix plugin list [--json]`
- `felix plugin remove <id>`
- `felix plugin info <id>`
- `felix event tail [--kind ...] [--run-id ...] [--since <dur>] [--follow]` (alias: `events`)
- `felix event query <expr> [--json]` (alias: `events`)
- `felix doctor [--fix]` — extensible; phases register checks. v2.0 ships with checks for: stale leases (H), orphaned worktrees (H), corrupt event log, plugin manifest hash mismatches, repo-map staleness (A), spec frontmatter (B), stale prompt-review (E), `.felixignore` debug (`--explain <path>`)

### `doctor-check` registration interface

Frozen shape for any phase that wants to extend `felix doctor`:

```ts
{
  id: string,                          // stable, kebab-case (e.g. "stale-lease")
  severity: "warn" | "error",          // "warn" is informational; "error" fails the command
  message: string,                     // human-readable; may include path or count
  fix?: () => void                     // optional non-destructive repair; absent = report only
}
```

`felix doctor --json` output schema:

```json
{
  "_v": 1,
  "checks": [
    {
      "id": "stale-lease",
      "severity": "warn",
      "status": "pass|fail",
      "message": "..."
    }
  ]
}
```

- **Late-registration model:** A.5 ships only the checks for already-shipped phases. B/E/H register their checks on their own release. Adding a new check id is additive and does **not** bump `_v`; consumers iterate over `checks[]` and ignore unknown ids.
- A check whose owning phase has not shipped is simply absent from the `checks[]` array (not a stub with `status: "skipped"`).

---

## Phase B (v2.1) — Skills & Spec Frontmatter

### `skill.json` v1

Required: `id`, `name`, `description`, `version`, `prompt` (path to fragment).
Optional: `triggers.{commands,applyTo,tags,keywords,always}`.

### Spec frontmatter v1

Required: `id`, `title`, `status`.
Optional: `applyTo`, `tags`, `skills`, `gates`, `depends_on`, `priority`, `block_reason` (free-form string, populated when `status: blocked`).
Lifecycle states: `draft | planned | in-progress | complete | blocked`. (No `reviewed`/`approved` states — promotion = human edit.)

### CLI

- `felix skill list|show|enable|disable`
- `felix spec fix|create`
- Spec frontmatter validation folded into `felix doctor` (no separate `spec lint` verb)
- `felix spec create` always emits frontmatter for new specs (closes the migration loop)
- `felix spec review` / `felix spec approve` **cut**; promotion = human edit

---

## Phase C (v2.2) — Exploration Subagent

### `context-map.md` schema

Required sections (markdown headings):

- `## Files likely to change`
- `## Files to read for context`
- `## Symbols of interest`
- `## Related tests`
- `## Prior runs`

Natural ordering within each section is the ranking signal in v2.2. Numeric rank suffixes deferred until a bench fixture demonstrates rank-driven eviction is net-positive.

### `explore` config block

```json
{
  "explore": {
    "enabled": false,
    "auto_enable_when": { "min_tracked_files": 500 },
    "skip_on_iteration_gt": 1,
    "agent_override": null,
    "max_tokens": 8000
  }
}
```

Default OFF; `felix setup` / `felix migrate` flip `enabled: true` when `auto_enable_when` signal is met.

### Hooks

- `OnPreExplore($HookName, $RunId, $Data{Requirement}, $Config)`
- `OnPostExplore($HookName, $RunId, $Data{ContextMapPath, Requirement}, $Config)`

### Phase ordering

`explore → plan → build → validate` (skip rules per `explore` config and `skip_on_iteration_gt`)

---

## Phase D (v2.3) — Search

### `felix search` CLI

```
felix search "<pattern>" [--scope file|symbol] [--in code|specs|runs|all]
                         [--max N] [--related-to S-NNNN] [--json]
```

### `--json` schema (frozen)

```json
{
  "_v": 1,
  "matches": [{"path":"...","line":N,"col":N,"text":"...","symbol":"...","rank":0.0,"context":["",""]}],
  "truncated": false,
  "total": N,
  "ignored_globs": [],
  "fallback": false
}
```

### `search-cache.json`

Per-run; format owned by Felix; consumers read but do not write.

### `pre-bash` hook (D6) _(cut)_

Raw-grep guard rail cut from v2.3. `felix search` exposed as a registered tool via D5/MCP is the primary path; the guard is a belt-on-suspenders we don't ship until bench shows agents continue to raw-grep at scale after MCP exposure.

### `{{SEARCH_HINTS}}` placeholder

_Removed._ D7 was cut; Phase C's `context-map.md` is the universal-coverage mechanism for non-tool-calling adapters.

---

## Phase D′ (v2.4) — Navigation

### `felix navigate` CLI

```
felix navigate definition <symbol> <file:line> [--json]
felix navigate references <symbol> [--json]
felix navigate callers <symbol> [--json]
felix navigate implementations <symbol> [--json]
```

### `--json` schema

```json
{"_v":1,"results":[{"path":"...","line":N,"col":N,"kind":"definition|reference|caller|impl","preview":"..."}],"fallback":false}
```

### Tool exposure contract (MCP-first; fallback shim)

- Primary: `felix mcp serve` exposes `search`, `navigate`, `query` as MCP tools
- Fallback: per-adapter shim with the same logical contract
- **Selection rule:** MCP wins when `felix mcp serve` is running; shim is strict fallback for adapters without MCP support
- Input: `{"tool":"<name>","args":{...},"caller":"<adapter|mcp-client>"}`
- Output: `{"ok":bool,"data":{...},"error":{"code":"...","message":"..."} | null}`
- Errors include `denied_by_allowlist`, `tool_not_found`, `arg_invalid`, `lsp_unavailable` (with `fallback: true` data if D fallback fired)

### `lsp-bridge` plugin

Auto-detection rules and daemon control commands documented in the plugin's manifest; pinned here.

### `felix mcp serve` CLI

- Flags: `--port <n> | --socket <path>`, `--tools <list>`, `--allow-from <client-id,...>`
- Lists registered tools at startup via MCP tools/list

---

## Phase E (v2.4) — Self-Improving Loop + Memory

### `.felix/memory/` layout

- `global/*.md` (sourced from `%USERPROFILE%/.felix/memory/global/`)
- `repo/*.md`
- `requirement/S-NNNN/*.md`
- Each file: optional YAML frontmatter (`created`, `promoted`, `tags`); body is freeform markdown

### `agents-md-suggestions.md` schema

Required sections:

- `## Proposed AGENTS.md additions`
- `## Proposed memory entries`
- `## Proposed prompt edits`

### CLI

- `felix memory view|add|edit|prune`
- `felix review [--learnings|--prompts|--all|--acknowledge]` (unified surface; replaces separate `learnings review` and `prompts review` verbs)
- Stale-review reminder folded into `felix doctor` (no `OnLoopStart` banner hook)
- `learning-capture` plugin **enabled by default** on `felix setup`; writes proposals only to `runs/<id>/agents-md-suggestions.md`. Disable via `learning.auto_propose: false`.
- Auto-prune scope: `runs/.../agents-md-suggestions.md` only; `.felix/memory/` is never auto-modified by the loop

---

## Phase F (v2.5) — Targeted Execution + Security

### Backpressure

- `commands[].appliesTo` (glob array; absent = always-run, v1 compat)
- `always_run` (string array of command names)

### `felix query` CLI

```
felix query <kind> [<key=value>...] [--json]
```

Kinds: `requirements`, `runs`, `state`. (Other resources use first-class verbs: `felix event query`, `felix plugin list`, `felix skill list`, `felix memory view`.)
Output schema versioned per-kind (`"_v": 1`).

### `tools` config

```json
{ "tools": { "allow": ["..."], "deny": ["..."], "default": "allow" } }
```

- v1→v2 migrated repos and new `felix setup` repos start `default: "allow"` with full audit logging
- `felix tool harden` is the one-time opt-in that flips `default` to `"deny"` after proposing an allowlist derived from recent audit logs (alias: `felix tools harden`)

### `kind=tool.call` event payload

```json
{"tool":"string","args":{},"allowed":bool,"caller":"string","denial_reason":"string|null"}
```

### `felix gc`

Flags: `--dry-run`, `--yes`, `--older-than <dur>`. Config: `gc.retention_days` (default 30). Prunes old `runs/`, rotated event files, and orphaned worktrees.

---

## Phase H (v2.6) — Concurrency & Worktrees

### Lease file schema (`.felix/.locks/<requirement-id>.lock`)

Required: `worker_id`, `run_id`, `claimed_at`, `lease_until`, `pid`.

### `felix loop --parallel N [--worktrees]`

- N ≥ 1; default 1 (v1 behavior)
- `--worktrees` is opt-in; without it, parallel workers share the single working tree
- Each worker registers in `.felix/sessions.json` with `worker_id`

### `.felix/sessions.json` extensions

Added fields: `worker_id`, `parallel_group`, `worktree_path` (nullable when `--worktrees` not in use).

### `block_reason` metadata

Free-form string on a requirement with `status: blocked`. Canonical values documented here so downstream tooling (TUI, sync) can render icons/colors:

- `merge-conflict` (H4)
- `budget` (cost guardrails)
- `validation-retries-exhausted` (loop)
- `backpressure-retries-exhausted` (loop)

New values may be added by phases without `BREAKING:`; document them here.

### `felix run recover`

- `felix run recover --run <id> | --all [--yes]` (alias: `felix recover`)
- Surfaces a structured plan before mutating lease files, worktrees, or partial commits

---

## Phase G (v2.7) — Marketplace (minimal)

### `plugins.json` index schema

Versioned (`"schema": "https://felix.dev/plugins-index/v1.json"`). Single index URL only (`distribution.index_url`). Multi-index support deferred until one corporate user asks. See [PHASE_G_MARKETPLACE.md](PHASE_G_MARKETPLACE.md) for full shape.

### CLI

- `felix plugin list|update [--remote] [--channel stable|beta]` (extends A.5's `plugin` verb)
- `felix skill install <source>`

_Packs (`pack.json`), `felix plugin certify`, and the certification GitHub Action are cut from v2; reopen when ≥3 external plugins exist._

---

## Change log

| Date       | Phase | Change                                                                                                                                                                                                | By            |
| ---------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| 2026-05-29 | —     | Registry created                                                                                                                                                                                      | v2 planning   |
| 2026-05-29 | A     | A6 run-ID change cut; A7 `migrate` registry, A8 `config explain`, `replay` added                                                                                                                      | review pass   |
| 2026-05-29 | A.5   | AS3 enforcement deferred; `doctor` ownership assigned here; `event` (singular) preferred verb                                                                                                         | review pass   |
| 2026-05-29 | B     | Spec lifecycle collapsed (no `reviewed`/`approved` states); lint enforcement opt-in until repo clean                                                                                                  | review pass   |
| 2026-05-29 | C     | `explore` default OFF; auto-enable on repo-size signal                                                                                                                                                | review pass   |
| 2026-05-29 | D     | D7 prompt-augmentation fallback cut (context-map covers it)                                                                                                                                           | review pass   |
| 2026-05-29 | D′    | Tool exposure unified: MCP-first, per-adapter shim as fallback; D5 a–d collapsed                                                                                                                      | review pass   |
| 2026-05-29 | E     | E2/E3/E4 merged into `felix review` unified surface; E7 auto-prune scoped to proposals only                                                                                                           | review pass   |
| 2026-05-29 | F     | F7 sandbox cut; `query` kinds trimmed to 3; default-allow + `tools harden`; `gc` owned here                                                                                                           | review pass   |
| 2026-05-29 | H     | Worktrees opt-in; `block_reason` metadata replaces `blocked-merge-conflict` state; `recover` owned here                                                                                               | review pass   |
| 2026-05-29 | G     | Packs + certification cut; minimum-viable marketplace only                                                                                                                                            | review pass   |
| 2026-05-29 | —     | Verb-naming convention switched to `<noun> <verb>` for resource commands; renames: `repo-map`→`repo map`, `replay`→`run replay`, `recover`→`run recover`, `tools harden`→`tool harden` (aliases kept) | review pass 2 |
| 2026-05-29 | A     | A2 `repo-map build` folded into `doctor --fix`; A3 simplified to 2 layers; A5 weights/eviction dropped from config; A7 snapshot manifest deferred; A8 `config explain` cut                            | review pass 2 |
| 2026-05-29 | A.5   | `doctor` extended to absorb repo-map staleness, spec frontmatter lint, stale-review reminder, ignore debug; A.5 freezes treated as candidate v1 through v2.3                                          | review pass 2 |
| 2026-05-29 | B     | B7 `spec lint` folded into `doctor`; B8 `spec review`/`spec approve` + `spec-critic` skill cut; `spec create` always emits frontmatter                                                                | review pass 2 |
| 2026-05-31 | A     | `felix migrate --revert` cut (recovery = `git revert`); `migrate-transform` registration shape frozen with idempotency contract                                                                       | review pass 3 |
| 2026-05-31 | A.5   | `doctor-check` registration interface + `--json` schema frozen; late-registration model documented                                                                                                    | review pass 3 |
| 2026-05-31 | B     | Spec lifecycle parenthetical reworded (cut `spec approve` reference)                                                                                                                                  | review pass 3 |
| 2026-05-31 | E     | Config key renamed `learnings.auto_propose` → `learning.auto_propose` (singular noun convention)                                                                                                      | review pass 3 |
| 2026-05-29 | C     | C5 ranks dropped from contract; natural ordering only                                                                                                                                                 | review pass 2 |
| 2026-05-29 | D     | D6 raw-grep guard cut                                                                                                                                                                                 | review pass 2 |
| 2026-05-29 | E     | E3 reminder hook cut (folded into `doctor`); `learning-capture` confirmed default-on                                                                                                                  | review pass 2 |
| 2026-05-29 | F     | Cost guardrails simplified to static $5/$20 defaults; profile-aware quotas deferred                                                                                                                   | review pass 2 |
| 2026-05-29 | H     | H4 pre-merge "non-FF triggers re-plan" cut; block + `block_reason` is the path                                                                                                                        | review pass 2 |
| 2026-05-29 | G     | Multi-index support cut; single `index_url`                                                                                                                                                           | review pass 2 |
