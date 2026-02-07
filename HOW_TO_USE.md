# How to Use Felix

This guide explains:

- which files Felix expects
- where they live
- how to get started
- how Markdown and JSON work together
- how to run Felix day to day without drift

Felix is intentionally simple. If you understand where the artifacts live and what each iteration does, you understand the system.

---

## Mental model first

Felix runs an **autonomous loop**, not a chat.

Felix continuously iterates until work is complete:

- loads a small set of files each iteration
- runs in either planning or building mode
- produces one concrete outcome
- updates state on disk
- continues to next task

**Felix runs to completion by default.** You start it, it finishes the work, then stops.

All memory lives in files, not conversation state. This means:

- You can stop and resume anytime
- Progress is visible in git commits
- No chat history to maintain
- State is inspectable and recoverable

---

## Repository layout

A Felix enabled repository typically looks like this:

```
.
├── specs/
│   ├── CONTEXT.md
│   ├── auth-email-signin.md
│   ├── billing-invoice-download.md
│   └── ...
│
├── AGENTS.md
│
├── .felix/
│   ├── requirements.json
│   ├── state.json
│   ├── config.json
│   ├── prompts/
│   │   ├── planning.md
│   │   └── building.md
│   └── policies/
│       ├── allowlist.json
│       └── denylist.json
│
├── runs/
│   └── <run-id>/
│       ├── requirement_id.txt
│       ├── plan.snapshot.md
│       ├── commands.log.jsonl
│       ├── diff.patch
│       └── report.md
│
└── app/
    ├── backend/
    └── frontend/
```

Not all of these need to exist on day one, but this is the intended steady state.

---

## Core concepts

Felix separates **content**, **structure**, and **action**.

- Markdown holds **meaning**
- JSON holds **structure and status**
- The plan holds **next actions**

Each has one job.

---

## First-time setup

Before running Felix, set up the development environment:

```powershell
.\scripts\setup-dev-environment.ps1
```

This will:

- Create Python virtual environment in `app/backend/.venv`
- Install all Python dependencies including pytest
- Create `tests/` directory if missing
- Install frontend npm dependencies
- Verify toolchain (Python, Node.js, npm)

You only need to run this once. The test scripts will auto-setup if you skip this step.

## Prerequisites

Recommended tools and minimum versions for a smooth experience on Windows:

- **PowerShell**: PowerShell 7+ (or Windows PowerShell with execution policy set appropriately)
- **Python**: 3.10+
- **Node.js**: 16+ and **npm**
- **Git**: CLI installed and on PATH

If your environment uses a non-standard Python executable, set the path in `.felix/config.json` under the `python.executable` key so scripts like `validate-requirement.py` can be invoked reliably.

### Quick setup (one-liner)

Run the auto-setup which creates a venv and installs dependencies:

```powershell
.\scripts\setup-dev-environment.ps1
```

If the script fails, see the Troubleshooting section below.

### Troubleshooting (Windows)

- If virtualenv creation fails: run PowerShell as Administrator and ensure ExecutionPolicy allows script execution: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`.
- If Node/npm commands fail: ensure Node is installed and restart your shell so PATH updates take effect.
- If ports are already in use (backend/frontend): identify and stop the process or change the port in the respective start command.
- If `py -3` is not present, use `python` or provide the full Python executable path in `.felix/config.json`.

---

## Felix CLI

Felix provides both PowerShell and C# command-line interfaces for all operations.

### Option 1: PowerShell CLI (Original)

You can use Felix CLI directly without installation:

```powershell
# Run from the .felix folder
.\.felix\felix.ps1 run S-0001
.\.felix\felix.ps1 status
.\.felix\felix.ps1 list --status planned
.\.felix\felix.ps1 loop
```

**Optional Installation (Convenience)**

For shorter commands, install to PATH:

```powershell
# Install Felix CLI (adds .felix folder to PATH)
.\scripts\install-cli.ps1

# Restart PowerShell or reload profile
. $PROFILE

# Now use short commands
felix run S-0001
felix version
```

### Option 2: C# CLI (Cross-Platform)

A native C# executable that wraps felix.ps1. Provides identical functionality with better cross-platform support.

**Installation:**

```powershell
# One-time setup: Build and install to PATH
.\scripts\install-cli-csharp.ps1

