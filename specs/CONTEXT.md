# Context

This file documents product and system context for Felix.

## Tech Stack

- Language: (to be determined)
- Framework: (to be determined)

## Design Standards

- Keep the outer mechanism dumb
- File-based memory and state
- Deterministic, reproducible iterations

## UX Rules

- Minimal UI - operator console, not the brain
- State visible through file system
- Clear separation between planning and building

## Architectural Invariants

- Planning mode cannot commit code
- Building mode requires a plan
- One iteration equals one task outcome
- Backpressure is non-negotiable
