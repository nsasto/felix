---
name: felix
description: Use when setting up or running Felix 3 in a repository, selecting ready specs, configuring Claude Code/OpenCode/Codex/Grok Build, resuming Felix work, or reviewing Felix 2 to 3 migration behavior.
---

# Felix 3

Felix 3 is a breaking-change preview; Felix 2.2.0 is the final V2 release. Felix keeps the spec, plan, validation, review, work selection, and run record. A harness (Claude Code, OpenCode, Codex, or Grok Build) performs each agent phase. Read the repository's `AGENTS.md` and `features/felix3/README.md` before changing Felix workflows; the README is the canonical command and configuration reference.

## Set up a project

1. Check `felix --version` and `felix v3 --help` to confirm the installed CLI exposes V3.
2. For an existing Felix 2 project, run `felix v3 migrate` first. This is preview-only. It preserves V2 files and does not import V2 requirement or agent settings. Use `felix v3 migrate --harness <claude-code|opencode|codex|grok-build> --apply` only when you want to create the separate `.felix3/config.json`.
3. For a new project, run `felix v3 setup --harness <claude-code|opencode|codex|grok-build>`.
4. Install and authenticate the selected harness yourself, then edit `.felix3/config.json`. Configure independent validation commands before running work.
5. Keep V3 specs under the configured `work_source.specs_dir` (default `specs`). To queue a spec locally, give its Markdown frontmatter an `id`, a `title`, and `status: ready-for-agent`. Optional `depends_on: [S-0001]` entries are ready only after those specs are `completed` or `done`.

## Run work

- Run one explicit spec with `felix v3 run <id> --spec <path>`.
- Pick the next item with `felix v3 next`; continuously pick work with `felix v3 loop`.
- `next` and `loop` use the configured work source: local Markdown specs by default, or Felix Cloud when `work_source.provider` is `felix-cloud`.
- Inspect an active run with `felix v3 status <run-id>`. Resume a question or plan approval with `felix v3 resume <run-id> --answer <answer>`. Stop cooperatively with `felix v3 stop <run-id>`.

For optional Cloud run telemetry on a manually selected local spec, set `cloud_sync.enabled` and configure the project-scoped API key. `cloud_sync.upload_local_spec` defaults to false; enable it only when the spec should also be stored in Cloud. It uploads a Markdown file under `specs/` and creates a missing `S-0001`-style requirement mapping only when the filename code matches the run's requirement ID. Cloud-claimed specs already exist remotely and skip this upload. Live activity/output is separately opt-in, viewer-gated, transient, and not replayed or persisted; surfaced assistant text may still contain project context. See the README for configuration and privacy details.
- Felix marks local work complete only after its configured validation passes and the review approves. If the run pauses for a question or approval, resume the saved run; don't start a duplicate.

## Change Felix itself

Keep harness-specific process behavior in the provider adapter and shared workflow behavior in the Felix 3 coordinator. Update the work-source or harness contracts before adding another adapter. Add deterministic tests for lifecycle changes and update `features/felix3/V3_ROLLOUT.md` with verified gates and remaining limits. Do not tag V3 until the documented release acceptance gates pass.
