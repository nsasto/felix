# Release Notes v2.1.0

Date: 2026-06-23

## Highlights

Felix v2.1 adds optional Graphify integration for token-efficient codebase investigation. Graphify remains an external dependency and source of truth for graph creation and querying; Felix adds configuration, setup workflow, skill guidance, command wrappers, documentation, and safe team graph refresh automation.

## New Features

- Added `graphify` configuration defaults for local and team graph modes.
- Added `felix graphify` / `felix graph` commands:
  - `status`
  - `setup --local`
  - `setup --team`
  - `build`
  - `update`
  - `query`
  - `path`
  - `explain`
- Added the `graphify-investigator` Felix skill, loaded only when Graphify is enabled.
- Added team-mode support for committed `graphify-out/` maps, recommended `.gitignore` entries, post-commit hook setup, and merge-driver status checks.
- Added optional Felix auto chore commits for graph refreshes when only the configured team graph directory changed after a requirement commit.

## Documentation

- Added `docs/GRAPHIFY.md` with local mode, team mode, setup, hook behavior, auto refresh commits, and troubleshooting.
- Updated documentation hub, configuration reference, skills docs, search docs, and AGENTS operational commands with Graphify references.

## Test Coverage

- Added `tests/Test-Graphify.ps1` for Graphify defaults, setup helpers, skill loading, status detection, wrapper shims, and auto-commit eligibility.
- Added C# CLI coverage for Graphify command registration and config defaults.

## Breaking Changes

- None.

## Upgrade

```powershell
felix update
```

Graphify is optional. To enable it in a repo:

```powershell
felix graphify setup --local
# or
felix graphify setup --team
```