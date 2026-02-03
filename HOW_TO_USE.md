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
├── felix/
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

If your environment uses a non-standard Python executable, set the path in `felix/config.json` under the `python.executable` key so scripts like `validate-requirement.py` can be invoked reliably.

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
- If `py -3` is not present, use `python` or provide the full Python executable path in `felix/config.json`.

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

## `felix/requirements.json` – structured registry and status

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
  - If omitted: uses `felix/config.json` → `executor.commit_on_complete` setting
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
3. **Manually reset status**: Edit `felix/requirements.json` and change the requirement's status from `"blocked"` to `"planned"`
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

### `felix/prompts/planning.md`

Planning mode instructions with **iterative refinement**.

Planning mode:

- reads `specs/` and `felix/requirements.json`
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

### `felix/prompts/building.md`

Building mode instructions.

Building mode:

- reads plan from `runs/<run-id>/plan-<req-id>.md` (narrow, requirement-specific)
- selects exactly one plan item
- inspects existing code first
- implements one task
- runs backpressure (tests, build, lint)
- commits or reports failure
- updates the plan in `runs/<run-id>/plan-<req-id>.md`
- updates requirement status in `felix/requirements.json`

---

## Felix internal state

### `felix/state.json`

Felix’s minimal control state.

Typical contents:

- last mode
- last iteration outcome
- pointer to last run

You normally do not edit this by hand.

---

### `felix/runs/<run-id>/`

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

### Step 2: Create felix/requirements.json

Create the `felix/` directory and add `requirements.json` with entries for each spec:

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

- `felix/prompts/planning.md`
- `felix/prompts/building.md`

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

Use `felix-loop.ps1` to process multiple requirements sequentially:

```powershell
# Process all planned requirements until none remain
.\felix-loop.ps1 C:\path\to\project

# Process up to 5 requirements then stop
.\felix-loop.ps1 C:\path\to\project -MaxRequirements 5
```

**What the loop does:**

- Selects next available requirement (in_progress → planned)
- Spawns fresh felix/felix-agent.ps1 process for that requirement
- Handles completion: marks complete and moves to next
- Handles blocking: marks blocked and moves to next
- Continues until all requirements processed or max limit reached
- Each requirement gets fresh context (true Ralph style)

#### Single-Requirement Mode

Use `felix/felix-agent.ps1` directly to work on one requirement:

```powershell
# Work on specific requirement
.\felix\felix-agent.ps1 C:\path\to\project -RequirementId S-0008

# Work on first available requirement (in_progress or planned)
.\felix\felix-agent.ps1 C:\path\to\project
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

You can start the loop and walk away. State persists on disk. Progress is visible through commits and `felix/requirements.json`.

### Manual operation (optional)

For tighter control or debugging:

```powershell
# Single requirement, single iteration
.\felix\felix-agent.ps1 C:\path\to\project -RequirementId S-0008

# Review changes, then run again for next iteration
.\felix\felix-agent.ps1 C:\path\to\project -RequirementId S-0008
```

Most production runs use `felix/felix-loop.ps1`. Manual mode is for development and troubleshooting.

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

The presence of `felix/requirements.json` makes Phase 2 parallelism straightforward:

- requirements can be claimed structurally (add `claimed_by`, `claimed_at` fields)
- statuses are machine readable
- multiple Felix runners can operate safely with coordination

You do not need to change how specs or plans work.

---

## Healthy Felix checklist

- specs are small and readable
- `felix/requirements.json` is boring and accurate
- plan is short and current
- `AGENTS.md` fits on one screen
- one iteration equals one outcome
- rerunning Felix feels boring

That boredom is the signal the system is working.
