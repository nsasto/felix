# Release Notes v2.2.0

Date: 2026-10-13

## Highlights

Felix v2.2 improves agent workflow configuration, validation and review, adds a portable swarm-and-ship skill, and introduces an early multi-harness coordinator for Felix 3.

## New Features

- Added per-phase agent configuration and expanded provider/model support, including OpenCode Go.
- Added a post-validation review phase with configurable review behavior.
- Added the portable `felix-swarm-ship` skill and installation guidance for supported agent hosts.
- Added the `features/felix3` multi-harness coordinator prototype, with Claude, Codex, and OpenCode adapters, planning/build/review prompts, run storage, and optional cloud sync.

## Improvements

- Centralized backpressure enablement checks in the validator.
- Hardened pre-review validation, including rejection of vacuous validation gates.
- Improved configuration defaults and sanitization of non-ASCII content in agent workflow inputs.

## Test Coverage

- Added Felix 3 coordinator and harness tests.
- Added C# CLI tests to the Windows CI workflow and excluded live provider diagnostics from the deterministic PowerShell test run.
- Fixed Copilot PowerShell shim argument forwarding and updated the review completion test to match fail-closed behavior.

## Breaking Changes

- None intended for the Felix 2 CLI workflow. The Felix 3 coordinator is an early feature and is not a replacement for the Felix 2 runtime.

## Upgrade

```powershell
felix update
```
