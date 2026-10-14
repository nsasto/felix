# Felix 3.0.0 Preview 1 Release Notes

Date: 2026-10-14

Felix 3 is a breaking-change successor to Felix 2. Felix 2.2.0 remains the last V2 release. This preview is for evaluation and is not the final V3 release.

## Highlights

- Added a provider-neutral coordinator for Claude Code, OpenCode, and Codex harnesses.
- Added local Markdown spec setup, migration preview/apply, explicit-spec execution, ready-work selection, resumable runs, independent validation, and review gates.
- Added an installable Felix skill for the supported harnesses.
- Added an initial Felix Cloud work-source adapter with project-scoped agent identity, claim lifecycle, event reporting, and a durable local outbox.

## Breaking Changes

- Felix 3 uses a separate `.felix3/config.json`; Felix 2 project configuration, requirements, and agent profiles are not imported into the V3 workflow.
- Felix 3 delegates planning/build/review turns to the configured harness instead of using the Felix 2 agent loop.
- Users who need Felix Cloud after the V3 Cloud cutover must upgrade to a V3 CLI. The cutover date and supported Cloud version will be announced with the final V3 release.

## Known Limitations

- Cross-machine recovery of an active Cloud claim is not supported; resume from the checkout that holds the saved run state.
- GitHub Issues and Jira work-source adapters are not included in this preview.
- Website and Cloud documentation cutover is not complete. Do not treat this preview as the final supported V3 release.

## Upgrade and Migration

For a V2 project, `felix v3 migrate` previews the separate V3 configuration. Add `--harness <claude-code|opencode|codex> --apply` to create it. Migration preserves V2 files and does not import their requirement or agent settings. For a new project, run `felix v3 setup --harness <claude-code|opencode|codex>`.

See `features/felix3/README.md` and `features/felix3/skills/felix/SKILL.md` for preview setup and workflow details. Existing V2 users can continue to use Felix 2.2.0 from its release tag until the Cloud cutover is announced.
