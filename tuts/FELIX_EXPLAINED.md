# Felix Artifacts

This document explains the durable files Felix uses to keep progress, enforce workflow boundaries, and leave a complete audit trail behind every run.

---

## Mental Model

Felix treats the filesystem as working memory.

- Specs define what must be true.
- Plans define what to do next.
- JSON state tracks scheduling and execution.
- Run artifacts record what happened on each iteration.

The agent is intentionally restart-friendly: it can stop, reload fresh context, and continue because the important state already lives on disk.

---

## The Core Files

### `specs/`

Requirement specifications live here.

- `specs/CONTEXT.md` captures product context, constraints, and standards.
- `specs/S-0001-some-feature.md` captures one requirement per file.
- Validation criteria stay unchecked so Felix can re-run them every iteration.

Specs are long-lived. They are the contract.

### `runs/`

Each iteration writes a new run directory:

```
runs/
└── S-0001-20260224-164140-it7/
    ├── requirement_id.txt
    ├── output.log
    ├── report.md
    ├── plan-S-0001.md
    ├── diff.patch
    ├── backpressure.log
    ├── blocked-task.md
    ├── guardrail-violation.md
    └── max-retries-exceeded.md
```

Common files:

- `requirement_id.txt` identifies the requirement for the run.
- `output.log` stores raw agent output.
- `report.md` summarizes the iteration outcome.
- `plan-S-XXXX.md` stores the working plan snapshot for the requirement.
- `diff.patch` captures the code diff when changes are made.

Conditional files:

- `backpressure.log` appears when validation commands run.
- `blocked-task.md` explains why a task could not proceed.
- `guardrail-violation.md` records planning-mode violations.
- `max-retries-exceeded.md` records retry exhaustion.

Run directories are disposable as working directories, but valuable as evidence.

### `.felix/requirements.json`

This is the scheduling index.

It tracks what exists and what state each requirement is in:

- `draft`
- `planned`
- `in_progress`
- `complete`
- `blocked`

Felix uses this file to decide what to run next and to persist completion or blockage state.

### `.felix/config.json`

This stores active runtime configuration.

Typical concerns include:

- active agent selection
- sync settings
- backpressure command configuration

### `.felix/agents.json`

This stores the available agent profiles.

Felix now separates:

- profile configuration in `.felix/agents.json`
- active-agent selection in `.felix/config.json`

That split matters because `felix setup` and `felix agent use` no longer rely on a hardcoded provider list. They work from the configured profiles you actually have.

### `.felix/sessions.json`

This tracks active Felix processes so commands like `felix procs` can show or kill running sessions.

---

## Plans Vs Specs

This is the most important distinction in Felix.

- Specs are test suites. They stay relevant until the requirement is truly complete.
- Plans are to-do lists. They are working documents and can be regenerated.

If a plan gets stale, replace it. If a spec is wrong, fix the requirement.

---

## Why This Works

Artifact-based execution gives Felix a few useful properties:

- Fresh context every iteration without losing state
- Inspectable progress in git and on disk
- Deterministic mode boundaries between planning and building
- Stronger debugging because every run leaves evidence behind
- Optional cloud sync without making local execution dependent on the network

The result is a loop that behaves more like a build system than a chat session.

---

## Related Documentation

- [EXECUTION_FLOW.md](EXECUTION_FLOW.md) - Step-by-step mode transitions and validation gates
- [CLI Reference](../docs/CLI.md) - Commands, setup flow, and operational workflows
- [Sync Operations](../docs/SYNC_OPERATIONS.md) - Cloud sync, outbox behavior, and troubleshooting
