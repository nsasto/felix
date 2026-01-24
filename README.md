# Felix

<div align="center">
    <img src="img/Felix.png" alt="Felix" />
</div>
<br><br>

# Felix

Felix is a plan driven executor for Ralph style autonomous software delivery. He turns Ralph from “a loop you run” into an operable system with durable state, explicit modes, and a clean separation between planning and doing.

Ralph’s core insight is naive persistence: restart the agent in a simple outer loop so every iteration gets fresh context, while progress is kept on disk and validated by backpressure like tests, typechecks, and builds. ([Clayton Farr][1])
Felix keeps that philosophy, but moves the discipline from “best effort prompt compliance” into enforceable runtime scaffolding.

---

## What Felix is

Felix is the execution layer that implements Ralph as a product:

- **Ralph is the methodology.** A funnel and loop: define requirements, generate a plan, then iterate one task per loop until done. ([GitHub][2])
- **Felix is the runtime.** A stateful executor that:
  - persists artifacts between iterations
  - enforces mode boundaries (planning vs building)
  - makes completion explicit and observable
  - runs detached from any UI

Felix is not “a clever orchestrator.” The point is to keep the outer mechanism dumb and deterministic, while the agent does the thinking inside well shaped constraints. ([Clayton Farr][1])

---

## The Ralph model Felix follows

The Ralph Playbook clarifies that Ralph is not just “a loop that codes.” It is a funnel with **three phases, two prompts, one loop**. ([GitHub][2])

### Phase 1: Define requirements

Human in the loop conversation produces clear specs, broken into narrowly scoped topics of concern (a “one sentence without and” sanity check). ([Clayton Farr][1])

### Phase 2: Planning mode

Generate or refresh `IMPLEMENTATION_PLAN.md` via gap analysis between `specs/*` and the codebase, with strong guardrails like “don’t assume not implemented.” ([GitHub][2])

### Phase 3: Building mode

Iterate: read plan, pick the most important task, investigate existing code, implement, validate via backpressure, update artifacts, commit, exit, restart with fresh context. ([GitHub][2])

### Why this works

- **Context is everything:** keep work tight and fresh so the model stays in its “smart zone.” ([Clayton Farr][1])
- **File based memory:** specs, plan, and operational notes persist across resets. ([Clayton Farr][1])
- **Backpressure:** tests and builds force self correction before progress is accepted. ([Clayton Farr][1])
- **The plan is disposable:** regenerate it whenever it drifts. ([Clayton Farr][1])

---

## What Felix adds

Felix takes the Playbook mechanics and makes them structural.

### 1) Rules become runtime behavior

In many Ralph setups, the rules live in prompt text and can be violated accidentally. Felix shifts key invariants into the executor:

- planning mode cannot commit code
- building mode cannot proceed without a plan
- one iteration maps to one task outcome (done, blocked, or revised)
- artifacts are updated as part of the definition of “progress”

This is the core “build the builder” idea: improve the mechanism that improves everything else.

### 2) Planning and building are first class, separate concerns

The Playbook uses distinct prompts for PLANNING and BUILDING. ([GitHub][2])
Felix treats them as separate modes with separate contracts, telemetry, and failure semantics.

### 3) Detached operation

Felix is designed to run headless on a server, while a lightweight UI can observe and steer without being tightly coupled. State is not “in the chat,” it is in explicit artifacts.

### 4) Operability over vibes

Felix is built for:

- pause and resume
- replayable state
- audit trails of decisions and changes
- predictable iteration boundaries

---

## How Felix works

### The execution loop

At a high level:

1. Load artifacts (specs, plan, operational guide, repo state)
2. Select mode (planning or building)
3. Run one iteration
4. Record outputs and update artifacts
5. Decide whether to continue, stop, or switch modes

Ralph’s minimal loop is famously just a bash while loop that feeds a prompt file repeatedly. ([Clayton Farr][1])
Felix preserves the simplicity of that model, but formalizes the “what happens in an iteration” so it can be observed, tested, and extended.

### Key artifacts (canonical Ralph style)

The Playbook centers on a small set of files as the stable context. ([Clayton Farr][1])

- `specs/*`
  Requirements broken into narrowly scoped topics with descriptive filenames. IDs appear in the first line of each file. ([Clayton Farr][1])
- `specs/CONTEXT.md`
  Product and system context: tech stack, design standards, UX rules, and architectural invariants.
- `felix/requirements.json`
  Structured registry of requirements with stable IDs, status tracking, and dependencies. Provides machine-readable structure while Markdown specs hold the meaning.
- `IMPLEMENTATION_PLAN.md`
  Prioritized bullet list of tasks, updated continuously, and disposable. Snapshotted into each run for audit trail. ([Clayton Farr][1])
- `AGENTS.md`
  Operational "how to run/build/test" guide. It must stay short and operational or it pollutes every future loop. ([Clayton Farr][1])
- `felix/prompts/planning.md` and `felix/prompts/building.md`
  Mode specific instructions, including key language patterns and guardrails. ([Clayton Farr][1])

Felix supports splitting “big PRD state” into smaller, more stable files when it helps, while still keeping the Playbook’s principle: prefer simple, token efficient, inspectable artifacts (often Markdown) over heavy schemas. ([Clayton Farr][1])

