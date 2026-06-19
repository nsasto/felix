# Setup & Configuration

> **Quick links:** [Installation](#installation) · [felix setup](#felix-setup) · [felix agent](#felix-agent) · [felix tool](#felix-tool) · [felix migrate](#felix-migrate) · [felix doctor](#felix-doctor) · [felix gc](#felix-gc) · [felix update](#felix-update)

---

## Installation

### PowerShell CLI (Original)

```powershell
.\.felix\felix.ps1 run S-0001
```

Optional PATH install: `.\scripts\install-cli.ps1` → then use `felix run S-0001`

### C# CLI (Cross-Platform)

```powershell
.\scripts\install-cli-csharp.ps1   # One-time build + PATH install
Felix.Cli.exe run S-0001
Felix.Cli.exe dashboard            # Interactive status overview
```

Both CLIs share the same backend: `Felix.Cli.exe` → `.felix/felix.ps1` → `scripts/*.ps1`. No logic duplication.

### Global Installer

```powershell
# Windows
irm https://felixai.dev/install.ps1 | iex

# macOS / Linux
curl -sSL https://felixai.dev/install.sh | bash
```

After installation: `felix install` once per machine, then `felix setup` in any project.

---

## `felix setup`

```bash
felix setup
```

**What it does:** Guided wizard for configuring a Felix project from scratch (or reconfiguring an existing one). Safe to re-run — idempotent, never overwrites files that already exist.

The installed CLI presents this flow with a richer Spectre.Console interface instead of a plain `Read-Host` prompt sequence. Searchable pickers are used where they reduce setup friction, while the resulting files and defaults stay compatible with the PowerShell backend.

**Steps:**

1. **Confirm project folder** — defaults to current directory; accepts a different path
2. **Scaffold** — creates missing `policies/`, `specs/`, `runs/`, `config.json`, `requirements.json`, `state.json`, and templates including `.felix/model-pricing.json.example` (idempotent)
3. **AGENTS.md check** — offers to create a starter repository operations guide if one does not exist
4. **Agent profile setup** — optional searchable multi-select of installed providers plus per-provider model selection; writes `.felix/agents.json`
5. **Active agent selection** — searchable chooser for which configured profile is active in `.felix/config.json` (`agent.agent_id`)
6. **Auto-select shortcut** — if exactly one agent profile exists, setup auto-selects it and skips the chooser
7. **Test command** — prompts for backpressure test command
8. **Mode choice** — local (no server) or remote (server-backed team mode)
9. **Remote config** — in remote mode, prompts for backend URL and API key, validates key, then offers `spec pull` + `spec fix`
10. **Usage tracking next steps** — shows the `felix doctor` -> `felix run <requirement-id>` -> `felix query usage --since 7d` workflow

**Note:** Setup now distinguishes between configuring agent profiles (`.felix/agents.json`) and choosing the active profile (`.felix/config.json`) so you are not asked to re-pick providers from a hardcoded list.

**When to use:**

- Bootstrapping a brand-new project
- Onboarding a new team member on an existing project
- After a global `felix install` to set up a project without copying engine files

---

## `felix agent`

Manage agent profiles stored in `.felix/agents.json`.

### `felix agent list`

```bash
felix agent list
```

Renders a table showing current profile, key, provider, model, and executable status.

```
Current  Key          Name    Provider  Model    Executable
*        ag_ee77df894 claude  claude    sonnet   claude
-        ag_16fffb5a4 codex   codex     default  codex
```

The `*` marks your current agent (configured in `.felix/config.json`). Agent IDs are content-addressed keys (`ag_XXXXXXXXX`) generated from agent config.

### `felix agent current`

```bash
felix agent current
```

Shows the currently configured agent with full details.

### `felix agent setup`

```bash
felix agent setup
```

Interactive configuration for agents and default models. Writes or updates `.felix/agents.json` with selected agents and models.

The installed CLI presents this as a searchable multi-select with provider status, preselects already-configured profiles, and then prompts for a model for each selected provider. Providers that are not installed are shown but cannot be selected, and the command points you to `felix agent install-help <name>` for installation guidance.

For `copilot`, Felix currently uses a curated static model list instead of querying the CLI dynamically. Direct Copilot runs use `-p` prompt mode plus `--output-format json` so Felix can parse the JSONL event stream for the effective model, session ID, and reported output tokens. On Windows, Felix spills long prompts to a temporary prompt file and passes Copilot a short instruction to read that file, avoiding command-line length limits. Felix retries without `--model` if a configured Copilot model is no longer available.

If Copilot launches but returns blank output, run a direct probe:

```powershell
copilot -p "Reply exactly HELLO" --yolo --no-ask-user --output-format json
```

If the probe is also blank, check authentication (`copilot login`) and proxy/network environment variables such as `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `GIT_HTTP_PROXY`, and `GIT_HTTPS_PROXY`. A blocked local proxy, for example `http://127.0.0.1:9`, prevents Copilot from reaching GitHub and Felix can only record `usage_available: false`.

### `felix agent use <id|name>`

```bash
felix agent use claude
felix agent use claude --model sonnet

# Interactive selection
felix agent use
```

**What it does:** Updates `.felix/config.json` to use a different agent profile from `.felix/agents.json`.

If you pass `--model` and that model changes the agent identity, Felix also rewrites the matching entry in `.felix/agents.json` with the new deterministic `ag_...` key before updating `.felix/config.json`.

When you launch `felix agent use` without a target, the installed CLI shows a searchable picker of configured profiles and, when the provider has multiple known models, a second picker that lets you keep the current model or switch to another one.

If you prefer wording that emphasizes the persistent default rather than the immediate switch, use the alias `felix agent set-default`.

### `felix agent set-default <id|name>`

```bash
felix agent set-default claude
felix agent set-default copilot

# Interactive selection
felix agent set-default
```

**What it does:** Updates `.felix/config.json` to persist the default agent Felix should use for future runs. This is an alias for the same underlying operation as `felix agent use`, but named for the "set my default" workflow.

Like `felix agent use`, the command can also update `.felix/agents.json` when a model switch produces a different deterministic agent key.

**Why you'd switch:**

- `droid` is fast and cheap, good for bulk work
- `claude` has better reasoning for complex problems
- `codex` uses a diff-based workflow (different UX)
- `gemini` if you want to test Google's model
- `copilot` uses GitHub Copilot CLI autopilot locally

**Behind the scenes:** Agents are just different LLM adapters with different executables. They all speak the same protocol (JSON events) and follow the same workflow, but have different strengths.

### `felix agent test <id|name>`

```bash
felix agent test droid
```

Runs a quick smoke test to verify:

1. Executable is in PATH
2. The executable can be launched
3. A version probe works, or is skipped safely if unsupported

Use this after installing a new agent executable or updating versions.

For end-to-end usage tracking, run one small requirement and then inspect usage:

```powershell
felix run S-0000
felix query usage --run-id <run-id> --json
felix doctor
```

The smoke passes when `usage_available` is `true`, the effective model is populated, and `felix doctor` reports `[ok] [usage-artifacts]`.

### `felix agent register`

```bash
felix agent register
```

**What it does:** Registers the current agent profile (from `.felix/agents.json`) with the sync server so it appears in the UI Fleet view and can claim work via `GET /api/sync/work/next`.

- Shows the target URL and API key prefix before attempting
- Prompts to proceed if sync is disabled in config
- Continues safely in non-interactive shells by using the configured sync values without prompting
- Safe to re-run — uses an upsert (`ON CONFLICT DO UPDATE`) so repeated calls just refresh metadata
- Surfaces backend error detail inline: key mismatch, git URL mismatch, DB errors

**Agent keys are content-addressed:**

```
ag_ + first 9 chars of sha256("{provider}::{model}::{}::{machine}::{git_url}")
```

This means `.felix/agents.json` only needs `name`, `provider`, and `model` — no manual UUIDs. `felix setup` generates a correct `agents.json` automatically.

See [tuts/MULTI_AGENT_SUPPORT.md](../tuts/MULTI_AGENT_SUPPORT.md) for the full adapter architecture.

### `felix agent install-help [name]`

```bash
felix agent install-help
felix agent install-help copilot
```

Prints install and login guidance for all supported agents, or for one named agent. Use this when `felix agent setup` shows `Agent not installed` and you need concrete steps for that provider.

---

## `felix tool`

Manage the agent tool allowlist (Phase F security).

```powershell
# Show current allowlist and audit stats
felix tool status

# List enabled tools
felix tool list

# Enable or disable a specific tool
felix tool enable search.*
felix tool disable navigate.references

# Flip default to deny, infer allowlist from audit log
felix tool harden
felix tool harden --dry-run    # Preview without writing
felix tool harden --yes        # Skip confirmation prompt
```

After `felix tool harden`, the `tools` block in `config.json` is updated:

```json
"tools": {
  "allow": ["search.*", "navigate.*"],
  "deny":  [],
  "default": "deny"
}
```

Alias: `felix tools harden` (deprecated in next minor).

---

## `felix migrate`

Transform a v1 repository layout to v2. Preview by default; `--apply` is required to write changes.

```powershell
felix migrate              # Dry-run: show pending transforms
felix migrate --apply      # Execute all pending transforms
felix migrate --dry-run    # Explicit dry-run
felix migrate --only felixignore-seed   # Run a single transform
```

**Registered transforms:**

| ID | Phase | Description |
|---|---|---|
| `felixignore-seed` | A | Create `.felixignore` from default template |
| `agents-map-init` | A | Add `## Map` section to root `AGENTS.md` |
| `spec-frontmatter` | B | Add YAML frontmatter to v1 spec files |
| `explore-enable` | C | Auto-enable exploration when tracked files ≥ 500 |
| `tools-allow` | F | Seed `tools.default = "allow"` in `config.json` |

Migration is **idempotent** — re-running on an already-migrated repo is a no-op. To undo: `git revert` the migration commit. There is no `--revert` flag.

---

## `felix doctor`

Run diagnostic checks against the repository. Extensible — later phases register their own checks.

```powershell
felix doctor              # Run all checks
felix doctor --fix        # Run checks and apply non-destructive repairs
felix doctor --json       # Machine-readable output

# Explain why a specific file is ignored by .felixignore
felix doctor --explain publish-out/MyApp.exe
```

**Registered checks:**

| Check | Phase | Description |
|---|---|---|
| `event-log` | A | Detect corrupt or truncated `.felix/events.jsonl` |
| `plugin-hashes` | A | Detect plugin manifest hash mismatches |
| `repo-map-stale` | A | New top-level folder without entry in `AGENTS.md ## Map` |
| `spec-frontmatter` | B | Required frontmatter fields present; gates/skills/applyTo valid |
| `stale-review` | E | Last `felix review` > 90 days ago |
| `usage-artifacts` | F | Token/model usage artifacts exist and are readable |
| `usage-pricing` | F | Observed models have matching local pricing rules when usage exists |
| `stale-leases` | H | Lease files past their `lease_until` timestamp |
| `orphaned-worktrees` | H | Worktree directories not tracked in active sessions |

For usage reporting, `felix doctor` warns when existing runs do not have `usage.json`, when provider output lacks token/model data, or when cost estimates need `.felix/model-pricing.json`.

**Exit codes:** `0` all checks passed · `1` one or more checks failed · `2` invalid arguments

---

## `felix gc`

Prune stale run artifacts, event log rotations, and orphaned worktrees.

```powershell
felix gc               # Interactive — prompts before each category
felix gc --dry-run     # Preview what would be pruned
felix gc --yes         # Non-interactive — prune without confirmation
```

**What is pruned:**

- `runs/` directories older than `gc.retention_days` (default: 30). The most-recent successful run per requirement is always kept.
- `.felix/events-*.jsonl` rotation files older than `gc.events_retention_days` (default: 30).
- `.felix/worktrees/<run-id>/` directories not referenced by an active session.

Config keys: `gc.retention_days`, `gc.events_retention_days` — see [CONFIGURATION.md](CONFIGURATION.md).

---

## `felix update`

**What it does:** Checks GitHub Releases for the newest Felix build, compares it to the local installed version, and stages the matching platform package for replacement.

```bash
felix update

# See whether a newer release exists
felix update --check

# Install without prompting
felix update --yes
```

**What actually happens:**

- Detects the current platform release ID
- Fetches the latest release metadata from GitHub
- Selects the matching zip artifact and checksum manifest
- Verifies the downloaded package before staging it
- Prompts before install unless you pass `--yes`
- Launches a helper that swaps binaries after the current process exits

**When to use it:**

- You installed Felix globally and want the newest published release
- You want a safe checksum-verified upgrade path
- You need a non-interactive upgrade step for scripts or provisioning

**When not to use it:**

- You are doing a first-time local source checkout and plan to run from the repo directly
- You specifically want to stay on an older pinned release

**Install versus update:** `felix install` is the bootstrap path. `felix update` is the release-upgrade path. If no existing installed copy is found in the target install directory, `felix update` can still stage the latest release there.

Supported release identifiers: `win-x64` · `linux-x64` · `osx-x64` · `osx-arm64`

**Troubleshooting:**

- Network failures: retry and confirm GitHub Releases is reachable. Proxy, firewall, or transient GitHub API failures will surface as update check or download errors.
- Checksum failures: do not force the install. Re-run to fetch a clean copy. If the mismatch persists, treat the release asset or download path as suspect.
- Unsupported platform errors: Felix only updates from published release assets for supported RIDs. If your machine reports an unsupported platform, install from source or use a supported published build target.

---

## `felix version`

```bash
felix version
```

Displays the Felix CLI version, current git branch, and short commit hash. Useful for bug reports and confirming which version is installed.

**Example output:**

```
Felix CLI v0.3.0-alpha (Phase 1: PowerShell)
Repository: C:\dev\myproject
Branch: main
Commit: a3f8c12
```

---

## `felix help`

```bash
felix help
felix help run
felix help loop
felix help spec
felix help context
felix help agent
felix help deps
felix help procs
felix help tui
```

Prints usage, options, and examples for any command. Running `felix help` with no argument prints the full command list.

---

*See also: [RUNNING.md](RUNNING.md) for executing requirements · [SPECS.md](SPECS.md) for spec management · [CONFIGURATION.md](CONFIGURATION.md) for config.json reference · [SYNC_OPERATIONS.md](SYNC_OPERATIONS.md) for sync setup · [CLI.md](CLI.md) for global options and the full command index*
