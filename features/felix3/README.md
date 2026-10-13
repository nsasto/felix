# Felix 3 — Harness Coordinator

Felix 3 is the active target for the next major Felix release. This directory contains the harness/coordinator prototype; it is not yet the packaged CLI workflow. Follow [V3_ROLLOUT.md](V3_ROLLOUT.md) for the migration sequence and release acceptance gates.

## Harness adapters and task coordinator

`claude/Invoke-ClaudeHarness.ps1` runs Claude Code in headless mode. `opencode/Invoke-OpenCodeHarness.ps1` runs OpenCode's native `opencode run --format json` loop. `codex/Invoke-CodexHarness.ps1` runs Codex CLI's `codex exec --json` loop. Each adapter streams raw output to its phase artifact and returns a normalized run result. Felix 3 appends sequenced normalized events to `events.jsonl` and prints concise phase/tool progress. The selected harness owns its internal tool use, agent turns, and subagents. The caller supplies phase prompts; Felix 3 retains the work item, spec, plan, phase transitions, independent validation, and review decision.

All three adapters support planning, building, and reviewing, session resume, event capture, usage reporting when available, and run artifacts. `Invoke-Felix3Task.ps1` coordinates one manually supplied spec through planning, building, independent validation, and review. It does not select work from or update a tracker yet. A successful harness process is only a successful harness run; Felix 3 marks a task complete only when its plan exists, configured validation commands pass, and review approves.

Install and authenticate the harness you choose. Claude Code uses the root example config. OpenCode uses `opencode/felix3-opencode.config.example.json` and the provided agent profiles. Codex CLI uses `codex/felix3-codex.config.example.json`; it honors the user's Codex CLI authentication and configuration. Its sample policy uses read-only planning/review and workspace-write building, with approval prompts disabled for non-interactive execution. Sandbox restrictions still apply, and an operation outside policy fails back to the model. Copy the selected config into the target project's `.felix3/config.json`, then add its validation commands:

```powershell
New-Item -ItemType Directory -Force .felix3 | Out-Null
Copy-Item C:\dev\felix\features\felix3\opencode\felix3-opencode.config.example.json .felix3\config.json
New-Item -ItemType Directory -Force .opencode\agents | Out-Null
Copy-Item C:\dev\felix\features\felix3\opencode\agents\*.md .opencode\agents\
```

Validation commands use an executable plus an argument array, not a shell command string:

```json
"validation": {
  "require_at_least_one_command": true,
  "commands": [
    { "name": "tests", "executable": "dotnet", "args": ["test", "tests/Felix.Cli.Tests/"] }
  ]
}
```

Run a single requirement spec:

```powershell
. C:\dev\felix\features\felix3\Invoke-Felix3Task.ps1
$result = Invoke-Felix3Task -ProjectPath (Get-Location).Path -RequirementId S-0001 -SpecPath specs\S-0001.md
$result | Format-List
```

Each execution creates `.felix3/runs/<run-id>/` with a spec and work-item snapshot, `plan.md`, phase-level raw harness output and normalized results, `events.jsonl`, `usage.json`, `validation.json`, `review.json`, and atomic `state.json` snapshots. Partial harness output remains available if a process is interrupted. Provider output files may contain sensitive text and stay local by default. Completed runs older than `artifacts.local_retention_days` (30 days in the examples) are pruned when the next task starts. Blocked, interrupted, and awaiting-input runs are preserved.

If an agent needs a decision, it returns a structured Felix question and the run enters `awaiting-input`. Read `question.json`, then resume the same harness session:

```powershell
Resume-Felix3Task -ProjectPath (Get-Location).Path -RunId '<run-id>' -Answer 'Use the existing JSON format.'
```

When `workflow.require_plan_approval` is enabled, approve or reject the saved plan with `-Answer approve` or `-Answer reject`. Stop an active harness run with a cooperative cancellation request, then resume it later:

