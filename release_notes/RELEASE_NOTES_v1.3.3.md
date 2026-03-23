# Release Notes v1.3.3

Date: 2026-03-23

## Highlights

- Improved Copilot adapter reliability by switching prompt transport to stdin, avoiding Windows command-line length limits.
- Hardened completion parsing to extract the final valid JSON payload when streamed output includes interim non-JSON text.
- Tightened planning and building prompt contracts to require a single JSON object response with explicit completion signaling.
- Expanded observability with prompt artifact capture and parser logs to aid debugging and run diagnostics.

## Fixes

- Fixed Copilot invocation mode where large prompts could be passed as command arguments.
- Fixed JSON extraction logic for mixed output streams using balanced-brace parsing.
- Added informational logging when mixed output is reduced to a final JSON completion payload.
- Added and propagated `--debug` support through run entry points and CLI header display.

## Breaking Changes

- None.
