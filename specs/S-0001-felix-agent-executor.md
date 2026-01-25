# S-0001: Felix Agent Executor

## Narrative

As a developer, I need a standalone PowerShell agent that implements the Ralph methodology as a production-ready executor, following the three-phase funnel (requirements → planning → building) with autonomous operation, filesystem-based state persistence, and backpressure validation.

## Acceptance Criteria

### Agent Core

- [x] Standalone PowerShell script (`felix-agent.ps1`) executable without backend
- [x] Loads Felix artifacts on startup: specs/, AGENTS.md, felix/requirements.json, felix/config.json
- [x] Validates project structure before execution
- [x] Runs autonomous loop to completion (configurable max iterations)
- [x] Exits with clear status codes (success, blocked, error)

### Mode System

- [x] Implements planning mode: reads specs, generates/updates per-requirement plans in runs/<run-id>/plan-<req-id>.md, cannot modify code
- [x] Implements building mode: picks one task, investigates code, implements, validates, commits
- [x] Auto-transition: automatically switches from planning to building when `auto_transition: true` in felix/config.json
- [x] Mode guardrails enforced at runtime (planning cannot commit code)

### LLM Integration

- [x] Calls LLM via droid exec (existing Factory tooling)
- [x] Loads mode-specific prompts from felix/prompts/planning.md and felix/prompts/building.md
- [x] Gathers fresh context each iteration (specs + plan + AGENTS + codebase state)
- [x] Handles authentication via FACTORY_API_KEY environment variable

### State Management

- [x] Writes felix/state.json after each iteration (current_requirement_id, last_mode, status, iteration count)
- [x] Creates run directories in runs/<timestamp>/ for each iteration
- [x] Writes run artifacts: report.md, output.log, plan.snapshot.md, diff.patch
- [x] Updates felix/requirements.json with task/requirement status changes

### Backpressure & Validation

- [ ] Parses test commands from AGENTS.md
- [ ] Executes validation (tests, build, lint) after code changes
- [ ] Marks tasks blocked on validation failure
- [ ] Retries failed tasks according to configuration
- [ ] Only commits when validation passes

### Observability

- [x] Logs iteration progress to stdout (iteration number, mode, current task)
- [x] Records full LLM conversation in output.log
- [x] Snapshots plan state at each iteration
- [ ] Captures git diffs in diff.patch
- [x] Generates human-readable report.md summarizing outcome

## Technical Notes

**Architecture:** The agent is a separate process, not an async task. Backend spawns it via subprocess when needed. Communication is filesystem-only (no IPC, sockets, or shared memory).

**Ralph compliance:** Agent implements the canonical Ralph loop:

1. Load fresh context (reset contamination)
2. Determine mode (planning vs building)
3. Execute one iteration (one task, one outcome)
4. Validate via backpressure
5. Update artifacts
6. Exit and restart

**Naive persistence:** Each iteration starts fresh. No accumulated context or memory beyond what's in files. This keeps the agent in its "smart zone."

**Disposable plans:** Per-requirement plans in runs/<run-id>/plan-<req-id>.md are regenerated whenever stale. Not treated as sacred. Agent searches for the most recent plan for the current requirement across all run directories.

**"Don't assume not implemented":** Agent must search codebase before implementing to avoid duplication.

## Dependencies

None - this is the foundation. Backend and frontend depend on this agent being functional.