---

## How Felix compares to current Ralph implementations

Felix is deliberately compatible with Ralph’s core philosophy, but differs from common implementations in what is enforced and what is left to convention.

### Versus prompt only Ralph loops

Many teams run Ralph as “just rerun the agent” and rely on the model to remember and obey rules. Felix hardens the loop boundaries and state handling so success is less about perfect prompt compliance and more about system design.

### Versus snarktank/ralph

`snarktank/ralph` is a practical TypeScript loop that runs tools like Amp or Claude Code repeatedly until PRD items are complete, persisting memory via git history plus `progress.txt` and `prd.json`. ([GitHub][3])
Felix differs mainly in emphasis:

- Felix treats the Ralph Playbook funnel (requirements, planning, building) as explicit modes with explicit contracts. ([GitHub][2])
- Felix biases toward Playbook canonical artifacts (`AGENTS.md`, `IMPLEMENTATION_PLAN.md`, `specs/*`) as the durable interface, keeping operational learnings concise and separated from progress notes. ([Clayton Farr][1])
- Felix aims to be a reusable executor substrate, not a single repo centric loop script.

### Versus ralph-orchestrator

`mikeyobrien/ralph-orchestrator` positions itself as a more feature complete orchestration framework that keeps Ralph in a loop, with “hats” and richer orchestration. ([GitHub][4])
Felix intentionally stays smaller:

- fewer abstractions
- fewer roles
- stronger focus on deterministic artifact driven iteration
- easier to reason about failures

### Versus Gas Town style multi agent orchestration

Gas Town is a workspace manager for coordinating multiple Claude Code agents with persistent work tracking. ([GitHub][5])

Felix is **single agent by default**, but **multi agent capable by design**.

Felix does not prohibit parallel execution. Instead, it avoids baking scheduling, leasing, and merge policy into the core executor. Naively allowing multiple agents to pull from the same plan introduces race conditions, conflicting edits, and ambiguous backpressure.

Felix is designed so parallelism can be added cleanly in a second phase by composition:

- multiple Felix runners
- isolated workspaces per runner
- a shared task source with explicit claiming
- an integration and merge policy outside the core loop

This preserves the simplicity and reliability of the Ralph loop while keeping a clear path to controlled parallel execution.

### Versus the Claude Code Ralph Wiggum plugin

Anthropic’s Claude Code repo includes a Ralph Wiggum plugin implementation. ([GitHub][6])
Felix is complementary: it is an application level executor and system architecture that can drive Ralph style loops regardless of which coding tool is used.

---

## Design principles

### Deterministic setup

Each iteration should start from a known state by loading the same canonical artifacts, not a long conversational transcript. ([Clayton Farr][1])

### One task per iteration

A loop iteration is an atomic unit of progress. It ends with an explicit outcome and usually a commit. ([Clayton Farr][1])

### Backpressure is non negotiable

Tests, builds, typechecks, and lints are not optional polish. They are the steering mechanism. ([Clayton Farr][1])

### Keep AGENTS operational

`AGENTS.md` is not a diary. Status and planning belong in the plan. ([Clayton Farr][1])

### The plan is disposable

If the plan is stale, wrong, or cluttered, regenerate. Cheaper than letting the loop drift. ([Clayton Farr][1])

### “Don’t assume not implemented”

The executor and prompts must bias toward searching and confirming existing functionality to avoid duplication and regressions. ([Clayton Farr][1])

---

## Repository shape and components

Felix is intended to be split into two detached parts:

- **Backend (executor + API)**
  Owns artifacts, iteration state, tool execution, and completion criteria.
- **Frontend (lightweight operator UI)**
  Observes, edits artifacts, starts and stops runs, and inspects iteration outputs.

This separation is intentional: the UI is an operator console, not the brain.

### Internal structure

Felix maintains its state in a `felix/` directory and execution evidence in `runs/`:

- `felix/requirements.json` – central registry of requirements and work state
- `felix/state.json` – minimal control state (current requirement, last mode, iteration outcome)
- `felix/config.json` – executor configuration
- `felix/prompts/` – mode-specific prompt templates
- `felix/policies/` – allowlists and constraints
- `runs/<run-id>/` – per-iteration append-only logs, plan snapshots, diffs, and reports for auditing

---

## Glossary

- **Iteration**: one fresh context run producing one task outcome. ([Clayton Farr][1])
- **Backpressure**: validation gates that force self correction. ([Clayton Farr][1])
- **Artifacts**: the durable files that carry memory between iterations. ([Clayton Farr][1])
- **Planning mode**: update the plan only, no implementation. ([GitHub][2])
- **Building mode**: implement one prioritized plan item, validate, commit. ([GitHub][2])

---

## References

- The Ralph Playbook (Clayton Farr), formatted guide and detailed mechanics. ([Clayton Farr][1])
- `snarktank/ralph` autonomous PRD driven loop implementation. ([GitHub][3])
- `mikeyobrien/ralph-orchestrator` orchestration framework variant. ([GitHub][4])
- `steveyegge/gastown` multi agent workspace manager for Claude Code. ([GitHub][5])
- Claude Code Ralph Wiggum plugin documentation. ([GitHub][6])
