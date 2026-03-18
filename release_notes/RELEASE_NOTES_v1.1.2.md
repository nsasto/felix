# Release Notes - v1.1.2

**Release Date:** March 18, 2026

## Highlights

- Fixed the Unix update helper so CLI tests and update flows do not hang when invoked with parent PID `0`
- Rolls forward the `v1.1.1` context-builder, console output, and cross-platform packaging fixes into a new tagged release

---

## Fixes

### Unix Update Helper Wait Loop

The Unix update helper previously waited on the parent process with:

- `kill -0 "$PARENT_PID"`

When invoked with parent PID `0`, some Unix environments treat that as the current process group, which can cause the helper to wait indefinitely.

The helper now:

- normalizes invalid or non-numeric parent PID values
- only enters the wait loop when the parent PID is a positive integer

This fixes the stalled Unix helper execution seen in CLI test runs and makes the updater more robust for edge cases.

### Included From v1.1.1

This release also includes the fixes previously shipped on `main` and tagged as `v1.1.1`, including:

- context-builder agent invocation fixes
- verbose pass-through for `felix context build`
- plain-text Droid success response rendering
- ASCII-only console status output for Windows PowerShell compatibility
- cross-platform CLI bundle packaging during build and test

---

## Test Coverage

Validated with:

- `dotnet test tests/Felix.Cli.Tests/Felix.Cli.Tests.csproj`
- `.felix/tests/test-context-builder.ps1`
- `.felix/tests/test-agent-adapters.ps1`
- `.felix/tests/test-spec-builder.ps1`

---

## Notes

- This patch release supersedes `v1.1.1` for consumers who need the Unix helper fix in a tagged release.