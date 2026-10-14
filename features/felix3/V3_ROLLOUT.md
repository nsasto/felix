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

V3 Cloud integration still needs to settle and verify:

- How the explicit Cloud agent UUID and harness/model/machine identity are provisioned and connected.
- Mapping V3 run lifecycle states to Cloud run and requirement states, especially awaiting-input, interruption, and blocked work.
- Cloud UI presentation of phase events, usage, questions, and review outcomes.
- A clear client-version policy and cutover so V2 users know when they must upgrade to retain Cloud access.
- Cross-machine recovery still needs a shared resumable run state or an explicit takeover protocol; agent ownership and claim status alone cannot move a local harness session or working tree.

The Felix Cloud working tree has extensive pre-existing uncommitted changes. The V3 work has touched only `app/backend/routers/sync.py`, its focused `test_work_allocation.py` tests, and `docs/SYNC_OPERATIONS.md`; do not stage or commit the unrelated Cloud changes.

## Implementation sequence

### 1. Freeze the V3 contracts

- Define the provider-neutral harness adapter input/output, session resume, cancellation, event, usage, question, and failure contracts.
- Define the work-item and work-source contracts separately from harnesses. Start with local specs and the existing Felix Cloud work source; keep GitHub/Jira integrations behind future adapters.
- Define stable run state transitions and which component is authoritative for completion.
- Keep raw provider output local by default; send only explicitly allowed summaries, events, and artifacts to Cloud.

**Exit condition:** contract docs and adapter tests describe identical behavior across Claude, OpenCode, and Codex.

**Current status:** harness, work-item, event, usage, and run-state contracts are defined and covered by the Felix 3 adapter suite. The initial Felix Cloud work-source adapter is implemented against these contracts and the existing API. Its same-checkout lifecycle is tested with a mock transport; live backend and multi-machine behavior remain unverified.

Inspection of the Felix Cloud backend confirms the adapter's `next`, `start`, `complete`, and `release` routes. The Cloud API now returns current claim status and accepts optional agent ownership on lifecycle calls; Felix 3 sends that owner ID and stops on a sticky in-progress claim when its local resumable state is missing. The focused Cloud work-allocation suite passes (40 tests) in a temporary Python environment. A live disposable-project smoke registered a Cloud agent, uploaded and claimed a test spec, started the run, then resumed it after configuring a narrow Claude Code `allowed_tools` matcher for the Python validation command. Planning, build, all 10 tests, review, and Cloud completion passed. Felix 3 now defaults to `https://api.runfelix.io`, matching the API used for the live run. The smoke exposed and fixed the active-run stop transition; complete is live-tested, while release and cross-machine takeover remain unverified.

### 2. Make the coordinator a real Felix CLI workflow

- Package the V3 coordinator and harness adapters with the release artifact.
- Provide consistent CLI commands for setup, running one spec, looping ready work, resuming a run, answering a question, approving/rejecting a plan, stopping a run, inspecting runs, and diagnostics.
- Keep harness installation/authentication outside Felix; validate availability and give actionable setup guidance.
- Use one versioned project config and one durable run directory. Avoid exposing implementation-only PowerShell entry points as the user workflow.
- Make setup safe for existing repositories: preserve source/spec files, explain the V2-to-V3 config break, and show the migration preview before changing Felix-managed files.

**Current status:** the packaged CLI exposes an initial `felix v3` bridge for setup, migration preview/apply, explicit-spec run, local or Cloud next/loop, resume, stop, and run status. `.felix/version.txt` and the CLI project now agree on `3.0.0-preview.1`. The standard Windows release packaging script produced `.release/felix-3.0.0-preview.1-win-x64.zip` and its checksum manifest. The archive's executable reported the preview version, its checksum matched the manifest, and an extracted archive setup installed the OpenCode config and skill. A separate packaged local named-spec run completed planning, build, independent validation, and review using a fake Codex CLI; this verifies Felix packaging/orchestration rather than provider authentication. Migration preview made no writes, and apply installed the OpenCode config and skill while preserving V2 requirements. The full CLI suite passes (137 tests). Local Markdown specs support readiness, dependency gating, an exclusive checkout lock, persisted resume state, and in-progress/completed status. Fake Claude and Codex local cycles pass through planning, build, validation, and review. The Felix 3 contract suite is wired into Windows CI. Live Felix-driven plan/build/validation/review smokes passed for Claude Code, Codex CLI 0.162.1 with `gpt-6-luna`, and OpenCode Go with `opencode-go/deepseek-v4-pro`. The OpenCode run completed a Taskbox title-search spec in an isolated copy of the disposable fixture; validation and independent review approved it. This Windows host's elevated sandbox refresh can fail when the desktop computer-use runtime holds `node_repl.exe` open (sharing violation, OS error 32). Felix supports the Codex-only `windows_sandbox` config override; setting it to `unelevated` for the project passed full plan/build/validation/review without changing global Codex configuration. The unelevated backend has weaker OS-level isolation, so phase `sandbox` restrictions should remain enabled.

