# Felix 3 contracts

These contracts separate harness execution from work selection and define the durable evidence that Felix owns. They are versioned independently so the packaged CLI and future source adapters can evolve without copying provider-specific behavior into the coordinator.

## Work item

Every source adapter returns one normalized work item. The first source adapters are an explicit local spec and Felix Cloud; GitHub and Jira remain future adapters.

```json
{
  "schema": "felix3-work-item-v1",
  "id": "S-0001",
  "title": "Example requirement",
  "source": { "provider": "manual-spec", "id": "S-0001" },
  "priority": null,
  "depends_on": [],
  "spec_path": "specs/S-0001.md",
  "spec_sha256": "sha256 of the exact spec snapshot"
}
```

`id` is the stable identity supplied by the source; `source.id` is that source's key. `spec_path` is project-relative and points to the local materialized spec. The coordinator snapshots the spec text separately as `spec.md`; `spec_sha256` binds the work item to that exact input. A source may add source-specific fields in future schema versions but must not change these meanings.

A work-source adapter has four operations: `ClaimNext` returns one work item or no work; `Start` acknowledges that a claimed item is entering execution; `Complete` reports success only after validation and review pass; `Release` returns a claim after an unrecoverable block or explicit cancellation. A source that does not support claims may treat `Start`, `Complete`, and `Release` as local state operations, but must retain the same completion rule. Human-question and plan-approval waits are resumable and retain the claim; they are not releases.

The Cloud adapter maps these operations to `GET /api/sync/work/next`, `POST /api/sync/work/start`, `POST /api/sync/work/complete`, and `POST /api/sync/work/release`. Cloud's claim response provides requirement code, title, spec path, priority, and dependencies. The adapter resolves/materializes the spec before returning the normalized work item. API-key scope selects the Cloud project. Agent identity and claim ownership must be established before this adapter ships; do not assume a Felix 2 profile key is a V3 registration contract.

## Harness invocation and result

Each adapter accepts the same logical inputs: phase (`planning`, `building`, or `reviewing`), working directory, prompt, run directory, optional session ID, optional cancellation token, and optional event sink. Provider-specific settings stay in the selected harness config.

Each adapter returns these fields, even when the provider has no value for one of them:

| Field | Meaning |
|---|---|
| `Harness` | Canonical provider id: `claude-code`, `opencode`, or `codex` |
| `Phase` | Requested workflow phase |
| `Succeeded` | Harness completed the requested turn successfully |
| `Interrupted` | Felix cancellation stopped the process |
| `NeedsInput` | Harness requested human input |
| `ExitCode` | Process exit code, or null if unavailable |
| `SessionId` | Provider session handle, or null |
| `ResultText`, `Error` | Final response and failure summary; either may be empty/null |
| `Usage`, `CostUsd`, `Turns` | Provider-reported metadata; unavailable values remain null |
| `ResultPath`, `RawOutputPath`, `StderrPath`, `SessionPath` | Local artifact paths; session path may be null |

The three outcome flags are mutually consistent: an adapter cannot report success while interrupted or waiting for input. A successful result has exit code 0 or null. Missing usage is unknown, not zero. A session id is a provider handle and is only resumed by the same harness and phase policy.

Felix retains the raw stdout/stderr and normalized results locally. Cloud receives only allowlisted lifecycle/tool summaries and normalized metadata. Question wording and artifacts require explicit opt-in; prompts, specs, and full transcripts are never sent by default. Credentials never enter run artifacts.

## Events and usage

Run events use `felix3-event-v1`: `event_id`, `run_id`, monotonically increasing `seq`, ISO-8601 UTC `timestamp`, `kind`, nullable `phase` and `harness`, sanitized `summary`, and nullable structured `payload`. Appending an event is local-first. Cloud delivery is best-effort and retryable from the outbox.

Usage records use `felix3-usage-v1`. Preserve the provider payload for diagnosis, normalize known token and cost fields, keep unknown values null, and count each phase invocation once using `phase_instance` as its stable key.

## Run state

Active states are `planning`, `building`, and `reviewing`. `awaiting-input` and `awaiting-plan-approval` preserve the active phase and resume context. `stop-requested` is a cooperative cancellation request. `interrupted` is recoverable. `completed` and `blocked` are terminal outcomes for the current run; a new retry creates a new run rather than reopening a terminal record.

Allowed transitions:

- `planning` → `building`, `awaiting-input`, `awaiting-plan-approval`, `interrupted`, `blocked`
- `building` → `building` (retry), `reviewing`, `awaiting-input`, `interrupted`, `blocked`
- `reviewing` → `building` (review fixes), `completed`, `awaiting-input`, `interrupted`, `blocked`
- `awaiting-input` → its saved phase or `blocked`
- `awaiting-plan-approval` → `building` or `blocked`
- `stop-requested` → its saved phase, `interrupted`, or `blocked`
- `interrupted` → its saved phase or `blocked`

`completed` requires a persisted plan, passing independently executed validation, and an approved review. Harness exit code zero alone never completes a work item. The work source is marked complete only after Felix reaches `completed`; blocked work is released or left for an explicit human decision according to source policy.

## Compatibility rule

A contract change that alters field meaning or state transitions increments its schema version. Additive optional fields may be introduced within the current version. Adapters must pass the shared contract tests before the coordinator accepts their results.