# Restart terminal to refresh PATH
```

**Usage:**

```powershell
# All commands work identically
Felix.Cli.exe run S-0001
Felix.Cli.exe status
Felix.Cli.exe list --status planned
Felix.Cli.exe dashboard  # Visual status overview

# Short form (if you create an alias)
felix run S-0001
```

**Dashboard Command:**

The C# CLI includes an interactive dashboard:

```powershell
Felix.Cli.exe dashboard
```

Displays:

- FELIX ASCII art banner
- GitHub-style stacked bar chart showing requirement status
- Total requirement count

**Architecture:**

Both CLIs use the same backend:

- `Felix.Cli.exe` → `.felix/felix.ps1` → `scripts/*.ps1`
- All logic lives in PowerShell scripts (single source of truth)
- C# CLI is a thin wrapper with System.CommandLine
- No logic duplication = impossible to drift

⚠️ **Dev-Repo Only**: Current installation works from `C:\dev\Felix` only. CLI calls scripts using relative paths. Future: AppData installation for system-wide use.

### Available Commands

Both CLIs support the same commands:

```powershell
# PowerShell CLI
felix run <req-id>       # Execute a single requirement
felix loop               # Run agent in continuous loop mode
felix status [req-id]    # Show requirement status
felix list               # List all requirements with filters
felix deps <req-id>      # Show dependencies and validate status
felix validate <req-id>  # Run validation checks
felix spec create        # Create a new specification interactively
felix spec fix           # Align specs folder with requirements.json
felix spec delete        # Delete a specification
felix version            # Show version information
felix help [command]     # Show help

# C# CLI (identical functionality)
Felix.Cli.exe run <req-id>
Felix.Cli.exe dashboard   # Bonus: Visual status overview
Felix.Cli.exe list --status planned
# ... (all commands work the same)
```

#### Command Details

**run** - Execute a single requirement to completion

```powershell
felix run S-0001
felix run S-0001 --format json
Felix.Cli.exe run S-0001 --no-stats
```

**loop** - Continuous execution mode (processes all planned requirements)

```powershell
felix loop
felix loop --max-iterations 10
```

**status** - Show requirement status summary or details

```powershell
felix status              # All requirements
felix status S-0001       # Specific requirement
felix status --format json
```

**list** - List requirements with filtering

```powershell
felix list
felix list --status planned
felix list --priority high
felix list --blocked-by S-0001
felix list --with-deps
```

**dashboard** - Visual overview (C# CLI only)

```powershell
Felix.Cli.exe dashboard
# Shows: ASCII banner + GitHub-style status bar + total count
```

#### Dependency Management

Analyze and validate requirement dependencies:

```powershell
# Show dependencies for a requirement
felix deps S-0018

# Check if all dependencies are complete (exit code 0 if yes, 1 if no)
felix deps S-0018 --check

# Show full dependency tree
felix deps S-0018 --tree

# List all requirements with incomplete dependencies
felix deps --incomplete
```

**What it does:**

- **Validates** dependency completion (checks for done/complete status)
- **Detects** missing dependencies (referenced but not in requirements.json)
- **Color-coded output**: Green=complete, Yellow=incomplete, Red=missing
- **Exit codes**: 0 for complete dependencies, 1 for incomplete/missing

**Enhanced list filtering:**

```powershell
# Filter by multiple criteria
felix list --status planned --priority high
felix list --labels backend,api
felix list --blocked-by incomplete-deps

# Show dependencies inline
felix list --with-deps

# Combine filters
felix list --status planned --blocked-by incomplete-deps --with-deps
```

**Enhanced status display:**

```powershell
# Status now shows dependency warnings automatically
felix status S-0018
# Output includes:
#   [WARN] Incomplete dependencies: S-0003 (planned)
#   [ERROR] Missing dependencies: S-9999
```

#### Spec Management

Create, validate, and manage specifications:

```powershell
# Create new spec interactively
felix spec create

# Create with description (AI asks followup questions)
felix spec create "Add user authentication"

# Quick mode - minimal questions, makes assumptions
felix spec create --quick "Add export to CSV feature"
felix spec create -q "Add dark mode toggle"

# Fix alignment between specs/ folder and requirements.json
felix spec fix

# Fix alignment and auto-rename duplicate spec files
felix spec fix --fix-duplicates
felix spec fix -f

# Delete a specification
felix spec delete S-0042
```

#### Spec Builder

Create specifications through an interactive conversation with an AI agent:

```powershell
# Interactive mode - prompts for description
felix spec create

# Direct mode - provide description upfront
felix spec create "Add user authentication"

# Quick mode - minimal questions, makes assumptions
felix spec create --quick "Add export to CSV feature"
felix spec create -q "Add dark mode toggle"
```

**How it works:**

1. **Auto-generates ID**: Finds next available S-NNNN number
2. **AI Conversation**: Agent asks clarifying questions about your feature
3. **Generates Spec**: Creates properly formatted specification following spec_rules.md
4. **Updates Registry**: Adds entry to requirements.json with status "planned"

**Modes:**

- **Normal Mode**: Thorough conversation, asks detailed questions
- **Quick Mode** (`--quick` or `-q`): Max 2 questions, makes reasonable assumptions based on Felix architecture

#### Spec Fix

Synchronize specs folder with requirements.json:

```powershell
# Scan specs/ folder and update requirements.json
felix spec fix

# Also auto-rename duplicate spec files to next available ID
felix spec fix --fix-duplicates
felix spec fix -f
```

**What it does:**

- **Adds** new specs found in specs/ folder to requirements.json
- **Updates** spec_path and title if changed
- **Detects** orphaned entries (in JSON but file missing)
- **Warns** about duplicate IDs (same ID used in multiple files)
- **Fixes** duplicates by renaming to next available ID (with `--fix-duplicates`)
- **Preserves** git history using `git mv` when files are tracked

**Use cases:**

- After manually creating/renaming spec files
- Cleaning up duplicate spec IDs
- Validating repository consistency
- Preparing for commits

#### Spec Delete

Remove a specification and its requirements.json entry:

```powershell
# Delete a spec (prompts for confirmation)
felix spec delete S-0042
```

**What it does:**

- Removes spec file from specs/ folder
- Removes entry from requirements.json
- Prompts for confirmation before deletion

**Output:**

The spec builder emits pure JSON events for programmatic consumption:

- `spec_builder_started` - Conversation begins
- `spec_question` - Agent asks a question
- `prompt_requested` - Waiting for user input via response file
- `spec_draft` - Shows draft for review (if applicable)
- `spec_builder_complete` - Spec written successfully
- `spec_builder_cancelled` - User cancelled

Response files are written to `.felix/prompts/spec_q_N.response.txt` for UI/TUI integration.

### Output Formats

All commands support multiple output formats:

- `--format json` - Machine-readable NDJSON for scripts/APIs
- `--format plain` - Simple colored text for logs
- `--format rich` - Enhanced visuals with progress (default)

```powershell
# JSON output for scripts
felix status --format json | ConvertFrom-Json

# Plain output for logs
felix run S-0001 --format plain > run.log

# Rich output (default)
felix run S-0001
```

### Event Filtering

Filter events by type or log level:

```powershell
# Show only errors and warnings
felix run S-0001 --MinLevel warn

# Suppress statistics
felix run S-0001 --no-stats
```

### Examples

```powershell
# View all planned requirements
felix list --status planned

# Get detailed status for a requirement
felix status S-0001

# Run a requirement with JSON output
felix run S-0001 --format json

# Run loop with max iterations
felix loop --max-iterations 10

# Validate before running
felix validate S-0001
```

**Direct Script Usage**: You can always call the underlying scripts directly:

```powershell
# Direct agent execution (single iteration)
.\.felix\felix-agent.ps1 C:\path\to\project -RequirementId S-0001

# Direct loop execution
.\.felix\felix-loop.ps1 C:\path\to\project
```

The CLI wrapper (`.felix/felix.ps1`) provides a cleaner interface with output formatting, command routing, and argument parsing.

---

## `specs/` – requirements content

This directory contains **requirements**, not plans.

Rules:

- one topic per file
- narrow scope
- no implementation detail
- stable over time
- descriptive filenames (no ID prefix needed)
- ID in first line of file for reference

Good examples:

- `auth-email-signin.md`
- `billing-invoice-download.md`
- `search-filters.md`

Bad examples:

- a single giant PRD
- files that mix requirements and task lists

Example file start:

```markdown
# S-0001: Auth email sign-in

## Narrative

As a user, I want...
```

### `specs/CONTEXT.md`

Special file for product and system context:

- tech stack choices
- design standards
- UX rules and constraints
- architectural invariants

This is **not** operational. Operational details go in `AGENTS.md`.

Felix treats `specs/` as the source of truth for _what should exist_.

### The "Forever" Checkbox

When defining criteria in specs, **leave the checkboxes empty**.

**✅ Do this:**

```markdown
- [ ] Backend is healthy: `curl localhost:8080/health` (status 200)
```

_Felix interprets this as:_ "Every time I do work, I will run this curl command. If it passes, the requirement is healthy."

**❌ Do NOT do this:**

```markdown
- [x] Backend is healthy: `curl localhost:8080/health` (status 200)
```

_Felix interprets this as:_ "This was verified by a human ages ago. Ignored."

**How do I know it's done?**
Look at the **Requirement Status** (in the Kanban or CLI), not the checkboxes in the file.

- **Status: Complete** means "All the unchecked boxes in the spec ran successfully."

---

## `.felix/requirements.json` – structured registry and status

This file is the **central registry** of requirements and work state.

It provides:

- stable IDs
- minimum required structure
- current status
- a place for automation and UI to anchor

It does **not** replace Markdown specs.

### What belongs here

- requirement id and title
- path to spec file
- status (draft, planned, in_progress, complete, blocked)
- priority or labels
- optional dependencies
- timestamps

### What does not belong here

- long descriptions
- examples
- acceptance criteria
- design discussion

Those live in Markdown.

### Minimal recommended schema

```json
{
  "requirements": [
    {
      "id": "S-0001",
      "title": "Auth email sign-in",
      "spec_path": "specs/auth-email-signin.md",
      "status": "planned",
      "priority": "high",
      "labels": ["backend", "security"],
      "depends_on": [],
      "updated_at": "2026-01-24",
      "commit_on_complete": false // optional: override global commit setting
    }
  ]
}
```

Keep this boring and stable. JSON grows painful when it tries to express nuance.

### Requirement properties

**Required fields:**

- **id** - Unique identifier (e.g., S-0001)
- **title** - Brief description
- **spec_path** - Path to the spec file
- **status** - Current state (see status values below)
- **priority** - Importance level (high, medium, low, critical)
- **labels** - Array of tags for categorization
- **depends_on** - Array of requirement IDs that must complete first
- **updated_at** - Last modification date

**Optional fields:**

- **commit_on_complete** - Boolean to override global commit behavior
  - If `true`: creates git commits after each task (even if global setting is `false`)
  - If `false`: skips commits (even if global setting is `true`)
  - If omitted: uses `.felix/config.json` → `executor.commit_on_complete` setting
  - Useful for experimental requirements or when you want finer control

### Requirement status values

- **draft** - Initial state, not ready for work
- **planned** - Ready to be worked on
- **in_progress** - Currently being worked on
- **complete** - Finished and validated
- **blocked** - Cannot proceed due to validation or backpressure failures

### Handling blocked requirements

When a requirement becomes blocked (either from repeated validation failures or backpressure test failures), Felix automatically marks it as "blocked" in `requirements.json` and moves to the next requirement.

**Why requirements get blocked:**

- **Validation failures**: After retrying validation (default: 2 attempts), the requirement is blocked if validation criteria still fail
- **Backpressure failures**: After max retries (default: 3 attempts), the requirement is blocked if tests/lint/build continue to fail

**Unblocking a requirement:**

1. **Diagnose the issue**: Check the run logs in `runs/<run-id>/` and look for validation or backpressure failure messages
2. **Fix the root cause**: Correct the code, tests, or validation criteria as needed
3. **Manually reset status**: Edit `.felix/requirements.json` and change the requirement's status from `"blocked"` to `"planned"`
4. **Restart Felix**: The agent will pick up the unblocked requirement on the next run

Blocked requirements are intentionally manual - this prevents the agent from repeatedly attempting impossible tasks and allows independent requirements to proceed.

---

## Plans – per-requirement focus

### `runs/<run-id>/plan-<req-id>.md` – agent's working plan

This is the **narrow, disposable plan** the agent creates and uses:

- Scoped to a single requirement only
- Created fresh for each requirement during planning mode
- Prioritized bullet list of concrete tasks
- Updated by the agent as work progresses

Rules:

- Disposable and requirement-specific
- Frequently rewritten
- Agent reads and updates only this plan

If the plan becomes cluttered or wrong, the agent regenerates it.

Felix assumes this is cheap.

---

## `AGENTS.md` – how to operate the repo

This file tells Felix **how to run the system**.

Typical contents:

- how to install dependencies
- how to run tests
- how to build or start the app

Rules:

- operational only
- no planning
- no status updates
- no long explanations

If it would not help a new engineer run the repo, it does not belong here.

---

## Prompts

### `.felix/prompts/planning.md`

Planning mode instructions with **iterative refinement**.

Planning mode:

- reads `specs/` and `.felix/requirements.json`
- creates/updates `runs/<run-id>/plan-<req-id>.md` (narrow scope, single requirement)
- **loops with self-review** against 5 criteria:
  - Philosophy alignment (Ralph principles)
  - Tech stack consistency
  - Simplicity (avoid over-engineering)
  - Maintainability
  - Scope appropriateness
- refines the plan across multiple iterations
- signals `<promise>PLAN_COMPLETE</promise>` when satisfied
- may update requirement status
- must not modify source code

Planning is iterative: the agent will generate, review, and simplify until the approach is solid.

### `.felix/prompts/building.md`

Building mode instructions.

Building mode:

- reads plan from `runs/<run-id>/plan-<req-id>.md` (narrow, requirement-specific)
- selects exactly one plan item
- inspects existing code first
- implements one task
- runs backpressure (tests, build, lint)
- commits or reports failure
- updates the plan in `runs/<run-id>/plan-<req-id>.md`
- updates requirement status in `.felix/requirements.json`

---

## Felix internal state

### `.felix/state.json`

Felix’s minimal control state.

Typical contents:

- last mode
- last iteration outcome
- pointer to last run

You normally do not edit this by hand.

---

### `.felix/runs/<run-id>/`

Each iteration produces a run directory.

Contents may include:

- logs
- structured outputs
- notes
- tool results

These are for debugging and auditing, not long term memory.

---

## Getting started from scratch

### Step 1: Write specs

Create `specs/*.md`.

Do not write a plan yet.

---

### Step 2: Create .felix/requirements.json

Create the `.felix/` directory and add `requirements.json` with entries for each spec:

- id (e.g., S-0001)
- title
- spec_path
- initial status (draft)

This gives Felix structure from day one.

---

### Step 3: Write AGENTS.md

Document how to:

- run tests
- build the project
- start the app

Keep it short.

---

### Step 4: Add prompts

Create:

- `.felix/prompts/planning.md`
- `.felix/prompts/building.md`

Start simple.

---

### Step 5: First planning run

Run Felix in planning mode.

Expected outcome:

- Per-requirement plan created in runs/<run-id>/plan-<req-id>.md
- requirement statuses updated
- no code changes

---

### Step 6: First building run

Run Felix in building mode.

Expected outcome:

- one plan item implemented
- backpressure executed
- commit created or failure recorded
- task or requirement status updated

Felix exits after one iteration.

---

## Day to day usage

### Autonomous operation (default)

**Felix runs autonomously through all requirements:**

#### Multi-Requirement Mode (Recommended)

Use `felix loop` to process multiple requirements sequentially:

```powershell
# Process all planned requirements until none remain
felix loop

# Process up to 5 requirements then stop (not yet implemented)
# felix loop --max-requirements 5
```

**Legacy method:**

```powershell
.\\.felix\\felix-loop.ps1 C:\\path\\to\\project
```

**What the loop does:**

- Selects next available requirement (in_progress → planned)
- Spawns fresh agent process for that requirement
- Handles completion: marks complete and moves to next
- Handles blocking: marks blocked and moves to next
- Continues until all requirements processed or max limit reached
- Each requirement gets fresh context (true Ralph style)

#### Single-Requirement Mode

Use `felix run` to work on one requirement:

```powershell
# Work on specific requirement
felix run S-0008

# Legacy method
.\\.felix\\felix-agent.ps1 C:\\path\\to\\project -RequirementId S-0008
```

**What the agent does:**

- Generates implementation plan (if needed)
- Iterates continuously through tasks
- Validates with backpressure (tests/build/lint)
- Marks requirement complete or blocked
- Exits when complete, blocked, or max iterations reached

#### Via UI (Future)

When the backend is running:

1. Open Felix UI (http://localhost:3000)
2. Select project
3. Click "Start Run" to spawn felix-loop
4. UI shows real-time progress via WebSocket

**Mode transitions are automatic.** The agent plans and builds until done.

You can start the loop and walk away. State persists on disk. Progress is visible through commits and `.felix/requirements.json`.

### Manual operation (optional)

For tighter control or debugging, use legacy scripts for single iterations:

```powershell
# Single requirement, single iteration
.\\.felix\\felix-agent.ps1 C:\\path\\to\\project -RequirementId S-0008

# Review changes, then run again for next iteration
.\\.felix\\felix-agent.ps1 C:\\path\\to\\project -RequirementId S-0008
```

Most production runs use `felix loop`. The `felix run` command handles full requirement execution. Legacy scripts are for development and troubleshooting.

---

### When to return to planning

Switch to planning mode when:

- specs change
- the plan drifts
- repeated failures occur
- progress stalls

Planning is cheap. Drift is expensive.

---

## What not to do

- do not duplicate requirement content in JSON
- do not treat the plan as sacred
- do not let one iteration do many things
- do not skip backpressure
- do not store history in AGENTS.md

If something feels fuzzy, make it a file.

---

## Future extension: parallel execution

Felix is single agent by default.

The presence of `.felix/requirements.json` makes Phase 2 parallelism straightforward:

- requirements can be claimed structurally (add `claimed_by`, `claimed_at` fields)
- statuses are machine readable
- multiple Felix runners can operate safely with coordination

You do not need to change how specs or plans work.

---

## Multi-Agent Support

Felix supports multiple LLM agents through an adapter system. Switch between Droid, Claude Code, Codex CLI, and Gemini CLI seamlessly.

### Quick Start

```bash
# List available agents
felix agent list

# Check current agent
felix agent current

# Test an agent
felix agent test claude

# Switch agent
felix agent use claude

# Run with new agent
felix run S-0001
```

### Available Agents

- **Droid** (Factory.ai) - Fast, API key auth, XML completion signals
- **Claude** (Anthropic) - Best reasoning, OAuth, excellent code quality
- **Codex** (OpenAI) - Diff-based workflow, OAuth
- **Gemini** (Google) - JSON streaming, OAuth

### Authentication

**Droid:** Set `FACTORY_API_KEY` environment variable

**Claude/Codex/Gemini:** One-time OAuth setup:
```bash
claude auth login
codex auth
gemini auth login
```

### When to Switch

- **Need speed?** Use Droid
- **Complex requirements?** Use Claude
- **Want diffs?** Use Codex
- **Need JSON?** Use Gemini

### Documentation

- [SWITCHING_AGENTS.md](tuts/SWITCHING_AGENTS.md) - Quick start guide
- [MULTI_AGENT_SUPPORT.md](tuts/MULTI_AGENT_SUPPORT.md) - Comprehensive architecture docs

---

## Healthy Felix checklist

- specs are small and readable
- `.felix/requirements.json` is boring and accurate
- plan is short and current
- `AGENTS.md` fits on one screen
- one iteration equals one outcome
- rerunning Felix feels boring

That boredom is the signal the system is working.
