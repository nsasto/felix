# Agents - How to Operate This Repository

This file tells Felix **how to run the system**.

## Install

```powershell
git clone https://github.com/nsasto/felix.git
cd felix
.\scripts\install.ps1
```

Or download the installer from [GitHub Releases](https://github.com/nsasto/felix/releases/latest).

## Run Felix

### CLI Commands

```powershell
# Set up a new project
cd C:\your\project
felix setup

# Run agent on a requirement
felix run S-0001

# Verify first-run usage tracking without touching real requirements
felix smoke usage --dry-run
felix smoke usage

# Run in continuous loop mode
felix loop

# Launch interactive TUI dashboard
felix tui
```

### Running the Agent Directly (PowerShell)

```powershell
# Start the agent for a repository
.\felix\felix-agent.ps1 C:\dev\your-project

# Alternative: run the looped runner
.\felix\felix-loop.ps1 C:\dev\your-project
```

### Agent Profiles

- Agent profiles live in **.felix/agents.json** in the target repo.
- User profile **%USERPROFILE%\.felix\agents.json** is no longer used.

## Run Tests

```powershell
# Run Felix CLI unit tests (C# / xUnit)
dotnet test tests\Felix.Cli.Tests\

# Run Phase B PowerShell unit tests (skill-loader, frontmatter-parser)
.\tests\Test-PhaseB.ps1

# Run Phase C PowerShell unit tests (explore subagent: Get-ExploreConfig, Test-ExploreEnabled, Assert-ContextMapSchema)
.\tests\Test-PhaseC.ps1

# Run Phase D PowerShell unit tests (search: Get-SearchCacheKey, SearchCache, Get-RelatedFiles, JSON schema)
.\tests\Test-PhaseD.ps1

# Run Phase E PowerShell unit tests (learning: Get-RunEvents, Get-MemoryContext, memory/review CLI, doctor, learning-capture)
.\tests\Test-PhaseE.ps1

# Run Phase F PowerShell unit tests (targeted execution: path-matcher, backpressure v2, query, tool-allowlist, gc)
.\tests\Test-PhaseF.ps1

# Run Phase G PowerShell unit tests (marketplace: index-client, Compare-SemVer, plugin update, skill install)
.\tests\Test-PhaseG.ps1

# Run Phase H PowerShell unit tests (concurrency: lease-manager, worktree-manager, recover, parallel loop)
.\tests\Test-PhaseH.ps1

# Run Graphify integration tests
.\tests\Test-Graphify.ps1

# Run Felix CLI integration test against a live felix installation
.\run-test-spec.ps1
```

## Validate Requirement

Run requirement-level acceptance verification for a specific requirement. The validation script reads validation/acceptance criteria from the spec file and executes any commands specified.

This command answers: "Did we achieve this requirement per its criteria?"

This command is separate from loop backpressure checks. Backpressure gates each iteration before commit; `felix validate` checks requirement completion criteria.

```bash
# Validate a specific requirement
felix validate S-0002

# Machine-readable output (for CI / dashboards)
felix validate S-0002 --json

# If `py -3` is not available, use `python` or set the full Python executable path in `.felix/config.json` under `python.executable`.

# Example output:
# Validating Requirement: S-0002
# ✅ Tests pass: `pytest` (exit code 0)
# VALIDATION PASSED for S-0002
```

### Exit Codes

**Validation Script (validate-requirement.py):**

- `0` - All acceptance criteria passed
- `1` - One or more acceptance criteria failed
- `2` - Invalid arguments or requirement not found

**Felix Agent (felix-agent.ps1):**

- `0` - Success: requirement complete and validated
- `1` - Error: general execution failure (droid errors, file I/O issues)
- `2` - Blocked: backpressure failures exceeded max retries (default: 3 attempts)
- `3` - Blocked: validation failures exceeded max retries (default: 2 attempts)

When the agent exits with code 2 or 3, the requirement is automatically marked as "blocked" in `.felix/requirements.json`. To unblock:

1. Fix the underlying issues (tests, validation criteria, or code)
2. Manually edit `.felix/requirements.json` and change status from `"blocked"` to `"planned"`
3. Restart the agent - it will pick up the unblocked requirement

### Validation Criteria Format

Specs should include testable validation criteria with commands and expected outcomes. The script looks for "## Validation Criteria" first, then falls back to "## Acceptance Criteria":

```markdown
## Validation Criteria

- [ ] Tests pass: `pytest` (exit code 0)
- [ ] Lint clean: `npm run lint` (exit code 0)
```

**Important:** Only use backticks for actual executable commands. Do NOT use backticks for:

- File paths (use **bold** instead: **src/main.py**)
- URLs (use plain text: http://localhost:3000)
- Placeholders (use plain text: {ComputerName})
- Configuration values (use plain text or **bold**)

The validation script executes anything in backticks as a shell command. If it's not meant to be executed, don't use backticks.

## Graphify (Optional)

```powershell
# Check Graphify setup
felix graphify status

# Local graph for agent investigation
felix graphify setup --local
felix graphify build

# Team graph workflow
felix graphify setup --team
felix graphify build
git add graphify-out .gitignore .felix/skills/graphify-investigator
git commit -m "chore(graphify): add team graph"
```

Team mode commits **graphify-out/**, ignores **graphify-out/cost.json**, and can ignore **graphify-out/cache/** to keep the repo small. After code commits, commit graph refreshes separately as `chore(graphify): refresh graph`. Docs/papers require `felix graphify update`.

## Sync Configuration (Optional)

Enable artifact mirroring to [runfelix.io](https://runfelix.io) via the **sync-http plugin**. Quick start:

```powershell
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "https://runfelix.io"
$env:FELIX_SYNC_KEY = "fsk_your_api_key_here"  # Required when sync enabled
```

Or use the `--sync` CLI flag for a single run: `felix run S-0001 --sync`

See **docs/SYNC_OPERATIONS.md** for full configuration, troubleshooting, and architecture details.

## Explore Subagent (Phase C)

The explore phase is a read-only pass that runs before plan/build and writes `runs/<run-id>/context-map.md`. It lets the agent discover relevant files and patterns without burning plan/build tokens.

**CLI flags:** `felix run S-0001 --explore` (force on) / `--no-explore` (force off)

**Config block** (`.felix/config.json`):

```json
"explore": {
  "enabled": false,
  "auto_enable_when": { "min_tracked_files": 500 },
  "skip_on_iteration_gt": 1,
  "agent_override": null,
  "max_tokens": 8000
}
```

**Auto-enable:** `felix migrate --apply` sets `enabled: true` automatically when `git ls-files` >= 500.

**Plugin hooks fired:** `OnPreExplore` (before), `OnPostExplore` (after). `OnPostExplore` receives `ContextMapPath` and `ContextMapContent`.

**Required context-map sections:** `## Files likely to change`, `## Files to read for context`, `## Symbols of interest`, `## Related tests`, `## Prior runs`. Missing sections are injected with `_(no data)_` placeholders.

**Core script:** `.felix/core/explore.ps1` — functions: `Get-ExploreConfig`, `Test-ExploreEnabled`, `Assert-ContextMapSchema`, `New-ExplorePrompt`, `Invoke-ExplorePhase`, `Test-AgentReadOnly`

## Search (Phase D)

Felix-aware, `.felixignore`-scoped search command backed by ripgrep (falls back to `Select-String`).

**CLI:** `felix search "<pattern>" [--scope file|symbol] [--in code|specs|runs|all] [--max N] [--json] [--related-to <req-id>]`

**Memoisation:** per-run cache at `runs/<run-id>/search-cache.json`, keyed by `SHA1(query|flags)`. Set `FELIX_RUN_DIR` env var to activate caching within an agent run. Cache deleted with the run (no cross-run staleness).

**`--related-to <req-id>`:** assembles files referenced in that requirement's `context-map.md` and iteration plan files across all matching runs. Returns `{ "files": [...], "total": N, "source": "<req-id>" }`.

**Core scripts:**
- `.felix/commands/search.ps1` — `Invoke-Search`, `Get-RelatedFiles`
- `.felix/core/search-cache.ps1` — `Get-SearchCacheKey`, `Get-SearchCache`, `Set-SearchCache`, `Clear-SearchCache`

## Learning, Memory, and Review (Phase E)

Felix captures learnings from run events and exposes them for curation via `felix review` and `felix memory`.

**`felix review`:**
- `--learnings` — walk `agents-md-suggestions.md` proposals; accept/reject/defer to AGENTS.md
- `--prompts` — audit `.felix/prompts/` and `.felix/skills/` for stale model-workaround patterns
- `--all` — both in sequence
- `--acknowledge` — stamp `last_review` in `state.json` (clears doctor warning)
- `--dry-run` — preview without writing or committing

**`felix memory`:**
- `view [--scope global|repo|requirement] [--req <id>]` — list memory entries
- `add --scope <s> --title "<t>" --body "<b>" [--req <id>]` — create a new memory file
- `edit <file>` — open in `$EDITOR` (falls back to notepad)
- `prune [--older-than <days>] [--dry-run]` — prune old `agents-md-suggestions.md` proposal files only

**Memory tree scopes:**
- `global` — `%USERPROFILE%\.felix\memory\global\` — applies to all projects
- `repo` — `.felix/memory/repo/` — applies to this repo
- `requirement` — `.felix/memory/requirement/<req-id>/` — requirement-specific notes

Memory files use YAML frontmatter: `title`, `scope`, `created`, `tags`. They are NEVER auto-deleted; only proposal files in `runs/*/agents-md-suggestions.md` are pruned.

**`felix doctor` stale-review check:** warns when `last_review` is missing or older than 90 days. Run `felix review --acknowledge` to clear.

**learning-capture plugin** (`OnPostIteration` hook): reads `events.jsonl` via `Get-RunEvents` and writes `runs/<run-id>/agents-md-suggestions.md`. Disable with `Config.learning.auto_propose = false`.

**Core scripts:**
- `.felix/commands/review.ps1` — `Invoke-Review`
- `.felix/commands/memory.ps1` — `Invoke-Memory`
- `.felix/core/event-reader.ps1` — `Get-RunEvents`
- `.felix/core/memory-loader.ps1` — `Get-MemoryContext`
- `.felix/plugins/learning-capture/on-postiteration.ps1` — OnPostIteration hook

## Targeted Execution + Security (Phase F)

Phase F adds per-path backpressure filtering, requirement gate validation, query/audit/GC CLI commands, and tool allowlist hardening.

**`felix query`:**
```powershell
felix query requirements [--status planned|in-progress|done|blocked] [--since <date>] [--json]
felix query runs         [--requirement S-0001] [--json]
felix query usage        [--since <date|7d|24h>] [--requirement S-0001] [--run-id <id>] [--json]
felix query state        [--json]
```
All outputs use versioned `_v:1` JSON when `--json` is passed.

**Usage tracking:** each agent execution writes `runs/<run-id>/usage.json` with agent, provider, model, session, duration, and token counts when the provider reports them. `felix query usage` totals these records. Optional cost estimates read `.felix/model-pricing.json` (start from `.felix/model-pricing.json.example` and add current provider prices). `felix doctor` reports missing/corrupt usage artifacts and missing pricing coverage.

**`felix tool`:**
```powershell
felix tool status                     # show current policy (default-allow/deny, patterns)
felix tool harden [--yes] [--dry-run] # flip to deny; infer allowlist from audit log
```
Tool calls are logged to `events.jsonl` as `tool.call` events regardless of policy. After running the agent enough cycles to populate the audit log, run `felix tool harden` to switch to an explicit allowlist.

**`felix gc`:**
```powershell
felix gc             # prune stale runs, event rotations, orphaned worktrees (asks for confirmation)
felix gc --dry-run   # preview what would be deleted
felix gc --yes       # skip confirmation
```
GC always preserves the last successful run per requirement regardless of age. Configure retention in `.felix/config.json`: `gc.retention_days` (default 30), `gc.events_retention_days` (default 30).

**Per-path backpressure (F1):** Backpressure commands now support an `appliesTo` field so expensive checks only run when relevant files changed:
```json
"backpressure": {
  "commands": [
    { "name": "dotnet.test", "cmd": "dotnet test --no-build", "appliesTo": ["src/**", "tests/**"] },
    { "name": "npm.lint",    "cmd": "npm run lint",           "appliesTo": ["*.ts", "*.tsx"] }
  ],
  "always_run": ["dotnet.test"]
}
```
Old plain-string format (`"commands": ["cmd1"]`) is still accepted (runs always).

**Validation gates (F2):** Spec files can declare `gates:` in YAML frontmatter to run specific backpressure commands during `felix validate`:
```markdown
---
id: S-0005
gates: [dotnet.test, npm.lint]
---
```

**Core scripts:**
- `.felix/core/path-matcher.ps1` — `Test-GlobMatch`, `ConvertTo-GlobRegex`
- `.felix/core/tool-allowlist.ps1` — `Test-ToolAllowed`, `Test-AllowlistDecision`, `Emit-ToolCallEvent`
- `.felix/commands/query.ps1` — `Invoke-Query`
- `.felix/commands/tool.ps1` — `Invoke-Tool`
- `.felix/commands/gc.ps1` — `Invoke-Gc`

## Marketplace (Phase G)

Phase G adds a curated plugin/skill index, remote list/update, and `felix skill install`.

**`felix plugin update`:**
```powershell
felix plugin list --remote [--channel stable|beta]   # list with available-update column
felix plugin update --all [--dry-run] [--channel stable|beta]
felix plugin update <id>  [--dry-run]
felix plugin install <name|./path|https://url.zip> [--channel stable|beta]
```

**`felix skill install`:**
```powershell
felix skill install <name>           # from index (felix_min + SHA256 verified)
felix skill install ./local/path     # copy local skill dir to .felix/skills/<id>/
felix skill install https://url.zip  # download, verify, extract
felix skill install <name> --scope user  # install to user scope (~/.felix/skills/)
```

**Index config** (`.felix/config.json`):
```json
"distribution": {
  "index_url": "https://nsasto.github.io/felix/plugins.json",
  "channels": ["stable"]
}
```
Override `index_url` for a private/internal registry.

**Core scripts:**
- `.felix/core/index-client.ps1` — `Get-PluginIndex`, `Get-DistributionConfig`, `Compare-SemVer`, `Get-CompatibleVersion`, `Test-IndexEntrySha256`, `Install-FromIndexEntry`
- `docs/plugins.json` — reference curated index (`schema: index-v1`)

**Tests:** `tests/Test-PhaseG.ps1` (53 tests).


## Concurrency & Worktrees (Phase H)

Phase H adds parallel worker support, git worktree lifecycle management, atomic requirement leases, and crash recovery.

**`felix loop --parallel N`:**
```powershell
felix loop --parallel 4              # 4 concurrent workers (lease-coordinated)
felix loop --parallel 4 --worktrees  # each worker gets its own git worktree
```

**`felix recover` / `felix run recover`:**
```powershell
felix recover --all               # list all orphaned leases/worktrees
felix recover --run <run-id>      # recover a specific orphaned run
felix recover --all --yes         # apply fixes without prompts
felix recover --all --dry-run     # show plan only
```

**Lease protocol:**
- Atomic claim: `.felix/.locks/<req-id>.lock` created with `FileMode.CreateNew` (O_CREAT|O_EXCL equivalent)
- TTL: 30 min, refreshed every 5 min by running worker
- Expired lease is auto-reclaimed by next `New-RequirementLease` caller
- `Test-RequirementLeased`, `Get-AllLeases`, `Get-ExpiredLeases` for inspection

**Worktree lifecycle:**
- Created at `.felix/worktrees/<run-id>/` with `.felix-worktree.json` metadata
- `Merge-WorktreeToBase` returns "ok"/"conflict"/"error"
- `Remove-StaleWorktrees` prunes based on `concurrency.retention_days`
- `Get-ActiveWorktrees` reads all metadata files

**Config** (`.felix/config.json`):
```json
"concurrency": {
  "worktrees": false,
  "parallel": 1,
  "merge_strategy": "merge",
  "retention_days": 3
}
```

**Core scripts:**
- `.felix/core/lease-manager.ps1` — `New-RequirementLease`, `Test-LeaseValid`, `Update-LeaseExpiry`, `Remove-RequirementLease`, `Get-AllLeases`, `Get-ExpiredLeases`
- `.felix/core/worktree-manager.ps1` — `New-WorktreeForRun`, `Remove-WorktreeForRun`, `Merge-WorktreeToBase`, `Get-ActiveWorktrees`, `Remove-StaleWorktrees`, `Get-WorktreeConfig`
- `.felix/commands/recover.ps1` — `Invoke-Recover`, `Find-OrphanedRuns`
- `.felix/commands/loop.ps1` — updated with `--parallel`/`--worktrees` flags, `Invoke-LoopParallel`

**Tests:** `tests/Test-PhaseH.ps1` (44 tests).


## Sync Troubleshooting

For sync errors, outbox management, configuration examples, emergency disable, and log viewing, see **docs/SYNC_OPERATIONS.md**.

Quick checks:

```powershell
# Pending uploads
(Get-ChildItem .felix\outbox\*.jsonl -ErrorAction SilentlyContinue).Count

# Recent sync errors
Select-String -Path .felix\sync.log -Pattern "ERROR" -ErrorAction SilentlyContinue | Select-Object -Last 5
```

## Repository Conventions

- Keep this file operational only
- No planning or status updates
- No long explanations
- If it wouldn't help a new engineer run the repo, it doesn't belong here

## CLI Scope

Felix CLI configuration and execution are always local to the machine running it.

## Version Bump Workflow (Agent)

When asked to bump a release version, do this sequence exactly:

1. Choose the target version (example: `1.1.0`) and keep the same value everywhere below.
2. Update required version files:
   - `.felix/version.txt` (used by release packaging scripts)
   - `src/Felix.Cli/Felix.Cli.csproj` `<Version>` value
3. Add release notes file at `release_notes/RELEASE_NOTES_v<major>.<minor>.md` (or next repo convention), with date, highlights, fixes, and breaking changes if any.
4. Validate build/release artifacts:
   - `powershell -File .\scripts\package-release.ps1 -Rid win-x64`
5. Commit changes:
   - `git add .felix/version.txt src/Felix.Cli/Felix.Cli.csproj release_notes/*`
   - `git commit -m "chore(release): bump version to v<version>"`
6. Create annotated git tag:
   - `git tag -a v<version> -m "Release v<version>"`
7. Push commit and tag:
   - `git push`
   - `git push origin v<version>`

Notes:

- `scripts/package-release.ps1` reads `.felix/version.txt` for artifact names.
- Update release server `latest.txt` to the new version when publishing artifacts.
