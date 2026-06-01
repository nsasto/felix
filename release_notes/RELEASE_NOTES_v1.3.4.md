# Release Notes v1.3.4

Date: 2026-03-25

## Highlights

- Rebuilt the Felix TUI around a more stable fixed-shell interaction model with a persistent command bar and improved transcript behavior.
- Expanded the TUI command surface to reflect the supported CLI command tree, including nested command families such as `spec`, `agent`, `procs`, and `context`.
- Made `felix` with no arguments open the dashboard/TUI by default for a faster interactive entry point.

## Fixes

- Fixed command suggestion and execution flow so keyboard selection populates the textbox and Enter runs exactly what is typed.
- Improved TUI transcript rendering, scrolling, resume behavior, and body/footer redraw handling to reduce corruption and flicker.
- Restored proper command routing for `spec list` in the PowerShell dispatcher and improved captured command output visibility.
- Added Felix version information to the TUI welcome panel under the current agent details.

## Breaking Changes

- None.
