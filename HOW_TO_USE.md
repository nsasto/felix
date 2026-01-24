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
├── IMPLEMENTATION_PLAN.md
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
- status (draft, planned, in_progress, done, blocked)
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
      "updated_at": "2026-01-24"
    }
  ]
}
```

Keep this boring and stable. JSON grows painful when it tries to express nuance.

---

## `IMPLEMENTATION_PLAN.md` – disposable plan

This is the **current plan**, not the historical record.

Contents:

- prioritized bullet list of tasks
- phrased as concrete work items
- often referencing requirement IDs

Rules:

- disposable
- frequently rewritten
- always reflects current understanding

If the plan becomes cluttered or wrong, regenerate it.

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

Planning mode instructions.

Planning mode:

- reads `specs/` and `felix/requirements.json`
- updates `IMPLEMENTATION_PLAN.md`
- may update requirement status
- must not modify source code

### `felix/prompts/building.md`

Building mode instructions.

Building mode:

- selects exactly one plan item from `IMPLEMENTATION_PLAN.md`
- inspects existing code first
- implements one task
- runs backpressure (tests, build, lint)
- commits or reports failure
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

- `IMPLEMENTATION_PLAN.md` created or refreshed
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

**Felix agent runs autonomously through all tasks:**

**Option A: Via UI**

1. Open Felix UI (http://localhost:3000)
2. Select project or register new one
3. Click "Start Run"
4. Backend spawns agent process for that project
5. Agent runs to completion
6. UI shows real-time progress via WebSocket

**Option B: Via CLI (Pure Ralph)**

1. Navigate to project: `cd my-todo-app`
2. Run agent: `felix run` (or `felix-agent .`)
3. Agent runs to completion
4. No UI needed - pure command line

**What the agent does:**

- Starts in planning mode if no plan exists
- Generates implementation plan
- **Automatically transitions to building mode**
- Iterates continuously through tasks:
  - Picks next task
  - Implements
  - Validates
  - Updates status
  - Commits
  - Repeats
- Returns to planning mode if plan becomes stale
- Transitions back to building after replanning
- Stops when all requirements complete or all tasks blocked

**Mode transitions are automatic.** Start the agent once, it plans and builds until done.

You can start the agent and walk away. State persists on disk. Progress is visible through commits and `felix/state.json`.

### Manual operation (optional)

For tighter control or debugging:

1. Run Felix with single-iteration flag
2. One task executes
3. Felix exits
4. Review changes
5. Repeat manually

Most production runs use autonomous mode. Manual mode is for development and troubleshooting.

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
