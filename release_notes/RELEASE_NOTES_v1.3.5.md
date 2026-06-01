# Release Notes v1.3.5

Date: 2026-04-13

## Highlights

- Added configurable requirement conventions through `.felix/config.json`, including requirement ID prefix, specs directory, agents guide path, and context file list.
- Updated Felix command flows to honor configured paths and prefixes across spec management, context management, and prompt generation.
- Extended setup defaults and status surfaces so project conventions are visible and editable without hand-discovering engine assumptions.

## Fixes

- Removed hardcoded `S-0001`, `specs/`, `AGENTS.md`, and `CONTEXT.md` assumptions from major C# and PowerShell entry points.
- Corrected prompt/context injection so agents are directed to the configured operational guide and configured context files instead of fixed filenames.
- Improved spec sync and context sync path handling so client-side uploads and downloads follow configured project conventions.
- Added regression coverage for configurable paths, configurable prefixes, and context builder/spec builder helper behavior.

## Breaking Changes

- Projects that rely on hardcoded file names in custom extensions or external tooling should update those integrations to read `.felix/config.json` instead of assuming `specs/`, `AGENTS.md`, or `CONTEXT.md`.
