# Felix, Explained (Like You're Smart, Not Like You're a Computer)

Felix is a "Ralph-style" autonomous delivery system: you feed it specs, it makes (and follows) a plan, and it keeps going until the work is done -- or it can prove it's blocked.

If you've ever watched an AI coding session start brilliant and end like a soap opera ("wait... why is there a second auth system?"), Felix exists because of that exact pain.

Ralph's core bet is simple:

- Long conversations pollute context.
- Fresh starts keep the model in its "smart zone".
- Files + tests + git are better memory than vibes.

Felix turns that bet into an operable project with real artifacts, mode boundaries, and an execution loop you can observe.

---

## 1) The Big Picture: A Tiny Brain, a Big Clipboard

Think of Felix like a very capable builder who wakes up every morning with mild amnesia.

That sounds scary until you hand them:

- A blueprint (`specs/*.md`)
- Working plans scoped to each requirement (`runs/<run-id>/plan-<req-id>.md`)
- An operations manual (`AGENTS.md`)
- A clipboard with status checkboxes (`..felix/requirements.json`, `..felix/state.json`)
- A folder of receipts (everything under `runs/`)

Every "day" (iteration), the builder reads the same small set of documents, does one unit of work, updates the documents, and goes back to sleep.

No sprawling chat history. No "I think we already did that?" Just: read -> do -> write -> repeat.

---

## 2) The Architecture (Who Talks to Whom, and How)

Felix is intentionally split into three independent pieces:

1. Agent (the worker)
2. Backend (the dispatcher + librarian)
3. Frontend (the dashboard)

The most important design decision is how they communicate:

### Filesystem is the "message bus"

- The agent reads specs/plan/config from disk and writes results back to disk.
- The backend spawns the agent as a separate process and (eventually) watches the filesystem for changes.
- The frontend talks only to the backend over HTTP/WebSocket.

No RPC between backend and agent. No sockets. No shared memory. Just files.

Why that's good:

- If something goes wrong, you can open a file and see what happened.
- You can kill and restart parts without losing "memory".
- You get an audit trail for free (git + run artifacts).

---

## 3) Repo Tour: Where Everything Lives

Here's the codebase as a map you can keep in your head:

### Runtime + agent

- `felix-agent.ps1` - the current Felix agent (PowerShell). This runs the loop.
- `..felix/` - Felix's "artifact directory" (prompts, policies, config, state).
- `runs/` - per-iteration run artifacts (logs, snapshots, reports).

### Backend (optional, but very useful)

- `app/backend/main.py` - FastAPI server entrypoint (HTTP API, spawns agents).
- `app/backend/routers/projects.py` - register/list projects.
- `app/backend/routers/files.py` - read/write specs, plan, requirements; includes path-policy enforcement.
- `app/backend/routers/runs.py` - spawn agent processes + track run status in memory.
- `app/backend/storage.py` - persists the project registry in `~/...felix/projects.json`.
- `app/backend/models.py` - Pydantic request/response models.

### Frontend (currently a scaffold)

- `app/frontend/` - React + TypeScript + Vite app.
  - Today, it's still a "generic AI workspace UI" scaffold (Gemini chat + kanban + markdown assets).
  - The specs describe refactoring it into a Felix observer console later.

### Methodology + specs

- `specs/` - requirements/spec documents (what should exist).
- `CONTEXT.md` - design/stack/UX invariants and rules of the game.
- `README.md`, `HOW_TO_USE.md`, `RALPH_EXPLAINED.md` - the "why" and "how to operate" docs.

---

## 4) The Artifacts (Felix's "Durable Memory")

If you remember nothing else, remember this: Felix is a file-based system.

These files are the product as much as the code is.

### `specs/*.md`: "What do we want?"

Humans write these. They're meant to be stable, narrow, and readable.

### Plans: Per-Requirement Focus

**`runs/<run-id>/plan-<req-id>.md`:** Narrow, disposable plans scoped to single requirements. This is what the agent creates, reads, and updates. Created fresh during planning mode with iterative self-review.

The plan is not sacred scripture; it's a whiteboard that gets regenerated when needed.

### `AGENTS.md`: "How do I run this repo?"

Felix loads this file into context, so it's intentionally operational-only:
install commands, dev server commands, build commands. No diaries.

### `..felix/requirements.json`: "What's the status?"

Machine-readable registry of requirements:

- IDs, titles, statuses (`draft`, `planned`, `in_progress`, `complete`, `blocked`)
- dependencies (`depends_on`)

This is what a UI can safely rely on without parsing prose.

### `..felix/state.json`: "Where am I in the loop?"

Minimal control state for the agent and observers:

- last mode (planning/building)
- last outcome
- iteration counters

### `runs/<timestamp>/...`: "Show your work"

Each iteration produces a folder with receipts, like:

- `output.log` - full model output from that iteration
- `report.md` - a human-readable summary
- `plan.snapshot.md` - what the plan looked like at that moment

This is how you debug an autonomous system without guessing.

---

