# Felix 3.0.0 Preview 2 Release Notes

Date: 2026-11-04

Felix 3 is a breaking-change successor to Felix 2. Felix 2.2.0 remains the last V2 release. This is an updated V3 preview for evaluation, not a stable release.

## Highlights

- Completed and verified Felix 3 workflows for Claude Code, OpenCode, Codex CLI, and Grok Build.
- Added transient, viewer-gated Cloud activity and surfaced assistant output. Streamed content is not retained by Cloud; local Felix run artifacts remain the durable record.
- Deployed the matching Felix Cloud endpoints and Orchestration live-output view.
- Brought the Felix 3 workflow, skill, compatibility, and release guidance up to date.

## Verification

- Felix CLI suite: 156 passed.
- Felix 3 PowerShell contract suite: passed across the four harness adapters, work-source lifecycle, streamed events and usage, questions, approvals, cancellation, privacy, retries, and resume behavior.
- Windows Grok 4.6 workflow: plan, build, independent validation, and review completed successfully. A local Cloud SSE observer received surfaced text and tool activity; durable Cloud events contained no output text.
- Production Cloud health is healthy, and the authenticated live activity route is present in the deployed API schema.
- Windows self-contained release packaging completed successfully. The hosted release workflow creates the cross-platform assets and Windows installer.

## Breaking Changes

- Felix 3 uses a separate `.felix3/config.json`; Felix 2 project configuration, requirements, and agent profiles are not imported into the V3 workflow.
- Felix 3 delegates planning/build/review turns to the configured harness instead of using the Felix 2 agent loop.
- Users who need Felix Cloud after the V3 Cloud cutover must upgrade to a V3 CLI. The cutover date and supported Cloud version will be announced with the final V3 release.

## Known Limitations

- Felix 3 remains a preview and is not a stable-release promise.
- Production Cloud health and route availability are verified, but a real production run has not yet been observed in the browser live-output panel. Local Cloud SSE and browser rendering have been verified separately.
- Cloud live fan-out is process-local and currently requires one backend instance; do not scale horizontally until shared transient fan-out is implemented.
- Cross-machine recovery of an active Cloud claim is not supported; resume from the checkout that holds the saved run state.
- GitHub Issues and Jira work-source adapters are not included in this preview.

## Upgrade and Migration

For a V2 project, run `felix v3 migrate` to preview the separate V3 configuration, then add `--harness <claude-code|opencode|codex|grok-build> --apply` after reviewing it. Migration preserves V2 files and does not import their requirement or agent settings. For a new V3 project, run `felix v3 setup --harness <provider>`.

See `features/felix3/README.md` and `features/felix3/skills/felix/SKILL.md` for setup and workflow details. Existing V2 users can continue to use Felix 2.2.0 from its release tag until the Cloud cutover is announced.
