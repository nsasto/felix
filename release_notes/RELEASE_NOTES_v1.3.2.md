# Release Notes - v1.3.2

**Date:** 2026-03-23

## Fixes

- **Copilot agent no longer uses the C# bridge by default.** The bridge added unnecessary overhead (two-process spawn, temp file I/O, JSON round-trips) and was the root cause of the recurring `Cannot find GitHub Copilot CLI` error. Copilot now runs directly like all other agents (droid, claude, etc.). The bridge can still be re-enabled with `$env:FELIX_COPILOT_BRIDGE=1` if needed.
- **Copilot executable resolution now prefers `.ps1` over `.cmd`/`.bat`.** Both `GetCopilotExecutableCandidates` (C#) and `Resolve-FelixExecutablePath` (PowerShell) no longer swap a resolved `.ps1` for its `.cmd`/`.bat` sibling. This prevents the script from being invoked via `powershell -Command` which left `$MyInvocation.MyCommand.Path` empty inside the Copilot bootstrapper, causing the "Cannot find GitHub Copilot CLI" error.
- **Removed `AnsiConsole.Clear()` from all non-TUI CLI command handlers** (`spec status`, `spec delete`, `spec fix`, `spec pull`, `spec push`). These commands no longer wipe the terminal on execution.
