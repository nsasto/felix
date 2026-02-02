<div align="center">
    <img src="img/github-header-image.png" alt="Felix" />
</div>
<br><br>

# Felix

Felix is a plan-driven executor for Ralph-style autonomous software delivery. It turns Ralph from "a loop you run" into an operable system with durable state, explicit modes, and a clean separation between planning and doing.

Ralph's core insight is naive persistence: restart the agent in a simple outer loop so every iteration gets fresh context, while progress is kept on disk and validated by backpressure like tests, typechecks, and builds.¹ Felix keeps that philosophy, but moves the discipline from "best effort prompt compliance" into enforceable runtime scaffolding.

---

## Quick Start

```bash
# Clone and navigate to project
git clone https://github.com/yourusername/felix.git
cd felix

# Start backend (in one terminal)
python app/backend/main.py

# Start frontend (in another terminal)
cd app/frontend
npm install
npm run dev

# Run agent on your project
.\felix-agent.ps1 path\to\your\project
```

📘 **[Complete setup guide →](HOW_TO_USE.md)**

---

## Core Concepts

Felix implements Ralph as a production system with four key principles:

- **🎯 Plan-driven execution**: Explicit planning → building phases with enforced boundaries
- **✅ Backpressure validation**: Tests, builds, and lints gate all progress (non-negotiable)
- **📁 Artifact-based state**: Durable files carry memory, not chat transcripts
- **🤖 Autonomous by default**: Runs to completion without human intervention

**The Golden Rule**: Spec files (`specs/*.md`) are test suites (run forever), Plan files (`runs/*/plan-*.md`) are to-do lists (check off once). See [Artifacts](tuts/FELIX_EXPLAINED.md) for details.

---

## How It Works

```
Requirements → Planning Mode → Building Mode → Validation → Complete
     ↓              ↓                ↓              ↓           ↓
  specs/*.md    plan-*.md      git commits    tests pass   status:done
```

Felix follows the **Ralph Playbook funnel**: Define requirements, generate plans, iterate one task per loop until done.²

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
├── felix/                          # Felix configuration & state
│   ├── requirements.json          # Requirement registry with status
│   ├── config.json                # Executor configuration
│   ├── agents.json                # Agent profiles (S-0020)
│   ├── state.json                 # Current execution state
│   └── prompts/                   # Mode-specific LLM prompts
│       ├── planning.md
│       └── building.md
│
├── runs/                           # Per-iteration execution evidence
│   └── 2026-01-27T14-30-00/       # Run directory (timestamp)
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

Felix consists of three independent components:

```
┌─────────────────────────────────────────────────────┐
│  Frontend (React)                                   │
│  • Observes project state                           │
│  • Edits artifacts                                  │
│  • Spawns agents                                    │
│  • Monitors runs                                    │
└──────────────────┬──────────────────────────────────┘
                   │ HTTP/WebSocket
┌──────────────────▼──────────────────────────────────┐
│  Backend (FastAPI)                                  │
│  • Spawns agent processes                           │
│  • Monitors via filesystem watchers                 │
│  • Provides API for UI                              │
│  • WebSocket updates                                │
└──────────────────┬──────────────────────────────────┘
                   │ subprocess + filesystem
┌──────────────────▼──────────────────────────────────┐
│  Agent (PowerShell)                                 │
│  • Runs Ralph loop                                  │
│  • Reads/writes artifacts                           │
│  • Calls LLM APIs                                   │
│  • Executes code changes                            │
│  • Runs tests                                       │
│  • Independent process per project                  │
└─────────────────────────────────────────────────────┘
```

**Key Design**: Agents communicate with backend only via filesystem. No IPC, sockets, or shared memory. This keeps agents simple and enables remote execution.

---

## Felix vs Other Ralph Implementations

| Feature               | Felix                       | snarktank/ralph³   | ralph-orchestrator⁴    | Gas Town⁵         |
| --------------------- | --------------------------- | ------------------ | ---------------------- | ----------------- |
| **Mode enforcement**  | Runtime (planning/building) | Prompt-based       | Orchestrated roles     | Workspace-based   |
| **State persistence** | Structured artifacts        | git + progress.txt | Framework state        | Workspace files   |
| **Multi-agent**       | Single (multi-capable)      | Single loop        | Orchestrated           | Native parallel   |
| **UI decoupling**     | Detached observer           | None               | Integrated             | Integrated        |
| **Complexity**        | Minimal executor            | Minimal script     | Feature-rich framework | Workspace manager |

**Felix positioning**: Deterministic, artifact-driven execution layer that implements the Ralph Playbook² as enforceable system behavior, not prompt suggestions.

