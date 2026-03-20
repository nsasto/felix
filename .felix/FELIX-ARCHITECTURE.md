# Felix .felix/ Architecture

Quick reference for agents and developers. Lists every file in `.felix/` with a one-line description of its role.

---

## Installation Model

Felix supports two deployment modes — both work simultaneously:

| Mode                   | How invoked                                | Engine script location                      | Project root                                                      |
| ---------------------- | ------------------------------------------ | ------------------------------------------- | ----------------------------------------------------------------- |
| **Dev / repo-coupled** | `.\.felix\felix.ps1 run S-0001`            | `$PSScriptRoot` (`.felix/` inside the repo) | Resolve from CWD (.felix/.git) with fallback to current directory |
| **Global install**     | `felix run S-0001` (after `felix install`) | `%LOCALAPPDATA%\Programs\Felix\`            | `Directory.GetCurrentDirectory()` (set by C# runner)              |

The C# runner (`felix.exe`) sets two env vars on every PS subprocess it launches:

| Env Var              | Value set by runner                    | Fallback when absent (direct PS call)                         |
| -------------------- | -------------------------------------- | ------------------------------------------------------------- |
| `FELIX_INSTALL_DIR`  | Path to extracted engine scripts       | `$PSScriptRoot`                                               |
| `FELIX_PROJECT_ROOT` | User's working directory (the project) | Resolve from CWD (.felix/.git), fallback to current directory |

### Root Path Resolution in PS Scripts

```powershell
# felix.ps1
$FelixRoot = if ($env:FELIX_INSTALL_DIR) { $env:FELIX_INSTALL_DIR } else { $PSScriptRoot }
$RepoRoot  = if ($env:FELIX_PROJECT_ROOT) { $env:FELIX_PROJECT_ROOT } else { Resolve-RepoRoot -StartDir (Get-Location).Path }

# felix-agent.ps1
$FelixEngineRoot = if ($env:FELIX_INSTALL_DIR) { $env:FELIX_INSTALL_DIR } else { $PSScriptRoot }
```

All `commands/`, `core/`, `cli/`, and `plugins/` dot-sources use `$FelixRoot` / `$FelixEngineRoot` so they resolve correctly whether Felix is globally installed or run directly from the repo.

### Installing / Upgrading

```powershell
# First install (or upgrade)
felix install

# Force re-extraction even if version matches
felix install --force