## 5) The Agent: How `felix-agent.ps1` Thinks

The current agent is PowerShell (`felix-agent.ps1`) because Felix is designed to run comfortably on Windows and because it integrates cleanly with existing tooling (`droid exec`).

### Step A: Validate the project looks "Felix-shaped"

The agent requires a minimum structure in the target project:

- `specs/`
- `..felix/` with `config.json` and `requirements.json`

If those aren't present, it exits early instead of doing something wild.

### Step B: Pick a requirement to work on

It selects the first requirement with:

1. `status: in_progress`, otherwise
2. `status: planned`

That's the "current requirement" for the run.

### Step C: Decide the mode

Felix has two modes:

- Planning mode: create/update requirement-specific plan in `runs/<run-id>/plan-<req-id>.md`; iterate with self-review; no code edits.
- Building mode: implement work; update plan in `runs/<run-id>/plan-<req-id>.md`; possibly update requirement status.

In the current PowerShell agent:

- If there is no `runs/<run-id>/plan-<req-id>.md` for the current requirement, it goes planning.
- Otherwise it goes building.
- Planning mode loops multiple times with self-review before signaling `<promise>PLAN_COMPLETE</promise>`.
- It tries to continue from the previous `last_mode` on the first iteration.

### Step D: Gather context and call the model

The agent builds one big prompt from:

- `AGENTS.md`
- the current requirement's spec file only (narrow scope)
- `runs/<run-id>/plan-<req-id>.md` (only in building mode)
- `..felix/requirements.json` (embedded as JSON)
- the current requirement ID

Note: The agent loads only the current requirement's spec, not all specs. This keeps context narrow and focused.

Then it shells out to:

`droid exec --skip-permissions-unsafe`

That command is the bridge to the LLM (via Factory tooling).

### Step E: Record receipts

For every iteration it creates `runs/<timestamp>/` and writes:

- `output.log`
- `report.md`
- `plan.snapshot.md` (building mode)

### Step F: Stop conditions

The agent watches for completion signals in the model output:

- `<promise>PLAN_COMPLETE</promise>`: Planning iteration finished successfully; ready to transition to building mode
- `<promise>COMPLETE</promise>`: Work iteration finished successfully; task or requirement is done

These signals determine when to move to the next phase or iteration.

---

## 6) The Backend: A Dispatcher You Can Trust

The backend is FastAPI (`app/backend/main.py`) and it plays three roles:

1. Project registry: "what repos are we managing?"
2. File gateway: safe read/write access for the UI
3. Process spawner: start agent runs and track status

### Project registry (`~/...felix/projects.json`)

`app/backend/storage.py` stores registered projects in the user's home directory.

Why not in the repo?

- You can register multiple projects without touching each repo.
- You don't accidentally commit your local machine paths.

### Spawning the agent

`app/backend/routers/runs.py` spawns `felix-agent.ps1` as a detached process.

Important details:

- It uses `powershell.exe` on Windows (or `pwsh` on Unix).
- It tracks the PID and run metadata in memory.
- It includes cleanup logic for dead/stale processes so you don't get "ghost runs".

### File API + security policies

`app/backend/routers/files.py` is where Felix gets serious about safety.

It validates writes against `..felix/policies/allowlist.json` and `..felix/policies/denylist.json`:

- "You may write to `specs/**` and `runs/**`..."
- "...but not to prompt templates or policies themselves."

This exists because a file-editing API is one accidental path traversal away from becoming "remote control for your laptop".

---

## 7) The Frontend: What It Is Today (and What It Wants to Become)

`app/frontend/` is React 19 + TypeScript + Vite.

Right now it's best described as:

- a nice UI scaffold (kanban, markdown assets, a chat panel)
- still wired to a Gemini-based helper (`app/frontend/services/geminiService.ts`)
- not yet wired into the Felix backend API or its real artifacts

The `specs/S-0003-frontend-observer-ui.md` file lays out the intended refactor:

- project registration + selection
- specs editor (real `specs/*.md`)
- plan view (per-requirement plans from `runs/`)
- requirement kanban (real `..felix/requirements.json`)
- run monitor (eventually via WebSockets + filesystem watching)

So the frontend is a "future observer console", but it hasn't been plumbed in yet.

---

## 8) Why These Technical Decisions Were Made

### Filesystem-only communication

This is the "boring but powerful" choice:

- easy to debug
- easy to audit
- easy to resume
- hard to accidentally hide state in runtime memory

### Two explicit modes (planning vs building)

A huge percentage of agent failures come from mixing:

- thinking about what to do
- and doing it

Felix separates those on purpose:

- planning mode is allowed to be wrong-but-useful
- building mode is forced to be concrete and verifiable

### Markdown + JSON (not one perfect format)

- Markdown is great for humans.
- JSON is great for tools.

Felix uses both so you don't end up forcing one format to impersonate the other.

---

## 9) "Bugs We Ran Into" (and the Lessons They Teach)

This project is young, but the commit history already shows a few classic agent-system faceplants and fixes:

