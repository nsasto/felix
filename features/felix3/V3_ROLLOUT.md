# Felix 3 rollout plan

Status: V3 implementation is authorized; release work has not started.
Last Felix 2 release: `v2.2.0`.

## Product boundary

Felix 3 should keep the useful orchestration Felix owns and delegate the coding loop to the selected harness. Harnesses such as Claude Code, OpenCode, and Codex own their native agent turns, tool use, and subagents. Felix owns work selection, durable specs and plans, phase progression, human questions and approvals, independent validation, review decisions, run history, and reporting to the work source.

Felix 3 is a breaking major release. Felix 2.2.0 remains the last supported V2 release and stays available by its release tag. Do not imply that V2 project configuration or the old agent loop runs unchanged under V3. Keep user source files and specs usable; make any project-state migration explicit and reviewable.

## Current baseline

The isolated `features/felix3` prototype already has Claude, OpenCode, and Codex harness adapters; planning/build/review phases; run snapshots and event journals; resume, cancellation, questions, and plan approval; independent validation; usage capture; and opt-in Cloud event/artifact sync.

The prototype currently runs one explicitly named spec. It is not in the packaged CLI, does not claim work from a tracker, and derives its Cloud agent key from Felix 2's `.felix/agents.json` or a manually configured key. Treat this as prototype capability, not a V3-ready end-user workflow.

## Cloud compatibility findings

The Cloud backend already exposes project-scoped run creation, batched events, run completion, artifact uploads, and work-source endpoints for next/start/complete/release. Its run-event payload accepts arbitrary JSON, which can carry Felix 3 phase, harness, usage, and local-run metadata without an immediate database migration.

V3 integration still needs to settle and verify:

- How V3 registers its harness/model/machine identity and obtains the Cloud agent identity needed for claiming work.
- Whether Cloud work claims can use the V3 agent identity directly or need a small API extension.
- Mapping V3 run lifecycle states to Cloud run and requirement states, especially awaiting-input, interruption, and blocked work.
- Cloud UI presentation of phase events, usage, questions, and review outcomes.
- A clear client-version policy and cutover so V2 users know when they must upgrade to retain Cloud access.

The Felix Cloud working tree currently has extensive uncommitted changes. It was inspected read-only; preserve those changes and coordinate Cloud edits with that checkout's owner/workflow.

## Implementation sequence

### 1. Freeze the V3 contracts

- Define the provider-neutral harness adapter input/output, session resume, cancellation, event, usage, question, and failure contracts.
- Define the work-item and work-source contracts separately from harnesses. Start with local specs and the existing Felix Cloud work source; keep GitHub/Jira integrations behind future adapters.
- Define stable run state transitions and which component is authoritative for completion.
- Keep raw provider output local by default; send only explicitly allowed summaries, events, and artifacts to Cloud.

**Exit condition:** contract docs and adapter tests describe identical behavior across Claude, OpenCode, and Codex.

### 2. Make the coordinator a real Felix CLI workflow

- Package the V3 coordinator and harness adapters with the release artifact.
- Provide consistent CLI commands for setup, running one spec, looping ready work, resuming a run, answering a question, approving/rejecting a plan, stopping a run, inspecting runs, and diagnostics.
- Keep harness installation/authentication outside Felix; validate availability and give actionable setup guidance.
- Use one versioned project config and one durable run directory. Avoid exposing implementation-only PowerShell entry points as the user workflow.
- Make setup safe for existing repositories: preserve source/spec files, explain the V2-to-V3 config break, and show the migration preview before changing Felix-managed files.

**Exit condition:** a clean install can set up a project and run/resume a spec using each supported harness without importing Felix 2 agent-loop configuration.

### 3. Connect work selection and Cloud

- Implement the local ready-spec loop and explicit-spec path on the same work-item contract.
- Integrate Cloud claim/start/release/complete with leases and recovery. A claim must not be lost on question/approval waits or process interruption.
- Add V3 client and harness metadata to Cloud run creation/events; agree on registration and identity with Cloud.
- Verify offline execution and outbox retry, idempotency, privacy defaults, and the final state reported to Cloud.
- Update Cloud UI/API behavior only where the verified V3 contract requires it; preserve unrelated working-tree changes.

**Exit condition:** local and Cloud work sources both complete a ready item exactly once, recover safely after interruption, and show the same validated/reviewed outcome.

### 4. Put the Felix skill at the front door

- Ship a provider-neutral Felix skill in the repository and install it into supported agent skill locations during project setup.
- The skill must explain installation, setup, harness selection/authentication, choosing a spec, looping ready work, plan/spec iteration, questions/resume, validation/review, Cloud setup, troubleshooting, and the V2-to-V3 break.
- Keep the skill concise, link to canonical detailed docs, and test its commands against the shipped CLI. Do not duplicate stale V2 instructions into a V3 skill.

**Exit condition:** an agent starting from the repository can discover the skill and complete the documented setup/run path without a human reconstructing hidden steps.

### 5. Release and documentation cutover

- Keep `v2.2.0` identified as the final V2 release. Prepare an annotated `v3.0.0` tag only after all V3 acceptance gates pass.
- Update the website/repository docs, install instructions, package/update behavior, release notes, examples, and Cloud docs together.
- Clearly label V3 as a breaking change, link to the latest V3 install/release, link to the final V2.2.0 release for existing users, and explain that users must upgrade their CLI to continue using Cloud after the cutover.
- Publish a compatibility matrix for CLI, project configuration, harnesses, and Cloud versions.

**Exit condition:** a V2 user can identify their current version, find the last V2 release, understand what breaks, and follow the V3 upgrade path before Cloud enforces the cutover.

## Release acceptance gates

- All deterministic C# and PowerShell tests pass in CI; live-provider diagnostics remain opt-in.
- Each harness passes adapter contract tests and a real smoke run in the sample project.
- Run lifecycle, questions, resume, plan approval, validation failure, review feedback, cancellation, and recovery are exercised end to end.
- Cloud sync is verified against the actual Cloud backend and UI, including claim/release behavior, privacy settings, offline outbox retry, and requirement completion.
- The sample project at `C:\dev\felix-test` can be reset to a known fixture and used for repeatable smoke runs.
- Release packaging contains the V3 CLI, adapters, examples, skill, and docs; version metadata agrees on `3.0.0`.
- V3 install and migration documentation is accurate before tagging; final V2.2.0 remains directly downloadable.

## Immediate next slice

Implement the Cloud work-source adapter against the contract above, including claim ownership, local spec materialization, and safe start/complete/release behavior. This closes the largest gap between the current single-spec prototype and the requested autonomous plan/build/review cycle. The packaged CLI and agent-facing skill should follow against the now-stable command and configuration surface.