```powershell
Stop-Felix3Task -ProjectPath (Get-Location).Path -RunId '<run-id>'
Resume-Felix3Task -ProjectPath (Get-Location).Path -RunId '<run-id>'
```

If the coordinator exits unexpectedly, the saved active phase and the session IDs in `events.jsonl` let `Resume-Felix3Task` continue from that phase. Resume keeps the existing run ID and artifacts.

`usage.json` stores per-invocation provider-reported input/output/total, cached and reasoning token counts, cost when supplied, duration, model, harness, and session. Missing values stay `null`; Felix does not estimate costs. Build retries are separate phase instances, so reported usage is counted once per invocation. Per-phase `session_policy` controls whether build retries and review cycles continue that phase's previous session (`resume`) or start fresh; answering a question or recovering an interrupted phase always resumes the session needed to continue that exact invocation.

### Optional cloud sync

Felix 3 uses Felix's existing HTTP sync transport when cloud sync is enabled. Enable it with `cloud_sync.enabled` or `FELIX_SYNC_ENABLED=true`; set `FELIX_SYNC_URL` and `FELIX_SYNC_KEY` as needed. Felix can infer the agent key from `.felix/agents.json` for the selected harness, or use `FELIX_SYNC_AGENT_KEY` / `cloud_sync.agent_key`. Failed deliveries stay in `.felix3/outbox` for retry.

Cloud sync sends run/phase/tool milestones and normalized usage. Raw prompts, full transcripts, specs, and question text are not sent by default. Set `cloud_sync.include_question_text=true` to include question wording. Artifact upload is opt-in per file through `cloud_sync.artifacts`, for example `['plan.md','review.json','usage.json']`. Cloud sync metadata and outbox files contain no provider credentials.

`permission_mode` is specific to Claude Code; the example uses its read-only `plan` mode for planning and review, and `acceptEdits` for building. OpenCode uses phase-specific agents; the provided plan and review profiles deny edits, while the build profile has edit and shell tools. Its example model is `opencode-go/deepseek-v4-pro`. OpenCode's CLI supports JSONL events, model/agent selection, and session continuation; see the [OpenCode CLI docs](https://opencode.ai/docs/cli/) and [OpenCode Go model list](https://opencode.ai/docs/go/). Codex supports JSONL event output and session continuation; usage is persisted when reported, while cost is currently unknown. Felix uses a structured question marker and resume workflow, and also converts supported native OpenCode/Claude question-tool requests into that workflow. Keep provider credentials in each harness's credential store or environment, never in Felix config or run artifacts.

## Intended cycle

1. Claim a ready work item from a work-source adapter.
2. Persist a snapshot of the work item and its acceptance criteria.
3. Ask the planning phase to inspect the repository and write a detailed, durable plan.
4. Check that the plan covers the acceptance criteria and is ready to build.
5. Ask the building phase to execute the plan using the selected harness's native agent loop.
6. Run repo-defined validation outside the harness.
7. Ask a review phase to inspect the implementation; route requested changes back to building.
8. Mark the work item complete only after the independent gates pass, then report evidence to the source tracker.

## Adapter contract

Each harness adapter accepts a working directory, phase, prompt, and run directory. It returns a stable result containing process status, session ID, result text, usage/cost metadata when provided, and artifact paths. Raw CLI output is retained so run reports can inspect the original evidence. OpenCode returns planning and review as final text; Felix persists those responses to the contract artifact paths, allowing its plan/review agents to remain read-only.

Claude Code CLI flags and response fields follow Anthropic's [CLI reference](https://docs.anthropic.com/en/docs/claude-code/cli-usage) and [SDK documentation](https://docs.anthropic.com/en/docs/claude-code/sdk).

## Current scope and completion boundary

This remains an isolated Felix 3 slice. It handles one explicit spec at a time; it does not claim/transition GitHub Issues or Jira work or migrate existing Felix runtime behavior. The current Felix engine remains unchanged. Claude, OpenCode, and Codex adapters should be exercised against the installed CLI versions and target backend before wider rollout.
