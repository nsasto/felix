# Release Notes - v1.1.1

**Release Date:** March 18, 2026

## Highlights

- Fixed `felix context build` so it resolves and invokes the configured agent through the adapter path used by the main runtime
- Added verbose pass-through and plain-text response rendering for context builds
- Fixed Felix CLI bundle packaging on Linux CI by removing the Windows-only `cmd /c` dependency from the build target

---

## Fixes

### Context Builder Agent Invocation

`felix context build` now:

- resolves the active agent through shared agent configuration logic
- uses adapter-built arguments instead of invoking the raw executable without adapter context
- forwards `--verbose` into the adapter path
- parses successful Droid JSON responses into plain text for console display

This fixes the failure mode where context build appeared to stall or failed to call the agent correctly when compared with the main Felix execution path.

### Console Output Cleanup

User-facing PowerShell output for context build, spec creation, and interactive agent warnings now uses ASCII-only status markers such as `[OK]` and `[WARN]` so Windows PowerShell renders messages cleanly without mojibake.

### Cross-Platform CLI Bundle Build

The `Felix.Cli` build target that embeds `.felix` scripts into `felix-scripts.zip` now uses:

- the existing Windows fallback path with `cmd /c`
- a direct `pwsh` invocation on non-Windows platforms

This fixes Linux CI failures during `dotnet test` and `dotnet build` for the CLI project.

---

## Test Coverage

Validated with focused regression coverage and build/test verification:

- `.felix/tests/test-context-builder.ps1`
- `.felix/tests/test-agent-adapters.ps1`
- `.felix/tests/test-spec-builder.ps1`
- `dotnet test tests/Felix.Cli.Tests/Felix.Cli.Tests.csproj`

---

## Notes

- This is a patch release on top of `v1.1.0`.
- The release includes the previously committed context/output fixes plus the pending CLI packaging fix required for Linux CI.
