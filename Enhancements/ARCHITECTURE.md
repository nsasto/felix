# Felix Local Execution Architecture

High Level Intent and Approach

## Intent

We want Felix to support three local interaction modes using the same execution engine:

- Plain console usage for developers and CI
- A rich terminal UI for interactive local runs
- A desktop tray application for background control and visibility

All three must be powered by the same underlying execution logic, with no duplication and no UI specific branching inside the engine.

The execution engine must remain local first and authoritative. UI layers observe and control it, but do not replace or duplicate its logic.

The current PowerShell based engine is retained.

---

## Core Design Principle

**One engine, many front ends.**

The engine emits structured events that describe what is happening.
All UIs consume those events and render them differently.

No UI parses freeform logs to infer state.

---

## Current State

- Core execution logic lives in PowerShell scripts
- `felix-loop` or `felix-agent` is the single master entrypoint
- Subscripts are called from the master loop
- A C# tray application already exists
- We want to add a proper console experience without rewriting the engine

---

## Target Architecture

### Components

1. PowerShell execution engine
2. Small C# host executable
3. Multiple front ends
   - plain console
   - terminal UI
   - tray app

### Responsibilities

#### PowerShell engine

- Owns execution logic
- Emits structured events describing:
  - run lifecycle
  - phases and steps
  - logs and errors
  - progress
  - prompts
  - artifacts produced

- Writes run artifacts to a run specific directory
- Does not contain UI logic
- Does not directly prompt the user via `Read-Host`

#### C# host executable

- Single stable entrypoint for all local usage
- Launches `felix-loop.ps1` as a subprocess
- Creates and manages a run directory
- Reads stdout and stderr from PowerShell
- Forwards structured events as newline delimited JSON
- Wraps any unstructured output as log events
- Handles cancellation
- Bridges prompt responses from UIs back to the engine

This host is the integration layer between scripts and UIs.

#### Front ends

All front ends consume the same event stream.

- Plain console
  - human friendly output
  - suitable for CI and quick runs

- Terminal UI
  - rich interactive console experience
  - progress, logs, prompts, artifact visibility

- Tray app
  - background execution
  - notifications
  - prompt handling
  - status visibility

Front ends do not run logic. They observe and control via events and responses.

---

## Event Model

The engine emits **newline delimited JSON events** to stdout.

Each event is a single JSON object on one line.

Events include:

- run started and finished
- phase started and finished
- step started and finished
- log messages with levels
- progress updates
- artifact creation
- prompt requests

This event stream is the system contract.

---

## Prompt Handling

The engine does not block on console input.

Instead:

- the engine emits a prompt event with a prompt id
- the engine waits for a response
- the response is delivered by a UI

For robustness and cross language simplicity, prompt responses are file based in the run directory.

This works for:

- tray apps
- console usage
- background execution

---

## Run Directory Convention

Each execution has its own directory.

Example structure:

- runs/<run_id>/
  - events.ndjson
  - artifacts/
  - prompts/
  - cancel.txt
  - manifest.json

This provides auditability and makes runs observable after completion.

---

## Console Experience

The system supports three console modes:

- Plain text console output
- Machine readable NDJSON output
- Rich terminal UI

All are powered by the same engine and host.

---

## Why This Approach

- Preserves existing PowerShell investment
- Avoids rewriting execution logic
- Enables multiple UIs with no duplication
- Keeps the engine local, inspectable, and debuggable
- Scales cleanly to future cloud monitoring or remote control
- Allows gradual enhancement rather than a big rewrite

---

## Immediate Next Steps

The next phase is specification and implementation planning, not UI polish.

Suggested focus areas for the next spec:

1. Event schema and required fields
2. PowerShell event helper functions
3. Changes to `felix-loop` to emit lifecycle events
4. C# host responsibilities and command structure
5. Prompt response and cancellation flow
6. Minimal console rendering strategy

---

## Non Goals (for now)

- Rewriting the engine in another language
- Cloud execution
- Multi user orchestration
- Full GUI application
