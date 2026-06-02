# Release Notes v2.0.0

Date: 2026-06-02

## Highlights

Felix v2 is a major release delivering eight phases of new capabilities for autonomous agent execution at scale. The headline features are parallel multi-worker loops with git worktree isolation, a curated plugin/skill marketplace, persistent agent memory, full-text search across runs, and a comprehensive documentation overhaul.

## New Features

### Phase A — Context & Continuity
- Hierarchical `AGENTS.md` discovery (repo-root → project-root → `.felix/`)
- `.felixignore` support for excluding paths from agent context
- Token budgeter: hard cap on context size with priority-ranked inclusion
- `felix migrate` — automated schema migration for `requirements.json` and config
- `felix run replay <run-id> [--iteration N]` — re-run any saved iteration from disk
- `felix context inspect` — inspect the full context snapshot for any run
- `felix event tail / query` — live and historical event stream

### Phase B — Skills & Spec Frontmatter
- `.felix/skills/<id>/` skill packages: `skill.json` manifest + PowerShell hooks
- Spec YAML frontmatter: `gates:`, `priority:`, `tags:`, `depends_on:` fields
- `felix skill list / show / enable / disable / install` CLI
- Three-scope loading: user (`~/.felix/skills/`) → repo → project

### Phase C — Exploration Subagent
- Auto-enabled exploration pass before plan/build on large or unfamiliar repos
- `felix run --explore / --no-explore` flags to override per-run
- Configurable `explore.auto_enable_threshold` (default: 20 files changed)

### Phase D — Search & Navigation
- `felix search <query>` — full-text search across specs, runs, and context
- `felix deps [--graph] [--dot]` — requirement dependency graph
- `felix query` — structured queries over `requirements.json` (filter, sort, count)
- Per-run memoisation cache (`.felix/search-cache/`) — fast subsequent runs

### Phase E — Learning & Memory
- `.felix/memory/` three-scope tree: global, project, requirement-scoped memories
- `felix memory view / add / edit / prune` — inspect and manage agent memory
- `learning-capture` plugin: agents propose memories after completing requirements
- Memory injected into every agent context within token budget

### Phase F — Targeted Execution & Security
- Per-path backpressure: `appliesTo` glob patterns limit expensive gates to relevant changes
- `felix gc [--yes]` — garbage collection for stale runs, events, and orphaned worktrees
- Tool allowlist: `tools.allow` / `tools.deny` in config restrict agent-callable tools
- `felix tool list / enable / disable / harden` CLI
- `gates:` frontmatter on specs invokes named validation gates during `felix validate`

### Phase G — Marketplace
- Curated `docs/plugins.json` index (`schema: index-v1`) with versioning and SHA256
- `felix plugin list --remote [--channel stable|beta]` — browse available plugins
- `felix plugin install <name|url|path>` — install with SHA256 verification
- `felix plugin update [--all] [--dry-run]` — update installed plugins
- `felix skill install <name|url|path> [--scope repo|user]` — install from index
- `distribution.index_url` in config for private/internal registries

### Phase H — Concurrency & Worktrees
- `felix loop --parallel N` — N parallel workers, lease-coordinated via filesystem
- `felix loop --parallel N --worktrees` — each worker gets an isolated git worktree
- Atomic lease protocol: `.felix/.locks/<id>.lock` with 30-min TTL, 5-min refresh
- Git worktree lifecycle: `New-WorktreeForRun`, merge-back with conflict detection
- `felix recover [--run <id>] [--all] [--yes] [--dry-run]` — crash recovery for orphaned leases/worktrees
- `concurrency` config block: `worktrees`, `parallel`, `merge_strategy`, `retention_days`

## Documentation

Complete documentation overhaul in `docs/`:
- `CONFIGURATION.md` — every `config.json` key with type, default, and description
- `SKILLS.md` — skills manifest, install, authoring guide
- `CONTEXT.md` — run artifacts, event stream, replay
- `SEARCH.md` — search, deps, query commands
- `MEMORY.md` — memory system and learning proposals
- `CONCURRENCY.md` — parallel loop, lease protocol, worktrees, recovery
- `MARKETPLACE.md` — curated index, install/update, private registry
- `CLI.md` updated with all 14 new v2 commands
- `FEATURES.md` updated with v2 phase feature bullets
- `README.md` reorganised as documentation hub

## Test Coverage

416 tests passing across all phases:
- 119 C# unit tests (command registration, option shapes, subcommand structure)
- 297 PowerShell integration tests (phases B–H)

## Breaking Changes

- `felix loop` now accepts `--parallel` and `--worktrees` flags; scripts that parse loop output may see additional worker-status lines
- Agent `$Args` parameter renamed to `$CmdArgs` in all command scripts; custom plugins calling internal functions should update parameter names
- `concurrency` block in `config.json` is new and ignored by v1 clients

## Upgrade

```powershell
felix update
```

Or download the `win-x64` / `linux-x64` / `osx-arm64` / `osx-x64` release artifact directly from GitHub Releases.