**Exit condition:** a clean install can set up a project and run/resume a spec using each supported harness without importing Felix 2 agent-loop configuration.

### 3. Connect work selection and Cloud

- Implement the local ready-spec loop and explicit-spec path on the same work-item contract.
- Integrate Cloud claim/start/release/complete with leases and recovery. A claim must not be lost on question/approval waits or process interruption.
- The Felix Cloud source changes add claim-state responses and owner-checked lifecycle calls. A live production check on 2026-10-14 returned a claim without `status`, showing those changes are not deployed there. Felix 3 now fails closed on an unknown/missing claim status, persists `recovery_required`, and does not start, release, or invoke a harness. Do not use V3 Cloud claiming against production until Cloud is deployed and live-verified. Once deployed, `work/start` should transition only `reserved` and return 409 otherwise; Felix treats that as already-started only when it has the matching saved local claim and run state. `work/complete` is idempotent for `complete`, and `work/release` returns work to `planned`. Same-checkout recovery is covered by Felix's durable claim record and lock; cross-machine recovery still cannot resume the prior local run. Cloud needs a recoverable run/claim identifier and shared resumable state or an explicit takeover protocol before cross-machine recovery is supported.
- Add V3 client and harness metadata to Cloud run creation/events; agree on registration and identity with Cloud.
- Verify offline execution and outbox retry, idempotency, privacy defaults, and the final state reported to Cloud. Deterministic coverage checks Felix 3's buffered event retry and sync-http's JSONL disk outbox persistence/retry. A loopback TCP/HTTP smoke against the real sync-http client also forced an actual refused connection, then brought up a local endpoint and confirmed exactly-once event and run-finish delivery with the outbox drained. The production Cloud service's response to an actual network outage remains unverified.
- Update Cloud UI/API behavior only where the verified V3 contract requires it; preserve unrelated working-tree changes.

**Exit condition:** local and Cloud work sources both complete a ready item exactly once, recover safely after interruption, and show the same validated/reviewed outcome.

### 4. Put the Felix skill at the front door

- Ship a provider-neutral Felix skill in the repository and install it into supported agent skill locations during project setup.
- The skill must explain installation, setup, harness selection/authentication, choosing a spec, looping ready work, plan/spec iteration, questions/resume, validation/review, Cloud setup, troubleshooting, and the V2-to-V3 break.
- Keep the skill concise, link to canonical detailed docs, and test its commands against the shipped CLI. Do not duplicate stale V2 instructions into a V3 skill.

**Current status:** a provider-neutral skill is in `features/felix3/skills/felix/SKILL.md`, and root `AGENTS.md` points repository agents to it and the canonical V3 docs. Setup and migration apply install it into the configured Claude Code, OpenCode, or Codex project skill directory without overwriting existing skill or config files. Source installer smoke passed for all three paths; the embedded bundle includes the skill and its Codex install path passed. Claude, OpenCode, and Codex runtime skill discovery are verified: OpenCode Go loaded `.opencode/skills/felix/SKILL.md` through its native `skill` tool, and Codex CLI 0.162.1 read `.agents/skills/felix/SKILL.md`; both returned the documented named-spec command. The Codex smoke needed the project-scoped `windows.sandbox=unelevated` workaround for this host's sandbox refresh error while retaining Codex's `read-only` command sandbox.

**Exit condition:** an agent starting from the repository can discover the skill and complete the documented setup/run path without a human reconstructing hidden steps.

### 5. Release and documentation cutover

- Keep `v2.2.0` identified as the final V2 release. Prepare an annotated `v3.0.0` tag only after all V3 acceptance gates pass.
- Update the website/repository docs, install instructions, package/update behavior, release notes, examples, and Cloud docs together.
- Clearly label V3 as a breaking change, link to the latest V3 install/release, link to the final V2.2.0 release for existing users, and explain that users must upgrade their CLI to continue using Cloud after the cutover.
- Publish a compatibility matrix for CLI, project configuration, harnesses, and Cloud versions.

**Exit condition:** a V2 user can identify their current version, find the last V2 release, understand what breaks, and follow the V3 upgrade path before Cloud enforces the cutover.

**Documentation progress (2026-10-14):** the website CLI guide now clearly scopes its long-form command reference to Felix 2.2.0, labels Felix 3 as a breaking successor, links to the V3 preview guide/skill and final V2.2.0 release, and says the preview is not yet published. Felix Cloud's sync operations guide now documents claim lifecycle compatibility and advises upgrading before a future Cloud cutover. The compatibility matrix is in `COMPATIBILITY.md` and linked from the Felix 3 README, website guide, and Cloud guide. No cutover date or enforcement has been announced. Remaining: review the production website page, publish a downloadable V3 preview/release, and finish the Cloud recovery checks.

