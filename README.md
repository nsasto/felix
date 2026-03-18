<div align="center">
    <img src="img/github-header-image.png" alt="Felix" />
</div><br>

[![Tests](https://github.com/nsasto/felix/actions/workflows/tests.yml/badge.svg)](https://github.com/nsasto/felix/actions/workflows/tests.yml)
[![Latest Release](https://img.shields.io/github/v/release/nsasto/felix?label=latest)](https://github.com/nsasto/felix/releases/latest)
[![Cloud](https://img.shields.io/badge/cloud-runfelix.io-blue)](https://runfelix.io)

# Felix

Felix is an agent harness that lets teams run autonomous coding loops against real, existing codebases - and keep quality high while doing it. Most toy examples fall apart the moment you point them at a production repo. Felix doesn't, because it treats tests, type-checks, and builds as hard gates, not suggestions.

The trick is simple: run the agent in a loop, restart it every iteration so it gets fresh context, and keep all progress on disk. If the tests fail, the loop pushes back. If they pass, the agent moves on. No magic - just structured scaffolding, durable state, and backpressure that actually works.

**Optional cloud sync**: Mirror run artifacts to [runfelix.io](https://runfelix.io) for team visibility, multi-agent coordination, and real-time monitoring.

---

## Setup

### 1. Install the CLI

**Windows installer:**

Download [felix-latest-setup.exe](https://github.com/nsasto/felix/releases/latest/download/felix-latest-setup.exe) and run it. This adds `felix` to your PATH.

After installation, update in place from the CLI on Windows, Linux, or macOS:

```powershell
felix update
```

Check for a newer release without installing it:

```powershell
felix update --check
```

Skip the confirmation prompt during automation:

```powershell
felix update --yes
```

`felix update` resolves the latest GitHub Release, selects the correct platform package, verifies checksums, and stages the replacement after the current process exits.

**Or install from source (any platform):**

```powershell
git clone https://github.com/nsasto/felix.git
cd felix
.\scripts\install.ps1
```

Use `felix install` or the installer to bootstrap a machine. Use `felix update` when you already have Felix installed and want to move to the latest published release.

### 2. Set up your project

Navigate to any existing codebase and run:

```powershell
cd C:\your\project
felix setup
```

The setup wizard walks you through:

- **Scaffolding** - creates `.felix/`, `specs/`, and `runs/` directories
- **Agent profile setup** - configure one or more agent profiles in `.felix/agents.json`
- **Active agent selection** - choose which configured profile is active in `.felix/config.json`
- **Test command** - configure your backpressure command (`pytest`, `npm test`, etc.)
- **Mode** - local (standalone) or remote (team sync via [runfelix.io](https://runfelix.io))

If exactly one agent profile is configured, setup auto-selects it and skips the chooser. Setup is idempotent - safe to re-run without overwriting existing config.

### 3. Run

```powershell
# Run agent on a requirement
felix run S-0001

# Or run in continuous loop mode
felix loop

# Launch interactive TUI dashboard
felix tui

# View active agent sessions
felix procs
```

**Optional: Enable cloud sync for run artifacts (free)**

Mirror run artifacts to the cloud for team visibility. Sign up at [runfelix.io](https://runfelix.io) - it's free. Then set env vars or add to `.felix/config.json`:

```powershell
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "https://runfelix.io"
$env:FELIX_SYNC_KEY = "fsk_your_api_key_here"  # Generate in Settings → API Keys
```

Or use the `--sync` flag for a single run: `felix run S-0001 --sync`

See **docs/SYNC_OPERATIONS.md** for full configuration, troubleshooting, and architecture.

---

## Core Concepts

- **🎯 Plan-driven execution**: Explicit planning → building phases with enforced boundaries
- **✅ Backpressure validation**: Tests, builds, and lints gate all progress (non-negotiable)
- **📁 Artifact-based state**: Durable files carry memory, not chat transcripts
- **🤖 Autonomous by default**: Runs to completion without human intervention
- **🔄 Optional cloud sync**: Mirror artifacts to [runfelix.io](https://runfelix.io) for team coordination

**The Golden Rule**: Spec files (`specs/*.md`) are test suites (run forever), Plan files (`runs/*/plan-*.md`) are to-do lists (check off once). See [Artifacts](tuts/FELIX_EXPLAINED.md) for details.

---

## How It Works

```
Requirements → Planning Mode → Building Mode → Validation → Complete
     ↓              ↓                ↓              ↓           ↓
  specs/*.md    plan-*.md      git commits    tests pass   status:complete
```

Felix follows a simple funnel: define requirements, generate plans, iterate one task per loop until done.

### Execution Flow (High-Level)

1. **Load Context**: Read specs, plan, AGENTS.md, and requirements status
2. **Select Mode**: Planning (no plan exists) or Building (plan exists)
3. **Execute Iteration**: Call LLM with mode-specific constraints
4. **Validate**: Planning has guardrails (no code commits), Building has backpressure (tests must pass)
5. **Update Artifacts**: Write plan updates, commit code, update status
6. **Loop**: Continue until requirement complete or max iterations

**Planning Mode**: Generate/refine plans with self-review loop, then signal `<promise>PLAN_COMPLETE</promise>` to transition.

**Building Mode**: Pick task, implement, validate via backpressure, commit, signal `<promise>TASK_COMPLETE</promise>`, repeat until `<promise>ALL_COMPLETE</promise>`.

📊 **[Detailed execution flow with diagram →](tuts/EXECUTION_FLOW.md)**

---

## Key Files & Structure

```
your-project/
├── specs/                          # Requirements (test suites, not todos)
│   ├── CONTEXT.md                 # Product context, tech stack, standards
│   ├── S-0001-feature-name.md     # Individual requirements
│   └── S-0002-another-feature.md
│
├── .felix/                          # Felix configuration & state
│   ├── requirements.json          # Requirement registry with status
│   ├── config.json                # Executor config (active agent, sync, backpressure)
│   ├── agents.json                # Agent profiles (provider/model presets)
│   ├── sessions.json              # Active Felix processes tracked by `felix procs`
│   ├── state.json                 # Current execution state
│   ├── outbox/                    # Sync queue (when sync enabled)
│   │   └── *.jsonl                # Queued uploads (retry on network failure)
│   ├── sync.log                   # Sync operation log (rotates at 5MB)
│   ├── core/                      # Core modules & interfaces
│   │   └── sync-interface.ps1    # Abstract sync plugin interface
│   ├── plugins/                   # Plugin system (see docs/PLUGINS.md)
│   │   └── sync-http/            # HTTP sync plugin (reference implementation)
│   └── prompts/                   # Mode-specific LLM prompts
│       ├── planning.md
│       └── building.md
│
├── runs/                           # Per-iteration execution evidence
│   └── S-0001-20260224-164140-it7/ # Run directory (requirement + time + iteration)
│       ├── plan-S-0001.md         # Plan snapshot
│       ├── requirement_id.txt     # Which requirement
│       ├── output.log             # LLM output
│       ├── diff.patch             # Git diff
│       └── report.md              # Iteration summary
│
└── AGENTS.md                       # Operational guide (how to run/test)
```

📚 **[Complete artifacts reference →](tuts/FELIX_EXPLAINED.md)**

---

## Architecture

Felix is a CLI-first agent harness. The agent runs as a local process and communicates entirely through the filesystem.

```
┌─────────────────────────────────────────────────────┐
│  Agent (PowerShell)                                 │
│  • Runs plan-execute-validate loop                  │
│  • Reads/writes artifacts to disk                   │
│  • Calls LLM APIs (via droid exec or direct)        │
│  • Executes code changes and runs tests             │
│  • Independent process per project                  │
│  • Optional: Syncs artifacts to cloud via outbox    │
│    - Idempotent SHA256-based deduplication          │
│    - Automatic retry with exponential backoff       │
│    - Network failures don't block agent execution   │
└─────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼ (optional)
   Local Filesystem              runfelix.io Cloud
   specs/, runs/, .felix/        Team dashboard, run
                                 viewer, multi-agent
                                 coordination
```

**Key Design**: All state lives on disk. The agent is a standalone process that reads specs, writes artifacts, and commits code. Cloud sync is opt-in and non-blocking - if the network is down, the agent keeps working.

---

## Viewing Run Artifacts

### Local Runs (Default)

All runs are stored under `runs/<requirement>-<timestamp>-it<iteration>/` with artifacts such as:

- `plan-*.md` - Implementation plan
- `output.log` - Agent execution log
- `diff.patch` - Code changes
- `report.md` - Run summary
- `backpressure.log` - Test/validation results (when backpressure runs)
- `guardrail-violation.md` / `blocked-task.md` - Failure details when an iteration is stopped

### Cloud Dashboard (With Sync Enabled)

When sync is enabled, run artifacts are mirrored to [runfelix.io](https://runfelix.io) where you can:

- Browse runs with status and duration
- View plans, logs, and diffs with markdown rendering
- Track execution events chronologically
- Coordinate multi-agent builds across your team

📊 **[Sync setup & troubleshooting →](docs/SYNC_OPERATIONS.md)**

---

## Comparison

| Feature               | Felix                            | snarktank/ralph    | ralph-orchestrator     | Gas Town          |
| --------------------- | -------------------------------- | ------------------ | ---------------------- | ----------------- |
| **Mode enforcement**  | Runtime (planning/building)      | Prompt-based       | Orchestrated roles     | Workspace-based   |
| **State persistence** | Structured artifacts             | git + progress.txt | Framework state        | Workspace files   |
| **Multi-agent**       | Single (multi-capable)           | Single loop        | Orchestrated           | Native parallel   |
| **Observability**     | Local artifacts + optional cloud | None               | Integrated             | Integrated        |
| **Complexity**        | Minimal executor                 | Minimal script     | Feature-rich framework | Workspace manager |

**Felix positioning**: Deterministic, artifact-driven execution layer. Execution constraints are enforced at runtime, not suggested via prompts. Cloud observability available via optional sync.

---

## Design Principles

### Deterministic Setup

Each iteration starts from known state by loading canonical artifacts, not conversational transcripts.

### One Task Per Iteration

A loop iteration is an atomic unit of progress ending with explicit outcome and usually a commit.

### Backpressure is Non-Negotiable

Tests, builds, typechecks, and lints are the steering mechanism, not optional polish.

### Keep AGENTS Operational

`AGENTS.md` is not a diary. Status and planning belong in the plan.

### The Plan is Disposable

If the plan is stale, wrong, or cluttered, regenerate. Cheaper than letting the loop drift.

### "Don't Assume Not Implemented"

Bias toward searching and confirming existing functionality to avoid duplication and regressions.

---

## Exit Codes

- **0** - Success: requirement complete and validated
- **1** - Error: general execution failure (droid errors, file I/O issues)
- **2** - Blocked: backpressure failures exceeded max retries (default: 3 attempts)
- **3** - Blocked: validation failures exceeded max retries (default: 2 attempts)

Blocked requirements must be manually reset to "planned" status in `.felix/requirements.json` after fixing underlying issues.

---

## Documentation

### Getting Started

- 📘 **[CLI Reference](docs/CLI.md)** - Installation, setup, commands, and usage guide
- 🎓 Philosophy - Origins in the [Ralph Playbook](https://github.com/ClaytonFarr/ralph-playbook), why naive persistence works

### Technical Reference

- 📊 **[Execution Flow](tuts/EXECUTION_FLOW.md)** - Detailed flow diagram, phase descriptions, exit codes
- 📚 **[Artifacts](tuts/FELIX_EXPLAINED.md)** - Durable memory, plans, and artifact lifecycle
- 🤖 **[Switching Agents](tuts/SWITCHING_AGENTS.md)** - Configure profiles, select the active agent, and smoke-test it
- 🧩 **[Writing Plugins](docs/PLUGINS.md)** - Build plugins with lifecycle hooks, state management, examples
- 🔄 **[Sync Operations](docs/SYNC_OPERATIONS.md)** - Cloud sync setup, troubleshooting, architecture
- 📋 **[Features](docs/FEATURES.md)** - Product capabilities and feature list

### Knowledge Base

- 🐚 **[PowerShell Learnings](learnings/POWERSHELL.md)** - Parameter binding, Python interop, scripting gotchas
- 🐍 **[Python Learnings](learnings/PYTHON.md)** - Subprocess deadlocks, pipe buffers, encoding
- 🖥️ **[Platform Learnings](learnings/PLATFORM.md)** - Windows quirks, silent killers, exit codes

---

## Glossary

- **Iteration**: One fresh context run producing one task outcome
- **Backpressure**: Validation gates that force self-correction
- **Artifacts**: Durable files that carry memory between iterations
- **Planning mode**: Update the plan only, no implementation
- **Building mode**: Implement one prioritized plan item, validate, commit

---

## Acknowledgments

Felix's execution model is inspired by the [Ralph Playbook](https://github.com/ClaytonFarr/ralph-playbook) by Clayton Farr - the insight that naive persistence (restart + fresh context + disk-based state) beats complex agent memory. See also [snarktank/ralph](https://github.com/snarktank/ralph), [ralph-orchestrator](https://github.com/mikeyobrien/ralph-orchestrator), [Gas Town](https://github.com/steveyegge/gastown), and [Claude Code Ralph Wiggum](https://github.com/anthropics/anthropic-quickstarts/tree/main/claude-code-ralph-wiggum) for related approaches.

---

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT - see [LICENSE](LICENSE) for details.