# Build + install from source (dev workflow)
.\scripts\install-cli-csharp.ps1
```

Install target: `%LOCALAPPDATA%\Programs\Felix\`. The installer also adds this directory to the user `PATH`.

---

## Entry Points

| File              | Purpose                                                                                                                                                                                                                                                                                                                               |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `felix.ps1`       | CLI dispatcher. Parses the verb (`run`, `list`, `spec`, …) and dot-sources the matching `commands/*.ps1` via `$FelixRoot`. Sets `$RepoRoot` from `FELIX_PROJECT_ROOT` or CWD root detection.                                                                                                                                          |
| `felix-agent.ps1` | Single-requirement executor. Called by `felix.ps1 run`. Loads config, selects one requirement, runs the iteration loop via `core/executor.ps1`. All `core/` dot-sources use `$FelixEngineRoot`.                                                                                                                                       |
| `felix-loop.ps1`  | Multi-requirement loop. Repeatedly calls `felix-agent.ps1` until no `planned`/`in_progress` requirements remain or a limit is reached. Loads `core/work-selector.ps1` to dispatch local vs remote work selection. On exit codes 2/3 (blocked) in remote mode, calls `Send-WorkRelease` to return the requirement to the server queue. |
| `felix-cli.ps1`   | NDJSON event stream consumer. Spawns a felix-agent subprocess, reads its stdout line-by-line and renders events. Dot-sources `cli/renderer.ps1`.                                                                                                                                                                                      |
| `version.txt`     | Version sentinel (e.g. `0.9.0`). Embedded in `felix.exe`; compared against the installed copy to decide whether to re-extract engine scripts on `felix install`.                                                                                                                                                                      |

---

## commands/ — One File Per CLI Verb

Each file exports a single top-level function invoked by `felix.ps1`.

| File           | Function                                                                        | Does                                                                                                                                                                                                          |
| -------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `run.ps1`      | `Invoke-Run`                                                                    | Resolves project path, delegates to `felix-agent.ps1`                                                                                                                                                         |
| `loop.ps1`     | `Invoke-Loop`                                                                   | Resolves project path, delegates to `felix-loop.ps1`                                                                                                                                                          |
| `tui.ps1`      | `Invoke-Tui`                                                                    | Launches the terminal UI frontend                                                                                                                                                                             |
| `status.ps1`   | `Invoke-Status`                                                                 | Prints current requirement status summary                                                                                                                                                                     |
| `list.ps1`     | `Invoke-List`                                                                   | Lists requirements with optional `--status` filter                                                                                                                                                            |
| `validate.ps1` | `Invoke-Validate`                                                               | Runs acceptance/validation checks for a requirement                                                                                                                                                           |
| `deps.ps1`     | `Invoke-Deps`                                                                   | Checks and reports dependency health                                                                                                                                                                          |
| `spec.ps1`     | `Invoke-SpecCreate`, `Invoke-SpecStatus`, `Invoke-SpecFix`, `Invoke-SpecDelete` | Create, view, fix, and delete spec files                                                                                                                                                                      |
| `agent.ps1`    | `Invoke-Agent`                                                                  | Manages agent profiles (list, add, remove, set-default)                                                                                                                                                       |
| `context.ps1`  | `Invoke-Context`                                                                | Regenerates `CONTEXT.md` by analysing the project                                                                                                                                                             |
| `procs.ps1`    | `Invoke-ProcessList`                                                            | Lists active felix agent processes                                                                                                                                                                            |
| `setup.ps1`    | `Invoke-Setup`                                                                  | Scaffolds `.felix/` (`requirements.json`, `state.json`, `config.json`, `.gitignore`) for new projects, then runs the interactive sync / API-key wizard. Scaffold step is a no-op if `.felix/` already exists. |
| `help.ps1`     | `Show-Help`                                                                     | Prints CLI usage                                                                                                                                                                                              |
| `version.ps1`  | `Show-Version`                                                                  | Prints version, repo, and branch info                                                                                                                                                                         |

---

## core/ — Engine Modules

Loaded via dot-source by entry points or each other.

### Orchestration

| File                 | Key Functions                                                                                                                | Role                                                                                                                                     |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `executor.ps1`       | `Invoke-FelixIteration`                                                                                                      | Main iteration driver. Coordinates one plan→build→validate cycle. Dot-sources mode-selector, prompt-builder, agent-runner, task-handler. |
| `mode-selector.ps1`  | `Get-ExecutionMode`                                                                                                          | Decides whether the current iteration should be in Planning or Building mode based on spec and history.                                  |
| `prompt-builder.ps1` | `New-IterationPrompt`                                                                                                        | Assembles the full LLM prompt from spec, context, history, and templates.                                                                |
| `agent-runner.ps1`   | `Invoke-AgentExecution`, `Test-AndEnforcePlanningGuardrails`                                                                 | Streams the LLM CLI subprocess, captures output, enforces planning-mode guardrails.                                                      |
| `task-handler.ps1`   | `Invoke-TaskCompletion`, `Invoke-BackpressureFailure`, `Save-TaskChanges`, `Invoke-CompletionSignals`, `New-IterationReport` | Handles post-LLM actions: marking tasks done, handling backpressure failures, committing state changes.                                  |
| `initialization.ps1` | `Initialize-ExecutionState`                                                                                                  | Loads state, selects the active requirement, registers the agent, sets up the execution environment.                                     |
| `workflow.ps1`       | `Set-WorkflowStage`, `Clear-WorkflowStage`                                                                                   | Writes workflow stage to `state.json` for live UI visualization.                                                                         |

### Agent / LLM

| File                     | Key Functions                      | Role                                                                                                                      |
| ------------------------ | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `agent-adapters.ps1`     | Adapter classes for each LLM       | Adapter pattern over supported LLM CLIs: Droid, Claude, Codex, Gemini, Copilot. Normalises invocation and output parsing. |
| `agent-registration.ps1` | `Register-Agent`, `Send-Heartbeat` | Registers the running agent with the backend API and sends periodic heartbeats. Best-effort; fails silently.              |
| `agent-state.ps1`        | `AgentState` class                 | Formal state machine tracking agent mode and requirement ID through a run.                                                |

### Configuration & State

| File                     | Key Functions                                                  | Role                                                                                       |
| ------------------------ | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `config-loader.ps1`      | `Get-FelixConfig`, `Resolve-AgentConfig`                       | Loads `config.json` and `agents.json`, validates project structure, resolves active agent. |
| `state-manager.ps1`      | `Get-RequirementsState`, `Save-RequirementsState`              | CRUD for `requirements.json`. Single source of truth for requirement status.               |
| `requirements-utils.ps1` | `Update-RequirementStatus`, `Invoke-ValidationScript`          | Updates requirement status/runId in state; invokes PowerShell validation scripts.          |
| `session-manager.ps1`    | `Register-Session`, `Unregister-Session`, `Get-ActiveSessions` | Tracks active agent sessions (in-process registry, used by `procs` command).               |

### I/O & Output

| File             | Key Functions                             | Role                                                                                                                   |
| ---------------- | ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `emit-event.ps1` | `Emit-Event`, `Emit-*` helpers            | All engine console output goes through here as NDJSON events (one JSON object per line). Makes the engine UI-agnostic. |
| `text-utils.ps1` | `Format-PlainText`, `Format-MarkdownText` | Converts markdown to plain text (for git commits) or ANSI-styled terminal output.                                      |

### Git & Validation

| File              | Key Functions                                                   | Role                                                                                                            |
| ----------------- | --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `git-manager.ps1` | `Initialize-FeatureBranch`, `Invoke-GitCommit`, `Get-GitStatus` | All git operations: branch creation, staging, committing, status checks.                                        |
| `guardrails.ps1`  | `Test-PlanningGuardrails`                                       | Enforces constraints during planning mode (e.g., prevents writing to protected paths like `.felix/state.json`). |
| `validator.ps1`   | `Get-BackpressureCommands`, `Invoke-Backpressure`               | Reads and runs backpressure validation commands; returns pass/fail with output.                                 |

### Utilities

| File                  | Key Functions                                  | Role                                                                                                                                                                                                                                                                      |
| --------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `compat-utils.ps1`    | `Coalesce-Value`, `Merge-Hashtable`            | PS 5.1-safe replacements for PS 7+ features (`??`, `?.`, etc.).                                                                                                                                                                                                           |
| `python-utils.ps1`    | `Resolve-PythonExecutable`                     | Resolves `python`/`python3`/`py` with configurable fallbacks.                                                                                                                                                                                                             |
| `context-builder.ps1` | `Invoke-ContextBuilder`                        | Analyses project tree and regenerates `CONTEXT.md`.                                                                                                                                                                                                                       |
| `spec-builder.ps1`    | `Invoke-SpecBuilder`                           | Interactive LLM-driven spec creation conversation.                                                                                                                                                                                                                        |
| `sync-interface.ps1`  | `IRunReporter`, `New-RunReporter`              | Interface + factory for optional run artifact sync to backend (outbox queue pattern).                                                                                                                                                                                     |
| `work-selector.ps1`   | `Get-NextRequirement`, `Send-WorkRelease`      | Dispatches work selection: **local mode** scans `requirements.json`; **remote mode** (`sync.enabled=true`) calls `GET /api/sync/work/next` (FOR UPDATE SKIP LOCKED). `Send-WorkRelease` calls `POST /api/sync/work/release` to return a blocked requirement to the queue. |
| `exit-handler.ps1`    | `Exit-FelixAgent`                              | Graceful agent shutdown: cleanup, final events, exit code propagation.                                                                                                                                                                                                    |
| `plugin-manager.ps1`  | `Initialize-PluginSystem`, `Invoke-PluginHook` | Discovers and invokes plugins at lifecycle hooks with circuit-breaker protection.                                                                                                                                                                                         |

---

## cli/ — Event Renderer

| File           | Key Functions                                                                                                          | Role                                                                                                                             |
| -------------- | ---------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `renderer.ps1` | `Render-Rich`, `Render-Plain`, `Render-Json`, `Update-Stats`, `Show-Stats`, `Should-Display-Event`, `Format-Timestamp` | ANSI colour definitions, per-run stats tracking, and all three render modes for NDJSON events. Dot-sourced into `felix-cli.ps1`. |

---

## plugins/ — Lifecycle Hooks

Each plugin is a subdirectory with `plugin.json` (manifest) and one PS1 per hook.

| Plugin               | Hooks                                                                   | Does                                                                                              |
| -------------------- | ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `sync-http/`         | PreIteration, Event, PostModeSelection, BackpressureFailed, RunComplete | Batches NDJSON events and uploads run artifacts to the backend via HTTP. Outbox queue with retry. |
| `metrics-collector/` | PreIteration, PostLLM, PostIteration                                    | Tracks token usage, latency, and cost per run.                                                    |
| `prompt-enhancer/`   | ContextGathering, PreLLM                                                | Injects additional context into the assembled prompt before LLM submission.                       |
| `slack-notifier/`    | PostLLM, PostValidation, BackpressureFailed                             | Sends Slack messages on key events.                                                               |
| `hook-contracts.ps1` | —                                                                       | Documents the input/output contract for every hook type.                                          |
| `test-harness.ps1`   | —                                                                       | Utility for testing plugins in isolation without a full agent run.                                |

---

## prompts/ — Prompt Templates

Markdown files assembled by `core/prompt-builder.ps1`.

| File                      | Used For                                          |
| ------------------------- | ------------------------------------------------- |
| `planning.md`             | System prompt for planning-mode iterations        |
| `building.md`             | System prompt for building-mode iterations        |
| `build_context.md`        | Project context block injected into build prompts |
| `check-tasks-complete.md` | Prompt asking LLM to assess task completion       |
| `explainer.md`            | Prompt for the `context` command explanation pass |
| `learning.md`             | Standalone learning extraction prompt             |
| `spec_rules.md`           | Rules injected when writing/editing specs         |
| `spec-builder.md`         | System prompt for interactive spec creation       |

---

## policies/ — Agent Guardrails

| File             | Purpose                                                    |
| ---------------- | ---------------------------------------------------------- |
| `allowlist.json` | Paths/patterns the agent is explicitly permitted to modify |
| `denylist.json`  | Paths/patterns the agent is forbidden from modifying       |

---

## Root Config Files

| File                | Purpose                                                                                                                                                                                                 |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `config.json`       | Per-project runtime config: agent, model, sync settings, python executable                                                                                                                              |
| `agents.json`       | Agent profile registry: name, CLI command, model, API key reference                                                                                                                                     |
| `requirements.json` | Slim requirement index: `id, title, spec_path, status, commit_on_complete`. Rich metadata (`priority, tags, depends_on`) lives in per-spec `.meta.json` sidecars (see below). Do not edit during a run. |
| `specs/*.meta.json` | Per-spec sidecar written alongside each `.md` spec. Holds `priority, tags, depends_on, updated_at`. Gitignored in remote/team mode; downloaded via `felix spec pull` from the server.                   |
| `state.json`        | Ephemeral run state for UI visualisation (workflow stage, current agent). Rewritten each iteration.                                                                                                     |

---

## tests/

Pester-style test files for all core modules. Run via `scripts/test-backend.ps1` (which executes `.felix/tests/test-*.ps1`). Each test file mirrors a `core/*.ps1` module and uses `.felix/tests/test-framework.ps1` for assertions.

---

## Remote / Team Mode

When `sync.enabled = true` in `.felix/config.json`, `felix-loop.ps1` uses server-side work allocation instead of scanning `requirements.json` locally.

### Work allocation flow

```
felix-loop.ps1
  └─ core/work-selector.ps1::Get-NextRequirement
       ├─ [sync disabled] Get-NextRequirementLocal  → scan requirements.json
       └─ [sync enabled]  Get-NextRequirementRemote → GET /api/sync/work/next
                                                        (FOR UPDATE SKIP LOCKED)
```

### On block (exit code 2 or 3)

```
felix-loop.ps1 exit code 2/3
  └─ core/work-selector.ps1::Send-WorkRelease → POST /api/sync/work/release
       → resets status = 'planned', assigned_to = NULL
```

### Spec metadata

`requirements.json` is a slim index (`id, title, spec_path, status, commit_on_complete`). Rich metadata is in per-spec `.meta.json` sidecars:

- Written by `spec-builder.ps1` and `commands/spec.ps1 spec fix`
- Served by `GET /api/sync/specs/file` (generated from DB)
- Included in the `POST /api/sync/specs/check` manifest as virtual entries
- Gitignored (`specs/*.meta.json`) in remote mode
- Downloaded by `felix spec pull`

### Environment variable overrides

| Variable             | Purpose                                 |
| -------------------- | --------------------------------------- |
| `FELIX_SYNC_ENABLED` | `"true"` to force remote mode           |
| `FELIX_SYNC_URL`     | Backend base URL (overrides `base_url`) |
| `FELIX_SYNC_KEY`     | API key `fsk_...` (overrides `api_key`) |

---

## Execution Flow (one requirement)

```
felix.ps1 run S-0001
  └─ commands/run.ps1 → Invoke-Run
       └─ felix-agent.ps1
            ├─ core/config-loader.ps1      load config + resolve agent
            ├─ core/initialization.ps1     load state, select requirement
            ├─ core/plugin-manager.ps1     OnPreIteration hooks
            └─ core/executor.ps1 → Invoke-FelixIteration (per iteration)
                 ├─ core/mode-selector.ps1    plan vs build?
                 ├─ core/prompt-builder.ps1   assemble prompt
                 ├─ core/agent-runner.ps1     stream LLM subprocess
                 ├─ core/task-handler.ps1     handle completion / backpressure
                 ├─ core/git-manager.ps1      commit changes
                 ├─ core/validator.ps1        backpressure check
                 └─ core/plugin-manager.ps1   OnPostIteration hooks
```

NDJSON events flow from `core/emit-event.ps1` → agent stdout → `felix-cli.ps1` (supervisor) → `cli/renderer.ps1` (display).