The compatibility matrix is now in `features/felix3/COMPATIBILITY.md` and linked from the Felix 3 README, website CLI guide, and Cloud sync guide. The website lockfile install succeeded; `npm run build`, `npm run lint`, and `git diff --check` pass, and the built JavaScript bundle contains the V3 version notice. Cloud's focused work-allocation suite passes 40 tests in an isolated environment with a dummy local-only database URL. The live production API returned S-9001 without `status`; Felix stopped before harness execution, and the test claim was released back to the queue. Felix now persists `recovery_required` and fails closed when Cloud omits or returns an unknown claim status; a regression covers no start, release, or harness call. The Cloud backend changes still need deployment and live verification. The Felix 3 preview package is locally built but not published; stable release and Cloud cutover remain gated on Cloud deployment/recovery checks and production page review.

## Release acceptance gates

- All deterministic C# and PowerShell tests pass in CI; live-provider diagnostics remain opt-in.
- Each harness passes adapter contract tests and a real smoke run in the sample project.
- Run lifecycle, questions, resume, plan approval, validation failure, review feedback, cancellation, and recovery are exercised end to end.
- Cloud sync is verified against the actual Cloud backend and UI, including claim/release behavior, privacy settings, offline outbox retry, and requirement completion.
- The sample project at `C:\dev\felix-test` can be reset to a known fixture and used for repeatable smoke runs.
- Release packaging contains the V3 CLI, adapters, examples, skill, and docs; version metadata agrees on `3.0.0`.
- V3 install and migration documentation is accurate before tagging; final V2.2.0 remains directly downloadable.

## Immediate next slice

The live disposable Cloud cycle completed requirement S-0001 and cleared the assignment; local run state is completed and its claim record was removed. The Claude usage record reports approximately $0.64 for planning/build/review, including the interrupted first build attempt. A second live Cloud smoke uploaded disposable requirement S-9001, claimed it through the Felix 3 adapter, released it, reclaimed it, and released it again; it is back in the planned queue for future disposable testing. The three harnesses now each have a live Felix-driven plan/build/validation/review smoke. The OpenCode Go / DeepSeek V4 Pro run completed a title-search spec in an isolated Taskbox copy, with its independent validation passing and review approving; the copy was removed and the sample checkout's existing uncommitted fixture changes were preserved. OpenCode and Codex both loaded the Felix skill from their documented project skill directories and returned the named-spec command. The Codex smoke used the project-scoped `windows.sandbox=unelevated` workaround with its command sandbox kept `read-only`. The Cloud smoke exposed coordinator details now covered or fixed: active runs can transition to `stop-requested`, phase-scoped `allowed_tools` is forwarded to Claude Code without broad permission bypass, failed event sends retain their buffer until a successful retry, and Codex now handles the optional Windows sandbox override being omitted. The packaged preview completed setup, migration, skill installation, V2-file preservation, and a fake-provider local spec cycle with validation and review. Standard Windows packaging produced the version-aligned `3.0.0-preview.1` archive, whose checksum and extracted setup were verified. A local loopback network smoke confirmed the sync-http outbox survives a refused connection and drains after reconnection; the production Cloud service has not been outage-tested. Cross-machine takeover remains unsupported until Cloud exposes a recoverable run/claim identity or explicit takeover protocol. Release readiness still requires CI confirmation, production Cloud outage/recovery verification, final stable version selection, production website build/page review, and publication of the V3 preview/release.

**Regression results (2026-10-14):** Felix CLI tests passed (137); Felix 3 PowerShell tests passed after adding a default-Codex-config full-cycle regression; Phase B–H passed (61, 35, 34, 46, 30, 53, and 45 checks); Graphify passed (21). The packaged CLI smoke passed setup, migration preview/apply, skill installation, V2-data preservation, and a local plan/build/validation/review cycle. Standard `package-release.ps1 -Rid win-x64 -SkipInstaller` produced `felix-3.0.0-preview.1-win-x64.zip`; version, checksum, and extracted setup passed. The sync-http reconnect smoke passed using a local HTTP endpoint after a real refused connection; Cloud service outage behavior still needs a live backend check. The package check exposed and fixed an optional `windows_sandbox` binding error: Codex configs that omit the override now run without passing an empty value to the adapter. Phase H exposed a culture-sensitive lease expiry parse: PowerShell deserialized ISO timestamps to `DateTime`, then the lease check reparsed the localized value. The validity check now handles `DateTime` and invariant timestamp strings directly, with a disk round-trip regression test.
