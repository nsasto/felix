# Release Notes - v1.3.0

**Release Date:** March 23, 2026

## Highlights

- Hardened Felix's planning and building output contract with strict completion markers, artifact validation, and bounded repair flow
- Added a structured C# Copilot bridge that routes Copilot execution through typed request/response handling instead of relying only on raw CLI text scraping
- Fixed local-mode execution so Felix no longer assumes a git repository exists when running in plain folders

---

## Features

### Phase 1 Contract Hardening

Felix now enforces a stricter execution contract across planning and building flows.

This release adds:

- exact standalone completion marker handling for `PLAN_COMPLETE`, `TASK_COMPLETE`, and `ALL_COMPLETE`
- provider-agnostic output normalization before completion parsing
- planning and building artifact validation against on-disk plan state
- one-shot corrective retry behavior when the contract is violated
- stronger regression coverage for adapter parsing, executor behavior, and contract repair

These changes make state transitions more deterministic and reduce the risk of false completion caused by loosely formatted provider output.

### Structured Copilot Bridge

Felix now includes a C# bridge execution path for GitHub Copilot.

This release adds:

- a typed `copilot-bridge` command inside the Felix CLI
- structured stdout/stderr capture and completion-signal extraction in C#
- retry without `--model` when Copilot rejects the configured model
- PowerShell handoff from both the main agent runner and the context builder into the C# bridge when available
- dedicated C# regression tests for bridge behavior and Copilot shim execution

This makes the Copilot path less dependent on fragile shell parsing while preserving the existing PowerShell workflow boundary for validation and orchestration.

---

## Fixes

### Local Mode Without Git

Fixed execution paths that still called git in local mode when the project directory was not a repository.

Felix now skips git state capture, commit detection, and planning guardrails in non-repository local runs while preserving normal git-backed behavior when a repository exists.

### Copilot Completion Reliability

Improved completion handling so broad phrases such as `requirement met` or inline tags no longer trigger workflow transitions.

Only exact standalone promise tags are treated as authoritative completion signals.

---

## Validation

Validated with:

- `dotnet test .\tests\Felix.Cli.Tests\Felix.Cli.Tests.csproj`
- `powershell -NoProfile -File .\run-git-test.ps1`
- `powershell -File .\scripts\package-release.ps1 -Rid win-x64`

---

## Notes

- This is a minor release because it materially improves Felix's execution reliability and introduces a new structured Copilot execution path in the C# CLI.
- The C# Copilot bridge is additive and still allows PowerShell to remain the workflow orchestrator.
- No breaking changes are intended in the public CLI surface for existing Felix commands.