📖 **[Detailed comparison →](tuts/RALPH_EXPLAINED.md)**

---

## Design Principles

### Deterministic Setup

Each iteration starts from known state by loading canonical artifacts, not conversational transcripts.¹

### One Task Per Iteration

A loop iteration is an atomic unit of progress ending with explicit outcome and usually a commit.¹

### Backpressure is Non-Negotiable

Tests, builds, typechecks, and lints are the steering mechanism, not optional polish.¹

### Keep AGENTS Operational

`AGENTS.md` is not a diary. Status and planning belong in the plan.¹

### The Plan is Disposable

If the plan is stale, wrong, or cluttered, regenerate. Cheaper than letting the loop drift.¹

### "Don't Assume Not Implemented"

Bias toward searching and confirming existing functionality to avoid duplication and regressions.¹

📐 Design patterns in depth → _(Coming soon)_

---

## Exit Codes

- **0** - Success: requirement complete and validated
- **1** - Error: general execution failure (droid errors, file I/O issues)
- **2** - Blocked: backpressure failures exceeded max retries (default: 3 attempts)
- **3** - Blocked: validation failures exceeded max retries (default: 2 attempts)

Blocked requirements must be manually reset to "planned" status in `felix/requirements.json` after fixing underlying issues.

---

## Documentation

### Getting Started

- 📘 **[Installation & Setup](HOW_TO_USE.md)** - First time setup, running your first agent
- 🎓 **[Ralph Philosophy](tuts/RALPH_EXPLAINED.md)** - The Ralph Playbook, why it works, comparisons

### Technical Reference

- 📊 **[Execution Flow](tuts/EXECUTION_FLOW.md)** - Detailed flow diagram, phase descriptions, exit codes
- 📚 **[Artifacts](tuts/FELIX_EXPLAINED.md)** - Durable memory, plans, and artifact lifecycle
- 🔧 **[Agent Configuration](tuts/AGENT_CONFIG_EXPLAINED.md)** - Agent profiles, registration, runtime management

### Advanced

- 📐 Design Patterns _(Coming soon)_ - Principles with examples, common patterns
- 🔌 API Reference _(Coming soon)_ - Backend API, WebSocket events

---

## Glossary

- **Iteration**: One fresh context run producing one task outcome¹
- **Backpressure**: Validation gates that force self-correction¹
- **Artifacts**: Durable files that carry memory between iterations¹
- **Planning mode**: Update the plan only, no implementation²
- **Building mode**: Implement one prioritized plan item, validate, commit²

---

## References

1. [The Ralph Playbook][1] by Clayton Farr - Core philosophy and patterns
2. [snarktank/ralph][2] - Ralph Playbook reference implementation
3. [snarktank/ralph][3] - Autonomous PRD-driven loop (TypeScript)
4. [mikeyobrien/ralph-orchestrator][4] - Orchestration framework variant
5. [steveyegge/gastown][5] - Multi-agent workspace manager for Claude Code
6. [Claude Code Ralph Wiggum][6] - Official Anthropic plugin implementation

[1]: https://github.com/ClaytonFarr/ralph-playbook "The Ralph Playbook by Clayton Farr"
[2]: https://github.com/snarktank/ralph "snarktank/ralph - Ralph Playbook reference implementation"
[3]: https://github.com/snarktank/ralph "snarktank/ralph - Autonomous PRD-driven loop implementation"
[4]: https://github.com/mikeyobrien/ralph-orchestrator "mikeyobrien/ralph-orchestrator - Orchestration framework variant"
[5]: https://github.com/steveyegge/gastown "steveyegge/gastown - Multi-agent workspace manager for Claude Code"
[6]: https://github.com/anthropics/anthropic-quickstarts/tree/main/claude-code-ralph-wiggum "Claude Code Ralph Wiggum plugin"

---

## Phase -1: Legacy Code Cleanup (Complete)

As of v0.1-cleanup-complete, Felix has undergone Phase -1 cleanup in preparation for cloud migration:

- **Removed**: File-based WebSocket infrastructure, frontend polling mechanisms
- **Preserved**: Console streaming (SSE), agent spawn/stop, project management
- **Status**: Backend returns stubbed data for agent registry and requirements until Phase 0 database implementation

For details, see [Enhancements/PHASE_MINUS_ONE_COMPLETE.md](Enhancements/PHASE_MINUS_ONE_COMPLETE.md).

---

## Contributing

Felix is under active development. Contributions welcome via issues and pull requests.

## License

[Your license here]
