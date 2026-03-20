# Release Notes - v1.2.0

**Release Date:** March 20, 2026

## Highlights

- Added first-class GitHub Copilot CLI support as a distinct Felix agent adapter
- Modernized interactive setup and agent-selection flows with searchable Spectre.Console-based CLI experiences
- Added provider-specific install guidance and curated model selection for supported local agent CLIs

---

## Features

### GitHub Copilot CLI Adapter

Felix now supports GitHub Copilot CLI as a dedicated local adapter rather than treating it as Codex.

This release adds:

- a separate `copilot` adapter and default profile
- Copilot-specific invocation handling for prompt argument transport
- setup-time detection for the Windows VS Code Copilot CLI shim
- curated Copilot model selection with `gpt-5.4` as the default

This makes Copilot available as a first-class local Felix agent alongside Droid, Claude, Codex, and Gemini.

### Agent Install Guidance

Felix now includes provider-specific installation help through:

- `felix agent install-help`
- `felix agent install-help <name>`

This gives concrete install and login directions for Droid, Claude, Codex, Gemini, and Copilot when an adapter is not yet available on the machine.

### Modern Interactive Setup

The installed CLI now provides richer interactive flows for setup-style commands:

- `felix setup`
  - searchable project setup flow
  - idempotent project scaffolding
  - optional `AGENTS.md` creation
  - active-agent selection
  - local/remote mode setup with API key validation
- `felix agent setup`
  - searchable multi-select of installed providers
  - per-provider model selection
  - clearer provider status and install guidance
- `felix agent use`
  - searchable interactive agent picker
  - optional model switching with Enter preserving the current model

These changes are focused on interactive setup and selection commands. The underlying PowerShell execution path remains in place for autonomous run and loop behavior.

---

## Fixes

### Interactive Agent Target Handling

Fixed PowerShell argument normalization issues that could truncate interactive `felix agent use` target values and produce errors such as `Agent not found: a`.

### Agent Profile and Key Consistency

Improved compatibility between legacy `id` fields and current content-addressed `key` fields, while keeping deterministic agent identity generation intact across setup and agent-switch flows.

This also improves consistency between setup-time profile creation, active-agent switching, and runtime agent resolution.

---

## Validation

Validated with:

- `dotnet test .\tests\Felix.Cli.Tests\Felix.Cli.Tests.csproj`
- `dotnet build .\src\Felix.Cli\Felix.Cli.csproj`
- `powershell -File .\scripts\package-release.ps1 -Rid win-x64`

---

## Notes

- This is a minor release because it introduces new user-visible CLI capabilities and expands supported local agent workflows.
- Existing PowerShell-backed execution flows remain intact; the richer UI is focused on interactive setup and selection commands.
- If you already have Felix installed globally, update the installed CLI before expecting the new interactive setup experience from the `felix` command on PATH.
