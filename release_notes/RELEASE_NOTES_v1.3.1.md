# Release Notes - v1.3.1

**Release Date:** March 23, 2026

## Highlights

- Fixed Windows Copilot bridge resolution to prefer the installed batch wrapper over the VS Code PowerShell bootstrap shim when both are present
- Refreshed the Droid model catalog to match the current supported model list used during setup and selection

---

## Fixes

### Copilot Windows Shim Resolution

Felix now normalizes Windows Copilot executable resolution so a resolved `copilot.ps1` path is upgraded to a sibling `copilot.bat`, `copilot.cmd`, or `copilot.exe` when available.

This avoids failures caused by the VS Code PowerShell shim in headless bridge execution, including startup errors such as empty-path `Split-Path` failures.

### Droid Model Catalog Refresh

Updated the Droid provider model catalog and setup fallback list to the current supported options:

- `claude-opus-4-6`
- `claude-opus-4-6-fast`
- `claude-opus-4-5-20251101`
- `claude-sonnet-4-6`
- `claude-sonnet-4-5-20250929`
- `claude-haiku-4-5-20251001`
- `gpt-5.4`
- `gpt-5.3-codex`
- `gpt-5.2-codex`
- `gpt-5.2`
- `gemini-3.1-pro-preview`
- `gemini-3-flash-preview`
- `glm-4.7`
- `glm-5`
- `kimi-k2.5`
- `minimax-m2.5`

---

## Validation

Validated with:

- `dotnet test .\tests\Felix.Cli.Tests\Felix.Cli.Tests.csproj`

---

## Notes

- This is a patch release focused on compatibility and catalog accuracy.
- No intentional CLI breaking changes.