### 1) "Oops, the backend can write anywhere"

When you build endpoints like `PUT /specs/:filename`, you discover that filenames are a security boundary.

Fix implemented:

- path allowlist/denylist enforcement in `app/backend/routers/files.py`
- safer filename validation and pattern matching

Lesson:

- Treat paths like user input (because they are).
- Make "safe paths" a first-class concept, not an afterthought.

### 2) "The agent is running... except it's not"

Process orchestration is full of "ghost state":

- the backend thinks a PID is alive
- the OS disagrees
- your UI shows "running forever"

Fix implemented:

- status checks + cleanup logic in `app/backend/routers/runs.py`

Lesson:

- Anything in memory is a rumor; disk (and the OS) is reality.

### 3) "Is the LLM down, or is my config broken?"

Without a connectivity test, you can't tell if your system is failing because:

- the model is unreachable
- your API key isn't set
- your tool wrapper is misconfigured

Fix implemented:

- a `--test-connection` path in the earlier Python agent (`app/backend/agent.py`)

Lesson:

- Add smoke tests for integrations before you build fancy features on top.

### 4) "We changed agent languages mid-flight"

Felix started with a Python agent implementation and later transitioned to a PowerShell agent (`felix-agent.ps1`) so it could run naturally in a Windows-first workflow and lean on existing `droid exec` tooling.

Lesson:

- It's fine to pivot on implementation details, as long as your interfaces stay stable.
- In Felix, the "interface" is the artifact contract: specs/plan/state/runs.

### 5) The silent killer: encoding weirdness

You'll notice some docs contain mojibake (garbled) characters.

Lesson:

- Pick UTF-8 everywhere, enforce it, and normalize copied text.
- If your system's "memory" is files, corrupted text is corrupted memory.

---

## 10) How Good Engineers Think Here (The Meta-Lessons)

Felix is not just an agent. It's a set of engineering habits made concrete:

### Make state explicit

If it matters tomorrow, write it down today -- in the right file.

### Prefer small, verifiable steps

"One task per iteration" isn't a moral rule; it's how you keep the system steerable.

### Design for restarts

If restarting breaks you, your system is fragile.
Felix is built on the opposite premise: restarts are normal.

### Backpressure is steering, not bureaucracy

Tests/builds/lints aren't "polish".
They're the steering wheel that keeps an autonomous worker between the guardrails.

This repo has the scaffolding for that mindset, even where full test suites aren't implemented yet.

---

## 11) Practical Pitfalls (and How to Avoid Them)

- Letting `AGENTS.md` become a diary: it bloats every iteration's context and makes the agent worse. Keep it operational.
- Treating the plan as sacred: stale plans are expensive; regenerating is cheap.
- Skipping "investigate first": duplicate implementations are the #1 way agents create chaos.
- No run receipts: if you can't answer "what happened in iteration 7?", you can't trust autonomy.
- Too many moving parts at once: start with the artifacts + agent loop; add backend/UI once the loop is boring.

---

## 12) If You Want to Extend Felix Next

These are the highest-leverage improvements that match the current architecture:

- Implement true backpressure in the PowerShell agent (parse commands from `AGENTS.md`, run them, block on failure).
- Add filesystem watching + WebSockets in the backend (the specs call for it).
- Wire the frontend to real artifacts (specs editor, plan view, requirement kanban).
- Unify/retire legacy agent code paths (the Python agent in `app/backend/agent.py` is useful for reference, but it's not what `runs.py` spawns today).
- Add a `felix init` scaffolder (see `specs/S-0004-artifact-templates.md`).

---

## 13) Running It

This tutorial is about the architecture and "why".

For the exact commands to run the backend and frontend, use:

- `AGENTS.md`

That file is intentionally short so Felix can read it every iteration without getting distracted.

---

## 14) The "Unchecked Box" Philosophy

You might notice that even when a Requirement is marked **COMPLETE**, the checkboxes in the `.md` file are still empty `[ ]`.

**Why doesn't Felix check them off?**

Imagine a Pilot's Pre-flight Checklist:

1.  [ ] Check Fuel
2.  [ ] Check Flaps
3.  [ ] Check Radio

If the pilot checks those boxes with a permanent marker on Day 1, **they can never check them again on Day 2.**

**Felix works the same way:**

1.  **The Spec (`specs/S-001.md`) is the Pre-flight Checklist.** We run these checks _every single iteration_ to make sure the "plane" (your app) is still flying correctly.
2.  **The Plan (`runs/.../plan.md`) is the Flight Log.** The Agent _does_ check these boxes `[x]` as it builds things, so it knows what it built today.

### Summary

| File Type | Purpose              | Checkboxes work like...                                           |
| :-------- | :------------------- | :---------------------------------------------------------------- |
| **Spec**  | Validation & Testing | **Use `[ ]`** (Active Test) <br> Use `[x]` (Disabled/Manual Test) |
| **Plan**  | Construction Steps   | **Use `[x]`** (Task Done)                                         |


