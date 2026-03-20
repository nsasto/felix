# The Felix CLI

Complete reference for the Felix command-line interface — commands, options, workflows, and conventions.

> **Quick links:** [Core Commands](#the-core-commands-your-daily-drivers) · [Update Command](#felix-update---refresh-the-installed-cli) · [Spec Management](#specification-management) · [Agent Management](#agent-management) · [Global Options](#global-options-the-switches-that-work-everywhere) · [Exit Codes](#the-exit-code-contract-what-they-mean) · [Workflows](#common-workflows)

---

## Mental Model

Felix runs an **autonomous loop**, not a chat.

- Loads a small set of files each iteration
- Runs in either planning or building mode
- Produces one concrete outcome
- Updates state on disk
- Continues to next task

**Felix runs to completion by default.** You start it, it finishes the work, then stops.

All memory lives in files, not conversation state:

- You can stop and resume anytime
- Progress is visible in git commits
- No chat history to maintain
- State is inspectable and recoverable

---

## Repository Layout

A Felix-enabled repository typically looks like this:

```
.
├── specs/                         # Requirements (markdown)
│   ├── CONTEXT.md
│   └── auth-email-signin.md
├── AGENTS.md                      # How to run the system
├── .felix/
│   ├── requirements.json          # Central registry and status
│   ├── state.json                 # Agent control state
│   ├── config.json                # Sync, agent, executor settings
│   ├── agents.json                # LLM agent profiles
│   ├── sessions.json              # Active process tracking
│   ├── outbox/                    # Sync queue (when enabled)
│   ├── prompts/
│   │   ├── planning.md
│   │   └── building.md
│   └── plugins/
│       └── sync-http/             # HTTP sync plugin
├── runs/
│   └── <run-id>/
│       ├── plan-<req-id>.md       # Working plan
│       ├── commands.log.jsonl     # Execution log
│       ├── diff.patch             # Git diff
│       └── report.md              # Run summary
└── app/                           # Your application code
```

---

## Core Concepts

Felix separates **content**, **structure**, and **action**:

- **Markdown** holds meaning (specs, plans, context)
- **JSON** holds structure and status (requirements.json, state.json)
- **Plans** hold next actions (per-requirement, disposable)
- **Sync** (optional) mirrors artifacts to server for team visibility

### Specs (`specs/`)

One topic per file. Narrow scope. No implementation detail. Stable over time.

**Good filenames:** `auth-email-signin.md`, `billing-invoice-download.md`
**Bad:** a single giant PRD, files mixing requirements and task lists.

### Requirements Registry (`.felix/requirements.json`)

Slim index — only what Felix needs to schedule and track work:

```json
{
  "requirements": [
    {
      "id": "S-0001",
      "title": "Auth email sign-in",
      "spec_path": "specs/auth-email-signin.md",
      "status": "planned",
      "commit_on_complete": false
    }
  ]
}
```

Rich metadata (`priority`, `tags`, `depends_on`) lives in `specs/*.meta.json` sidecars. Keep `requirements.json` boring and stable.

**Status values:** `draft` → `planned` → `in_progress` → `complete` / `blocked`

### Validation Criteria (the "Forever Checkbox")

Leave checkboxes **unchecked** — Felix re-runs them every iteration:

```markdown
- [ ] Backend healthy: `curl localhost:8080/health` (status 200)
```

Only use backticks for **actual executable commands**. Use **bold** for file paths, plain text for URLs and placeholders.

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

To update an existing install from GitHub Releases:

```powershell
felix update
felix update --check
```

Use `felix update --yes` to skip the interactive confirmation prompt.

The updater downloads the latest published release for the current platform, verifies the checksum manifest, stages the payload in a temporary directory, and replaces the installed files after the current Felix process exits.

Supported release identifiers:

- `win-x64`
- `linux-x64`
- `osx-x64`
- `osx-arm64`

If the install directory does not already contain Felix, `felix update` treats the latest release as the install target and bootstraps that location.

---

## The Core Commands: Your Daily Drivers

### `felix run <requirement-id>` - Execute One Thing

**What it does:** Tells the agent "work on this specific requirement until it's done or you hit a wall."

```bash
felix run S-0001
```

**When to use it:**

- You have a specific requirement ready to implement
- You want focused, controlled execution
- You're testing a new spec before letting the agent loose

**Real-world example:**

```bash
# Execute requirement with rich terminal output (default)
felix run S-0042

# Get JSON events for parsing in scripts
felix run S-0042 --format json

# Push artifacts to backend server
felix run S-0042 --sync
```

**Behind the scenes:** Felix spawns `felix-agent.ps1` as a subprocess, streams NDJSON events from stdout, and renders them in your chosen format. The agent runs in a loop (up to 100 iterations by default) trying to complete the requirement: building context, calling the LLM, processing responses, running tests, committing changes, and validating success.

**Exit codes tell the story:**

- `0` = Success (requirement completed and validated)
- `1` = Error (agent crashed or hit an unexpected failure)
- `2` = Blocked by backpressure (tests failed too many times)
- `3` = Blocked by validation (acceptance criteria failed)

### `felix loop` - Let It Run Wild

**What it does:** Autonomously processes all planned/in-progress requirements until the backlog is empty or you stop it.

```bash
felix loop
```

**When to use it:**

- Friday afternoon before the weekend (let it work while you're gone)
- You have 20 small requirements and don't want to babysit each one
- You trust your specs and backpressure tests

**When NOT to use it:**

- Your specs are half-baked or vague
- You haven't validated your test suite catches regressions
- It's Monday morning and your boss wants a demo at 10 AM

**Options:**

```bash
# Limit to 5 requirements then stop
felix loop --max-iterations 5

# Continuously sync artifacts to backend
felix loop --sync

# Skip git commits (useful for reviewing before committing)
felix loop --no-commit
```

**Pro tip:** Loop mode creates lock files in `.felix/.locks/loop-<PID>.lock` to prevent multiple loops from colliding. If Felix crashes and leaves a stale lock, you'll need to manually clean it up.

**War story:** We once let `felix loop` run overnight on a fresh project with 30 requirements. Came back to find 28 complete, 1 blocked (flaky test), and 1 in a hilarious infinite loop arguing with itself about whether a function should be async or not. Lesson learned: always write clear acceptance criteria.

---

### `felix run-next` - Claim and Run the Next Queued Requirement

**What it does:** Finds the next available requirement and runs it immediately — server-assigned in team mode, locally-picked in solo mode.

```bash
felix run-next
felix run-next --sync    # enable sync for this run
felix run-next --format json
```

**Remote mode** (sync enabled): calls `GET /api/sync/work/next` — atomic, `FOR UPDATE SKIP LOCKED` so multiple agents on the same project never claim the same item. Marks it `reserved`, then transitions to `in_progress` when the agent starts.

**Local mode**: picks the next `in_progress` then `planned` requirement from `requirements.json`, sorted by ID.

**Exit codes:**

| Code    | Meaning                                                    |
| ------- | ---------------------------------------------------------- |
| `0`     | Requirement completed successfully                         |
| `2`/`3` | Blocked — claim auto-released back to `planned`            |
| `5`     | No work available — nothing planned or already all claimed |

The `5` exit code is designed for CI poll loops:

```powershell
while ($true) {
    felix run-next --sync
    if ($LASTEXITCODE -eq 5) { Start-Sleep 60 }  # nothing to do, wait
    elseif ($LASTEXITCODE -ne 0) { break }        # error or block needs attention
}
```

---

### `felix update` - Refresh the Installed CLI

**What it does:** Checks GitHub Releases for the newest Felix build, compares it to the local installed version, and stages the matching platform package for replacement.

```bash
felix update
```

**What actually happens:**

- Detects the current platform release ID
- Fetches the latest release metadata from GitHub
- Selects the matching zip artifact and checksum manifest
- Verifies the downloaded package before staging it
- Prompts before install unless you pass `--yes`
- Launches a helper that swaps binaries after the current process exits

**Common forms:**

```bash
# See whether a newer release exists
felix update --check

# Install without prompting
felix update --yes
```

**When to use it:**

- You installed Felix globally and want the newest published release
- You want a safe checksum-verified upgrade path
- You need a non-interactive upgrade step for scripts or provisioning

**When not to use it:**

- You are doing a first-time local source checkout and plan to run from the repo directly
- You specifically want to stay on an older pinned release

**Install versus update:** `felix install` is the bootstrap path. `felix update` is the release-upgrade path. If no existing installed copy is found in the target install directory, `felix update` can still stage the latest release there.

**Troubleshooting:**

- Network failures: retry the command and confirm GitHub Releases is reachable from the machine running Felix. Proxy, firewall, or transient GitHub API failures will surface as update check or download errors.
- Checksum failures: do not force the install. Re-run the update to fetch a clean copy. If the checksum mismatch persists, treat the release asset or download path as suspect until the published checksums and artifact match.
- Unsupported platform errors: Felix only updates from published release assets for supported RIDs. If your machine reports an unsupported platform, install from source or use a supported published build target.

---

## Status & Visibility Commands

### `felix status [requirement-id]` - What's Happening?

**Check on everything:**

```bash
felix status
```

**Check one requirement:**

```bash
felix status S-0001
```

**Get machine-readable output:**

```bash
felix status --format json
```

**What you'll see:**

- Current requirement status (planned, in_progress, complete, blocked)
- Agent name and last execution time
- Validation results
- Git commit associated with completion

**Why this matters:** When your agent has been churning for 30 minutes and you're wondering if it's actually working or stuck in a loop, `felix status` is your reality check.

### `felix list` - See the Big Picture

**All requirements:**

```bash
felix list
```

**Filter by status:**

```bash
felix list --status planned
felix list --status complete
felix list --status blocked
```

**Filter by priority:**

```bash
felix list --priority high
felix list --priority low
```

**Filter by tags (comma-separated):**

```bash
felix list --tags backend
felix list --tags backend,auth
```

**Show requirements blocked by incomplete dependencies:**

```bash
felix list --blocked-by incomplete-deps
```

**Include dependency details in output:**

```bash
felix list --with-deps
```

**JSON for scripting:**

```bash
felix list --format json | jq '.[] | select(.status == "blocked")'
```

**Useful patterns:**

```bash
# Morning standup: what got done overnight?
felix list --status complete

# Planning: what's ready to work on?
felix list --status planned

# What's stuck on unfinished dependencies?
felix list --blocked-by incomplete-deps

# Troubleshooting: what's stuck?
felix list --status blocked
```

---

## Validation & Dependencies

### `felix validate <requirement-id>` - Did It Actually Work?

**What it does:** Runs requirement-level acceptance verification from the spec file without running the full agent loop.

**What this answers:** "Has this requirement been achieved according to its own acceptance criteria?"

**What it does not do:** It does not replace loop backpressure checks. Backpressure is the per-iteration safety gate (tests/build/lint before commit), while `felix validate` is a requirement-level done check.

```bash
felix validate S-0001
```

```bash
# Machine-readable result for CI/UI
felix validate S-0001 --json
```

**Why you need this:**

1. **Testing your acceptance criteria** before letting the agent loose
2. **Debugging failures** - run validation in isolation to see what's actually broken
3. **Post-deployment checks** - validate requirements still work after merging
4. **Progress confidence** - measure completion against explicit, executable criteria

**Validation criteria format** (from your spec file):

```markdown
## Validation Criteria

- [ ] Tests pass: `pytest` (exit code 0)
- [ ] Lint clean: `npm run lint` (exit code 0)
```

**Critical rule:** Only use backticks for actual executable commands. If it's not meant to run in a shell, don't wrap it in backticks. We learned this the hard way when someone wrote:

```markdown
- [ ] File exists: `src/config.py`
```

The validator tried to execute "src/config.py" as a command and exploded. Correct version:

```markdown
- [ ] File exists: **src/config.py** (file exists)
```

### `felix deps [requirement-id]` - Dependency Detective

**Show dependencies for one requirement:**

```bash
felix deps S-0001
```

**Check if dependencies are satisfied:**

```bash
felix deps S-0001 --check
```

**See the full dependency tree:**

```bash
felix deps --tree
```

**Find what's blocking progress:**

```bash
felix deps --incomplete
```

**Why dependencies matter:** Requirements have `depends_on` relationships. If S-0005 depends on S-0003 and S-0004, the agent won't start S-0005 until both dependencies are complete. This prevents building features on top of features that don't exist yet.

**Dependency resolution is smart:**

- Transitive dependencies work (A depends on B, B depends on C → A waits for C)
- Circular dependencies are detected and rejected
- Incomplete dependencies automatically block execution

---

## Specification Management

### `felix spec create <description>` - Start a New Requirement

**Interactive mode (asks questions):**

```bash
felix spec create "Add user authentication"
```

**Quick mode (makes reasonable assumptions):**

```bash
felix spec create "Add user authentication" --quick
```

**What --quick does:**

- Skips asking for detailed description (uses the title)
- Defaults to planned status
- No dependencies
- Generates minimal acceptance criteria

**Interactive mode asks:**

1. Do you want to provide a detailed description? (y/N)
2. What status should this be? (planned/draft/in-progress)
3. Does this depend on other requirements? (comma-separated IDs)
4. Do you want to generate acceptance criteria with the agent? (y/N)

**Behind the scenes:** Felix auto-generates the next requirement ID (finds highest S-NNNN in specs/ folder and increments), creates the spec file with frontmatter, and optionally launches the agent in spec-builder mode to write detailed acceptance criteria.

**Pro tip:** Use `--quick` for small, obvious requirements. Use interactive mode for complex features that need detailed planning.

### `felix spec fix` - Sync Specs Folder with requirements.json

**Scan specs folder and fix alignment:**

```bash
felix spec fix
```

**Auto-rename duplicate spec IDs:**

```bash
felix spec fix --fix-duplicates
```

**What this does:** Scans all `S-*.md` files in `specs/` and reconciles them against `.felix/requirements.json`:

- Adds entries for spec files that are missing from `requirements.json`
- Removes stale entries for requirements that no longer have a spec file
- With `--fix-duplicates`: detects duplicate `S-NNNN` IDs and renames files to the next available ID

**When to use:**

- After manually creating or deleting spec files without using `felix spec create`/`delete`
- After cloning a repo where `requirements.json` is out of sync with `specs/`
- When you see "requirement not found" errors that don't match your spec files

### `felix spec delete <requirement-id>` - Remove a Spec

**Delete with confirmation:**

```bash
felix spec delete S-0001
```

**What gets deleted:**

- The spec file (`specs/S-NNNN.md`)
- The requirement entry in `.felix/requirements.json`

**What stays:**

- Historical run artifacts in `runs/` (for audit trail)
- Git history (no force deletion)

**Safety:** Prompts for confirmation unless you're piping input or using `--force`.

### `felix spec status <requirement-id> <status>` - Update Requirement Status

**Change the status of a requirement:**

```bash
felix spec status S-0042 planned
felix spec status S-0042 in_progress
felix spec status S-0042 complete
felix spec status S-0042 blocked
```

**What it does:** Updates the `status` field for the given requirement in `.felix/requirements.json`. Useful for manually overriding status without hand-editing the JSON file.

**Common use cases:**

- Unblocking a blocked requirement: `felix spec status S-0042 planned`
- Manually marking something complete: `felix spec status S-0042 complete`
- Forcing a requirement back into the queue: `felix spec status S-0042 in_progress`

**Equivalent to:** opening `.felix/requirements.json` and editing `"status"` directly, but without the risk of malforming the JSON.

### `felix spec pull` - Sync Specs from Server

**Pull all specs that are out of date:**

```bash
felix spec pull
```

**Preview without writing any files:**

```bash
felix spec pull --dry-run
```

**Force overwrite of local files even if they exist:**

```bash
felix spec pull --force
```

**Also delete local specs that no longer exist on the server:**

```bash
felix spec pull --delete
```

**What it does:**

1. Calls `POST /api/sync/specs/check` with a manifest of local file hashes
2. Server responds with which files are missing, outdated, or current
3. Downloads only the files that differ (`.md` specs and `.meta.json` sidecars)
4. Writes them to `specs/` in the project

**What are `.meta.json` sidecars?**

Each spec has an accompanying `specs/S-NNNN-name.meta.json` file containing rich metadata stored in the server DB:

```json
{
  "priority": "high",
  "tags": ["backend", "auth"],
  "depends_on": ["S-0001", "S-0002"],
  "updated_at": "2026-02-23"
}
```

- Generated automatically on `spec create` and `spec fix`
- Gitignored (`specs/*.meta.json`) so they don't pollute version control
- Used by the agent loop to resolve `depends_on` for the current requirement
- Downloaded fresh each time via `felix spec pull`

**When to use it:**

- Before starting work in remote/team mode to get the latest server state
- When another team member has updated spec priorities or dependencies
- After `felix setup` on a new clone — pull specs before running the loop

**Authentication:** Requires `sync.api_key` in `.felix/config.json` or `FELIX_SYNC_KEY` env var.

```bash
# Typical workflow before running the agent loop in team mode
felix spec pull
felix loop
```

### `felix spec push` - Upload Local Specs to Server

**Upload all specs:**

```bash
felix spec push
```

**Preview without uploading:**

```bash
felix spec push --dry-run
```

**Re-upload all even if unchanged:**

```bash
felix spec push --force
```

**What it does:** Reads all `*.md` files from `specs/`, encodes them as base64, and sends them in a single batch to `POST /api/sync/specs/upload`. The server decodes and upserts each spec into the `requirement_content` table (DB-authoritative storage).

**Authentication:** Requires `sync.api_key` in `.felix/config.json` or `FELIX_SYNC_KEY` env var.

**When to use:**

- After creating or editing specs locally that you want remote agents to pick up
- Before starting a distributed team session — push local changes so others get them via `felix spec pull`
- After bulk-creating specs with `felix spec create --quick`

**Typical team workflow:**

```bash
# Developer A: create and push specs
felix spec create "Add rate limiting" --quick
felix spec push

# Agent on another machine: pull and work
felix spec pull
felix loop
```

---

## Context Management

### `felix context build` - Generate Project Documentation

**Standard build:**

```bash
felix context build
```

**Include hidden files:**

```bash
felix context build --include-hidden
```

**Skip overwrite confirmation:**

```bash
felix context build --force
```

**What it does:** Launches the agent to autonomously analyze your project and generate `CONTEXT.md` - a comprehensive document describing:

- Project purpose and architecture
- Tech stack and dependencies
- File structure and organization
- Key components and how they connect
- Development setup and workflows

**Why this exists:** Every project needs a "README for your brain" that explains the big picture. Rather than manually maintaining this (and watching it go stale), let the agent regenerate it periodically.

**Pro tip:** Run this after major architectural changes or before onboarding new team members. The agent will analyze file patterns, dependency graphs, import statements, and configuration files to understand your stack.

**Time commitment:** Usually takes 2-5 minutes depending on project size.

### `felix context show` - View Current Context

```bash
felix context show
```

Displays `CONTEXT.md` content in your terminal. Useful for quick reference without opening an editor.

### `felix context push` - Upload Project Docs to Server

**Upload all three docs:**

```bash
felix context push
```

**Preview without uploading:**

```bash
felix context push --dry-run
```

**Re-upload even if content is unchanged:**

```bash
felix context push --force
```

**What it does:** Reads `README.md`, `CONTEXT.md`, and `AGENTS.md` from the repo root, computes SHA256 hashes, skips files that haven't changed since the last push (using `.felix/manifest-hashes.json` as the cache), and uploads changed files to `PATCH /api/projects/{id}/manifest`.

Content is base64-encoded before sending to ensure safe transport of any special characters.

**Authentication:** Requires `sync.api_key` in `.felix/config.json` or `FELIX_SYNC_KEY` env var.

**When to use:**

- After updating `CONTEXT.md` to reflect architectural changes
- After modifying `AGENTS.md` with new agent instructions
- Keeping the UI project page and remote agents in sync with your local docs

### `felix context pull` - Download Project Docs from Server

**Download changed docs:**

```bash
felix context pull
```

**Preview without writing files:**

```bash
felix context pull --dry-run
```

**Overwrite local files not in the manifest cache:**

```bash
felix context pull --force
```

**What it does:** Calls `GET /api/projects/{id}/manifest`, compares each field's hash against the cached values in `.felix/manifest-hashes.json` (written after the last pull or push), and writes only the files that have changed. Shows `[SKIP]` for up-to-date files and `[OK]` for files that were updated.

**Authentication:** Requires `sync.api_key` in `.felix/config.json` or `FELIX_SYNC_KEY` env var.

**When to use:**

- When another team member has updated docs and pushed them
- Before a work session to ensure you have the latest `AGENTS.md`
- After another machine has run `felix context push`

**Typical workflow:**

```bash
# Morning sync before starting work
felix context pull
felix spec pull
felix loop
```

---

## Project Setup

### `felix setup` - Interactive Configuration Wizard

```bash
felix setup
```

**What it does:** Guided wizard for configuring a Felix project from scratch (or reconfiguring an existing one). Safe to re-run — idempotent, never overwrites files that already exist.

The installed CLI now presents this flow with a richer Spectre.Console interface instead of a plain `Read-Host` prompt sequence. Searchable pickers are used where they reduce setup friction, while the resulting files and defaults stay compatible with the PowerShell backend.

**Steps:**

1. **Confirm project folder** — defaults to current directory; accepts a different path
2. **Scaffold** — creates missing `policies/`, `specs/`, `config.json`, `requirements.json`, `state.json` and templates (idempotent)
3. **AGENTS.md check** — offers to create a starter repository operations guide if one does not exist
4. **Agent profile setup** — optional searchable multi-select of installed providers plus per-provider model selection; writes `.felix/agents.json`
5. **Active agent selection** — searchable chooser for which configured profile is active in `.felix/config.json` (`agent.agent_id`)
6. **Auto-select shortcut** — if exactly one agent profile exists, setup auto-selects it and skips the chooser
7. **Test command** — prompts for backpressure test command
8. **Mode choice** — local (no server) or remote (server-backed team mode)
9. **Remote config** — in remote mode, prompts for backend URL and API key, validates key, then offers `spec pull` + `spec fix`

**Note:** Setup now distinguishes between configuring agent profiles (`.felix/agents.json`) and choosing the active profile (`.felix/config.json`) so you are not asked to re-pick providers from a hardcoded list.

**When to use:**

- Bootstrapping a brand-new project
- Onboarding a new team member on an existing project
- After a global `felix install` to set up a project without copying engine files

---

## Agent Management

### `felix agent list` - See Available Agents

```bash
felix agent list
```

**Output:**

```
Available Agents:

* ID: ag_ee77df894 - claude
  Provider: claude
  Executable: claude
  Adapter: claude

  ID: ag_16fffb5a4 - codex
  Provider: codex
  Executable: codex
  Adapter: codex
```

The `*` marks your current agent (configured in `.felix/config.json`).
Agent IDs are content-addressed keys (`ag_XXXXXXXXX`) generated from agent config.

### `felix agent current` - What Am I Using?

```bash
felix agent current
```

Shows the currently configured agent with full details.

### `felix agent setup` - Configure Agents

```bash
felix agent setup
```

Interactive configuration for agents and default models. This writes or updates
`.felix/agents.json` with selected agents and models.

The installed CLI presents this as a searchable multi-select with provider status,
preselects already-configured profiles, and then prompts for a model for each selected provider.
Providers that are not installed are shown but cannot be selected, and the command points you to `felix agent install-help <name>` for installation guidance.

For `copilot`, Felix currently uses a curated static model list instead of querying the CLI dynamically. The default Copilot model is `gpt-5.4`.

### `felix agent install-help [name]` - Show Install Instructions

```bash
felix agent install-help
felix agent install-help copilot
```

**What it does:** Prints install and login guidance for all supported agents, or for one named agent.

**When to use this:** When `felix agent setup` shows `Agent not installed` and you need concrete steps for that provider.

### `felix agent use <id|name>` - Switch Agents

```bash
felix agent use claude
```

```bash
felix agent use claude --model sonnet
```

**Interactive selection:**

```bash
felix agent use
```

**What it does:** Updates `.felix/config.json` to use a different agent profile from `.felix/agents.json`.

When you launch `felix agent use` without a target, the installed CLI shows a searchable picker of configured profiles and, when the provider has multiple known models, a second picker that lets you keep the current model or switch to another one.

**Why you'd switch:**

- `droid` is fast and cheap, good for bulk work
- `claude` has better reasoning for complex problems
- `codex` uses a diff-based workflow (different UX)
- `gemini` if you want to test Google's model
- `copilot` uses GitHub Copilot CLI autopilot locally

**Behind the scenes:** Agents are just different LLM adapters with different executables. They all speak the same protocol (JSON events) and follow the same workflow, but have different strengths.

### `felix agent test <name>` - Smoke Test an Agent

```bash
felix agent test droid
```

**What it does:** Runs a quick smoke test to verify:

1. Executable is in PATH
2. Agent responds to commands
3. JSON event stream works
4. Basic code generation works

**When to use this:** After installing a new agent executable or updating versions.

### `felix agent register` - Register Agent with Sync Server

```bash
felix agent register
```

**What it does:** Registers the current agent profile (from `.felix/agents.json`) with the sync server so it appears in the UI Fleet view and can claim work via `GET /api/sync/work/next`.

- Shows the target URL and API key prefix before attempting
- Prompts to proceed if sync is disabled in config
- Safe to re-run — uses an upsert (`ON CONFLICT DO UPDATE`) so repeated calls just refresh metadata
- Surfaces backend error detail inline: key mismatch, git URL mismatch, DB errors

**Agent keys are content-addressed:**

```
ag_ + first 9 chars of sha256("{provider}::{model}::{}::{machine}::{git_url}")
```

This means `.felix/agents.json` only needs `name`, `provider`, and `model` — no manual UUIDs. `felix setup` generates a correct `agents.json` automatically.

See [tuts/MULTI_AGENT_SUPPORT.md](../tuts/MULTI_AGENT_SUPPORT.md) for the full adapter architecture.

---

## Process Management

### `felix procs` - See What's Running

```bash
felix procs
felix procs list
```

**Shows:**

- Session ID (run identifier)
- Requirement being executed
- Agent name
- Process ID (PID)
- Running duration
- Status (running/paused)

**Example output:**

```
Active Sessions:

  Session: S-0042-20260217-143022-it1
  Requirement: S-0042
  Agent: droid
  PID: 18432
  Duration: 12:34
  Status: running
```

**Why this matters:** Sometimes you spawn `felix loop` in a background terminal and forget about it. `felix procs` shows you it's still churning away.

### `felix procs kill <session-id>` - Stop a Runaway Process

```bash
felix procs kill S-0042-20260217-143022-it1
```

**Kill all running sessions at once:**

```bash
felix procs kill all
```

**What it does:** Gracefully terminates an agent process:

1. Sends termination signal
2. Waits for agent to finish current iteration
3. Cleans up lock files
4. Updates requirement status

**When you need this:**

- Agent is stuck in an infinite loop
- You realized the spec is wrong mid-execution
- You need to free up CPU/memory for something else

**Safety:** This is a graceful shutdown. The agent finishes its current LLM call before exiting and commits any pending changes.

---

## Utility Commands

### `felix tui` - Interactive Terminal Dashboard

```bash
felix tui
```

Also available as:

```bash
felix dashboard
```

**What it does:** Launches an interactive terminal UI (built with .NET/Spectre.Console) that provides:

- Visual requirement status and progress tracking
- Interactive command menu (run, loop, validate, etc.)
- Real-time status visualization

**Navigation:**

| Key   | Action            |
| ----- | ----------------- |
| `1-5` | Quick actions     |
| `/`   | Show all commands |
| `?`   | Help screen       |
| `q`   | Quit dashboard    |

**Requirements:** .NET SDK (`dotnet` CLI) must be installed. The TUI is the C# `src/Felix.Cli` project and is separate from the PowerShell CLI.

### `felix version` - Show Version Information

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

### `felix help [command]` - Command Reference

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

## Global Options: The Switches That Work Everywhere

### `--format <json|plain|rich>` - Control Output Style

**JSON (machine-readable):**

```bash
felix run S-0001 --format json
```

Every event as a complete JSON object on one line. Perfect for:

- Parsing in scripts
- Piping to other tools
- Remote execution / headless environments

**Plain (human-readable text):**

```bash
felix run S-0001 --format plain
```

Simple colored text output. Good for:

- Basic terminal environments
- Log files
- CI/CD pipelines where colors might break

**Rich (default, fancy):**

```bash
felix run S-0001 --format rich
```

Enhanced visuals with:

- Progress indicators
- Colored output
- Formatted tables
- Statistics summary

**Default:** Rich format for interactive terminals, JSON for scripts/pipelines.

### `--verbose` - See Everything

```bash
felix run S-0001 --verbose
```

**What you get:**

- Debug-level log messages
- Internal state transitions
- LLM prompt construction details
- File I/O operations
- Git command execution

**When to use it:**

- Debugging agent behavior
- Understanding why a requirement failed
- Learning how Felix works internally

**Warning:** VERY chatty. Your terminal will scroll like the Matrix.

### `--quiet` - Shut Up and Work

```bash
felix run S-0001 --quiet
```

**What gets suppressed:**

- Info-level messages
- Progress indicators
- Statistics

**What you still see:**

- Errors (obviously)
- Warnings
- Final status

**Use case:** Background jobs, cron tasks, CI/CD where you only want to know if it failed.

### `--no-stats` - Skip the Summary

```bash
felix run S-0001 --no-stats
```

Normally Felix shows a summary at the end:

```
=== Run Statistics ===
Events: 1,247
Errors: 2
Warnings: 5
Tasks completed: 8
Validations passed: 3
Duration: 4m 32s
```

With `--no-stats`, this is suppressed. Useful for:

- JSON output mode (stats would break parsing)
- Scripted execution where you don't care
- Minimalist aesthetic preferences

---

## Advanced Switches: The Power User Tools

---

## Operating Modes: Local vs Team

Felix runs in one of two modes depending on `sync.enabled` in `.felix/config.json`.

### Local Mode (default)

No server required. Everything runs from local files.

- Work selection reads `requirements.json` directly
- `in_progress` requirements resume first, then `planned`, sorted by ID
- Dependencies (`depends_on`) read from `specs/*.meta.json` sidecars or inline in `requirements.json`
- No network calls during the agent loop

```json
{
  "sync": {
    "enabled": false
  }
}
```

### Remote / Team Mode

Requires a running Felix backend. Enables server-side work allocation so multiple agents can collaborate on the same project without stepping on each other.

```json
{
  "sync": {
    "enabled": true,
    "base_url": "http://localhost:8080",
    "api_key": "fsk_..."
  }
}
```

**How work allocation works:**

1. `felix loop` calls `GET /api/sync/work/next` instead of scanning `requirements.json`
2. Server uses `FOR UPDATE SKIP LOCKED` to atomically assign a requirement to one agent
3. Returns 204 when nothing is available — loop idles and retries
4. If the agent is blocked (exit code 2 or 3), it calls `POST /api/sync/work/release` to return the requirement to the queue for another agent

**Typical remote mode workflow:**

```bash
# 1. Pull latest specs and metadata from server
felix spec pull

# 2. Start the autonomous loop (uses server work allocation)
felix loop

# Terminal 2 — second agent works in parallel on different requirements
felix loop
```

**Environment variable overrides** (useful for CI/CD):

```powershell
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL     = "https://felix.company.com"
$env:FELIX_SYNC_KEY     = "fsk_prod_key_here"
felix loop
```

---

## Advanced Switches: The Power User Tools

### `--sync` - Push Artifacts to Backend Server

**Usage:**

```bash
felix run S-0001 --sync
felix loop --sync
```

**What it does:** Enables artifact mirroring to a remote backend for this run only, overriding the `sync.enabled` setting in `.felix/config.json`.

**Why temporary override?**

- You normally run locally without sync (faster, no network dependency)
- But for important requirements you want artifacts backed up
- Or you're showing progress to stakeholders who don't have local access

**What gets synced:**

- Agent registration (hostname, platform, version)
- Run creation (requirement ID, start time)
- Events (full NDJSON stream)
- Output files (logs, diffs, reports)
- Run completion (status, exit code)

**Architecture:**

```
CLI Agent → Writes locally to runs/ → Queues to .felix/outbox/*.jsonl
                                   → Background sync uploads to backend
                                   → Retry on failure (exponential backoff)
```

**Sync failure handling:**

- Non-blocking: Agent continues even if sync fails
- Queued: Failed uploads retry later when backend comes back
- Eventual consistency: All artifacts eventually reach the backend
- SHA256 checksums: Duplicate uploads are skipped

**Configuration hierarchy:**

1. `--sync` flag (highest priority - this run only)
2. `$env:FELIX_SYNC_ENABLED` environment variable
3. `.felix/config.json` sync.enabled setting (persistent)

**Pro tip:** Set up sync for production/staging environments but disable for local dev:

```powershell
# Production deployment
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "https://felix.company.com"
$env:FELIX_SYNC_KEY = "fsk_prod_key_here"
felix loop
```

```powershell
# Local development (no sync)
felix run S-0001
```

**Troubleshooting:** If sync isn't working, check `.felix/outbox/` for queued files. If you see hundreds of `*.jsonl` files, the agent couldn't reach the backend. Clean them up or let them retry when the network recovers.

### `--quick` - Speed Through Interactive Prompts

**Usage:**

```bash
felix spec create "Add user authentication" --quick
```

**What it skips:**

- Detailed description prompts
- Dependency questions
- Status selection (defaults to "planned")
- Acceptance criteria generation

**What you get:**

- Spec file with title only
- Minimal frontmatter
- Ready to edit manually

**When to use it:**

- You know exactly what you want
- You'll flesh out details later
- You have 20 small requirements to batch-create

**Time savings:** Interactive mode: ~2-3 minutes per spec. Quick mode: ~5 seconds.

### `--no-commit` - Disable Git Commits (Testing Mode)

**Usage:**

```bash
felix run S-0001 --no-commit
```

**What it does:** Agent makes all code changes but skips `git commit` at the end.

**When to use it:**

- Testing a new spec for the first time
- Prototyping agent behavior
- You want to review changes before committing

**Why this exists:** Early on, we'd test a spec and Felix would commit broken code with a message like "Implement feature X [Claude]". Then we'd have to `git reset --hard` and lose the changes. `--no-commit` lets you see what the agent did before deciding to keep it.

**Pro tip:** Combine with `--format plain` for testing:

```bash
felix run S-0001 --no-commit --format plain | tee test-output.log
```

Review changes, then either commit manually or discard:

```bash
# Keep it
git add -A
git commit -m "Implement S-0001 (manually verified)"

# Discard it
git reset --hard
```

---

## The Exit Code Contract: What They Mean

Felix uses exit codes to communicate status in scripts/CI:

| Code | Meaning                | What to Do                                              |
| ---- | ---------------------- | ------------------------------------------------------- |
| `0`  | Success                | Requirement complete, tests pass, validated             |
| `1`  | Error                  | Agent crashed, unexpected failure, infrastructure issue |
| `2`  | Blocked (Backpressure) | Tests failed 3 times, agent gave up                     |
| `3`  | Blocked (Validation)   | Acceptance criteria failed 2 times                      |
| `5`  | No Work Available      | Nothing planned — used by `felix run-next`; safe in CI  |

**Why this matters for automation:**

```powershell
felix run S-0042
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    # Success - deploy to staging
    deploy-to-staging
}
elseif ($exitCode -eq 2 -or $exitCode -eq 3) {
    # Blocked - manual intervention needed
    send-slack-notification "S-0042 blocked, needs attention"
}
else {
    # Error - retry later
    schedule-retry
}
```

**Unblocking requirements:**

When Felix exits with code 2 or 3, it marks the requirement as "blocked" in `.felix/requirements.json`. To unblock:

1. Fix the underlying issue (broken tests, wrong acceptance criteria)
2. Edit `.felix/requirements.json` and change status from `"blocked"` to `"planned"`
3. Run Felix again - it will pick up the unblocked requirement

**Common causes:**

- Exit 2: Flaky tests, missing test data, environment issues
- Exit 3: Vague acceptance criteria, feature genuinely incomplete

---

## Lessons Learned: Bugs, Pitfalls, and War Stories

### The Case of the Stale Lock File

**Symptom:** Felix refuses to start with "Another process is running."

**Cause:** Agent crashed mid-run and left a `.felix/run.lock` file.

**Solution:** Check for stale processes first:

```powershell
felix procs list
```

If nothing running:

```powershell
Remove-Item .felix/run.lock
```

**Prevention:** Felix now detects stale locks (PID no longer exists) and cleans them automatically. But if you `kill -9` the process, you might still hit this.

### The ProcessStartInfo Inheritance Bug

**The Bug:** Added `--sync` flag, but environment variable wasn't reaching the subprocess.

**Root cause:**

```csharp
var startInfo = new ProcessStartInfo("pwsh", args);
// Looks like environment is inherited, right?
startInfo.Environment["FELIX_SYNC_ENABLED"] = "true";
// WRONG: Default environment is EMPTY, not inherited!
```

**The fix:**

```csharp
// Must COPY parent environment first
foreach (DictionaryEntry env in Environment.GetEnvironmentVariables()) {
    startInfo.Environment[env.Key.ToString()] = env.Value.ToString();
}
// NOW we can add our variable
startInfo.Environment["FELIX_SYNC_ENABLED"] = "true";
```

**Lesson:** Always check subprocess default behavior. "Inherited" doesn't mean what you think.

### The Arrow Character Encoding Disaster

**The Bug:** Console output showed `â€"` instead of `→` on some systems.

**Root cause:** UTF-8 string written to console configured for ASCII or Windows-1252.

**The fix:**

```powershell
# Must be in this exact order for Windows PowerShell 5.1
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
```

**Pragmatic solution:** Changed `→` to `->` in output messages. Not pretty, but works everywhere.

**Lesson:** Unicode support in terminal apps is a minefield. ASCII-safe characters or emojis (which Windows handles better for some reason) are safer than fancy arrows.

### The Path Shadowing Mystery

**The Bug:** CLI agents registered successfully, but database showed NULL for metadata fields.

**Debugged for hours:** API returned 200 OK, database schema was correct, payload looked valid.

**Smoking gun:** Both `routers/agents.py` and `routers/sync.py` defined `/api/agents/register`.

**FastAPI behavior:** Registers routes in order. First definition wins. Later definitions silently ignored.

**What happened:**

1. `sync.router` registered first with `/api/agents/register` (simple upsert)
2. `agents.router` registered second with same path (full auth, metadata handling)
3. CLI called `/api/agents/register` → routed to sync endpoint (no metadata support)
4. No error because the endpoint exists, just wrong implementation

**The fix:** Removed redundant endpoint, unified on single authenticated route.

**Lesson:** Name your endpoints uniquely or review route registration carefully. FastAPI won't warn about shadowing.

### The UUID Type Mismatch Saga

**The Bug:** Agent registration worked, then crashed on exit: "Cannot convert int to UUID."

**Original design:** Agent IDs were integers (0, 1, 2, 3).

**Database migration:** Changed agents.id column to UUID for scalability.

**Migration script:** Updated `.felix/agents.json` to use UUIDs.

**What we forgot:** 20+ PowerShell functions had `[int]$AgentId` parameters.

**The cascade:**

1. Load config: agent_id is now string "39535ce5-..."
2. PowerShell sees `[int]$AgentId` → tries to cast string to int → fails silently, uses $null
3. Agent runs successfully (default fallback mechanisms)
4. Exit handler tries to unregister: `Unregister-Agent -AgentId $null`
5. Backend: "uuid field cannot be null" → 500 error → crash

**The fix:** Changed every `[int]$AgentId` to `[string]$AgentId` across 5 files.

**Lesson:** When changing a core data type, grep the entire codebase for type hints. PowerShell's lenient casting can hide bugs until production.

### The Infinite Spec-Build Loop

**The Bug:** User runs `felix spec create`, agent generates criteria, saves file, detects changes, asks "want to commit?", user says yes, agent commits, then asks again, loops forever.

**Root cause:** Agent was detecting its own git commit as "new changes" and re-entering the commit flow.

**The fix:** Track last known git state, only prompt if working tree is dirty AND different from last check.

**Lesson:** State machines need memory. "Are there changes?" depends on "compared to when?"

### The 422 Validation Error Mystery

**The Bug:** Sync registration returned 422 Unprocessable Entity with cryptic message.

**Payload looked fine:** All required fields present, types correct.

**FastAPI validation error detail:**

```json
{
  "detail": [
    {
      "loc": ["body", "name"],
      "msg": "field required",
      "type": "value_error.missing"
    }
  ]
}
```

**What?** We were sending `agent_id` and `hostname`, not checking `name`.

**The fix:** Backend model expected optional `name` field, but validation middleware required it. Made it truly optional with default.

**Lesson:** FastAPI validation errors are your friend. Read them carefully. `"loc"` tells you exactly which field failed.

---

## Best Practices: How Good Engineers Use Felix

### 1. Write Testable Acceptance Criteria

**Bad:**

```markdown
- [ ] User authentication works
```

**Good:**

```markdown
- [ ] Login endpoint responds: `curl -X POST http://localhost:3000/api/auth/login -d '{"username":"test","password":"test"}' -H "Content-Type: application/json"` (status 200)
- [ ] Invalid credentials rejected: `curl -X POST http://localhost:3000/api/auth/login -d '{"username":"test","password":"wrong"}' -H "Content-Type: application/json"` (status 401)
- [ ] Auth tests pass: `pytest tests/test_auth.py` (exit code 0)
```

### 2. Start Small, Iterate

**Don't:**

```bash
# Write 50 requirements
# Run felix loop
# Go on vacation
# Come back to 47 failures
```

**Do:**

```bash
# Write 3 requirements
# Run felix run S-0001
# Verify it works
# Adjust your spec style based on what worked
# Write 5 more requirements
# Run felix loop --max-iterations 5
# Verify those work
# Now scale up
```

### 3. Use Quick Mode for Batch Creation

When you have a mental model of 20 small requirements:

```powershell
# Create them all with --quick
felix spec create "Add user login" --quick
felix spec create "Add password reset" --quick
felix spec create "Add email verification" --quick
# ... 17 more ...

# Go back and flesh out details for complex ones
felix spec fix S-0042
felix spec fix S-0051
```

### 4. Monitor Long-Running Loops

Don't just fire and forget:

```powershell
# Terminal 1: Run the loop
felix loop --sync

# Terminal 2: Watch progress
watch -n 30 'felix status'

# Terminal 3: Check for blockages
felix deps --incomplete
```

### 5. Use Sync Strategically

**Local dev:** No sync (fast, no network dependency)

```bash
felix run S-0001
```

**Integration environment:** Sync for troubleshooting

```bash
felix run S-0001 --sync
```

**Production automation:** Always sync

```powershell
$env:FELIX_SYNC_ENABLED = "true"
felix loop
```

### 6. Version Your Agents.json

Track agent configuration changes in git:

```bash
git add .felix/agents.json
git commit -m "Switch default agent to claude for better reasoning"
```

Why? When a requirement fails, you want to know which agent ran it and with what configuration.

### 7. Archive Old Runs

Run artifacts accumulate fast:

```
runs/
  2026-02-01T10-30-00/
  2026-02-01T11-15-22/
  2026-02-01T14-45-10/
  ... 500 more ...
```

Periodically archive:

```powershell
# Move runs older than 30 days to archive
$cutoff = (Get-Date).AddDays(-30)
Get-ChildItem runs/* | Where-Object { $_.CreationTime -lt $cutoff } | Move-Item -Destination archive/runs/
```

### 8. Test Acceptance Criteria Manually First

Before letting the agent work on a requirement:

```bash
# Run the validation commands yourself
python main.py  # Does it start?
curl http://localhost:3000/health  # Does the endpoint work?
pytest tests/  # Do the tests pass?

# If any fail, your criteria are wrong
felix validate S-0042  # Confirm with the validator
```

---

## Common Workflows

### The "Sprint Planning" Workflow

**Monday morning:**

```bash
# Review what's ready
felix list --status planned

# Check dependencies
felix deps --tree

# Start the first batch
felix run S-0042
felix run S-0043
felix run S-0044
```

### The "Continuous Integration" Workflow

**CI/CD pipeline:**

```yaml
# .github/workflows/felix.yml
- name: Run Felix requirements
  run: |
    felix loop --max-iterations 10 --format json --sync
  env:
    FELIX_SYNC_ENABLED: "true"
    FELIX_SYNC_URL: ${{ secrets.FELIX_BACKEND_URL }}
    FELIX_SYNC_KEY: ${{ secrets.FELIX_API_KEY }}
```

### The "Overnight Batch" Workflow

**Before leaving Friday:**

```bash
# Start loop in background
nohup felix loop --sync > felix-loop.log 2>&1 &

# Check progress Monday morning
felix status
grep -i error felix-loop.log
felix list --status blocked
```

### The "Emergency Fix" Workflow

**Production is down, need quick fix:**

```bash
# Create requirement
felix spec create "Fix authentication timeout issue" --quick

# Edit spec with exact criteria
code specs/S-0078.md

# Run focused execution, no distractions
felix run S-0078 --format plain --no-stats

# Verify fix
felix validate S-0078

# Deploy
git push
```

---

## Debugging Guide: When Things Go Wrong

### Felix Won't Start

**Error:** "Another process is running"

**Check:**

```bash
felix procs list
```

**Fix if stale:**

```bash
Remove-Item .felix/run.lock
```

### Agent Loops Forever

**Check:**

```bash
# See what it's doing
felix status S-0042 --format json | jq .current_iteration

# If iteration count keeps growing...
felix procs kill <session-id>
```

**Common causes:**

- Vague acceptance criteria that are never satisfied
- Flaky tests that sometimes pass/fail
- Agent making changes that break tests in a cycle

### Sync Not Working

**Symptoms:** No artifacts appear in backend

**Check local queue:**

```powershell
Get-ChildItem .felix\outbox\*.jsonl | Measure-Object
```

**If empty:** Sync disabled or failing silently

**If hundreds:** Network issue or backend down

**Test backend connectivity:**

```powershell
curl http://localhost:8080/health
```

**Enable debug logging:**

```powershell
felix run S-0001 --sync --verbose 2>&1 | Select-String -Pattern "sync"
```

### Validation Fails But Looks Correct

**Problem:** Acceptance criteria look right, but validation fails

**Debug:**

```bash
# Run validation with verbose output
felix validate S-0042 --verbose

# Manually run the failing command
python main.py  # Does it actually work?

# Check for environmental issues
echo $PATH
which python
python --version
```

**Common gotchas:**

- Wrong Python version
- Missing environment variables
- Database not running
- Port already in use

---

## Putting It All Together: A Real Example

Let's implement a complete feature using Felix:

```bash
# 1. Create the requirement
felix spec create "Add rate limiting to API endpoints"

# 2. Review auto-generated spec
code specs/S-0042.md

# 3. Flesh out acceptance criteria with agent help
felix spec fix S-0042
# Agent asks questions, generates detailed criteria

# 4. Check dependencies (might need auth requirement first)
felix deps S-0042 --check

# 5. Run focused execution
felix run S-0042 --sync

# 6. Check results
felix status S-0042

# 7. If blocked, investigate
felix validate S-0042
cat runs/*/output.log | grep -i error

# 8. Fix issues and retry
felix run S-0042

# 9. When complete, verify in staging
felix list --status complete
```

---

## Going Deeper

The `tuts/` directory contains architecture deep dives written alongside the codebase:

| File                                                          | Description                                                                                         |
| ------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| [tuts/FELIX_EXPLAINED.md](../tuts/FELIX_EXPLAINED.md)         | Accessible intro — the "tiny brain, big clipboard" mental model, full architecture tour             |
| [tuts/EXECUTION_FLOW.md](../tuts/EXECUTION_FLOW.md)           | Detailed execution flow with Mermaid diagram — planning mode guardrails, backpressure, git snapshot |
| tuts/RALPH*EXPLAINED.md *(Coming soon)\_                      | Why the loop design works — context pollution problem, 3-phase model, backpressure rationale        |
| [tuts/MULTI_AGENT_SUPPORT.md](../tuts/MULTI_AGENT_SUPPORT.md) | Full adapter pattern docs for all 4 LLM profiles                                                    |
| [tuts/SWITCHING_AGENTS.md](../tuts/SWITCHING_AGENTS.md)       | Step-by-step agent switching guide                                                                  |
| [tuts/sync/README.md](../tuts/sync/README.md)                 | 9-chapter sync system deep dive — outbox pattern, plugin internals, production ops                  |

---

## Conclusion: The Felix Philosophy

Felix is different from traditional tools because it's designed for **iterative autonomous execution** rather than one-shot commands. The switches and options reflect this:

- **`--sync`** exists because long-running agents need observability
- **`--quick`** exists because batch creation matters at scale
- **`--no-commit`** exists because testing agents is different from trusting them
- **Exit codes** communicate more than pass/fail; they tell you WHY it failed

The best way to learn Felix is to use it on a real project. Start with one simple requirement, watch what the agent does, adjust your specs based on what works, then scale up.

Remember: Felix is a junior developer. Give it clear instructions, testable criteria, and guard rails (backpressure tests), and it will happily churn through work while you focus on architecture and design.

Happy automating! 🚀
