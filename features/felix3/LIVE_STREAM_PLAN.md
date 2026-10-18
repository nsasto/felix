# Felix 3 live run stream plan

**Scope:** Stream a bounded view of surfaced harness output and safe activity to Felix Cloud while a Felix 3 run is active. Full run artifacts remain local; Cloud live content is transient.

## Current status

The stream has been verified in a browser during a real Grok Build run against the disposable local Felix Cloud backend on port 8081. Run `S-0001-20261016-091105-8341636c` streamed surfaced assistant text and tool lifecycle events into the attached Grok agent panel while active. Planning completed, the first build attempt failed on a denied terminal call, the second build passed, and independent validation passed. Review returned an approval object but Felix correctly blocked the run because review's blanket `deny Bash` also denied read-only Git inspection. Reported provider usage was $0.27259976 over 684.52 seconds. The Grok sample now permits only scoped `git status`, `git diff`, and `git log` commands in review; a fresh real run is still needed to verify that fix. No production Cloud service was contacted. The test project's Felix 3 config was restored byte-for-byte after the run.

Felix sends normalized live messages through an asynchronous named-pipe write with at most one pending write; a slow reader drops transient messages rather than holding up local execution. The Cloud API key is not included in the pipe configure frame. The CLI publisher independently reads the configured key; the coordinator retains credentials needed for existing metadata sync, while harness child processes have sync credentials removed. Cloud persists lifecycle/action metadata; live text is delivered only to connected run viewers and is not replayed.

The earlier Claude SSE smoke remains valid, but an additional approved Claude attempt stopped before Cloud run creation because local backend startup failed when Python's Windows `cp1252` console could not print a checkmark. The backend was restarted successfully with `PYTHONIOENCODING=utf-8`; that Claude attempt was interrupted and did not verify browser rendering. The Grok browser smoke did verify the panel. For this local setup, `FELIX_DEV_API_PROXY_TARGET=http://127.0.0.1:8081` proxies API, health, and WebSocket requests, and `VITE_API_URL=http://127.0.0.1:3004` points the UI to its same-origin proxy. Live content is not replayed after a run completes.

**Verification:** Felix 3 PowerShell contract suite passes, including a stalled-pipe-reader regression; Felix CLI suite passes 156/156 when run outside the restricted testhost environment; focused live-publisher tests passed 15/15 previously. Cloud backend passes 456 with 1 skipped; Cloud frontend previously passed 151, and the live-output component suite passes 11/11 on the current tree. Frontend typecheck and production build pass. The current Release win-x64 single-file executable was rebuilt from this tree and passed standalone `felix v3 --help` and `felix v3 setup --harness opencode` in a fresh project without V2 sidecars; its output is under `.tmp/release-smoke-8979167b0c694073a5a51837f33dfca2`. No `.release` archive or checksum was overwritten.
## Stage completion audit

| Plan stage | Current evidence | Status |
|---|---|---|
| 0. Protocol and topology | Event/transport contracts, limits, opt-in, and ownership checks are documented. Render source now pins one instance and one Uvicorn worker; its docs state that existing autoscaling can survive Blueprint updates and WebSocket handshakes are randomly assigned across instances. Verify the deployed scaling mode; otherwise add cross-instance fan-out before release. Render request logs document method/status/URL fields, but app and external trace logging still need review. | Code contract complete; runtime settings open |
| 1. Local event fan-out | Shared adapter projections, named-pipe publisher, bounded queue, slow-reader test, and disabled/unwatched/disconnected coverage pass in Felix tests. | Complete locally |
| 2. Cloud transient transport | Authenticated WebSocket/SSE, viewer demand, allowlisted events, rate/size limits, and no-persistence tests pass; full backend suite is green. | Complete in local process topology |
| 3. Existing Orchestration view | Lazy run-scoped panel, safe rendering, reconnect/gap states, isolation, no-history behavior, and full frontend tests pass. Fake-provider browser runs confirm live rendering. | Complete locally |
| 4. OpenCode vertical slice | Real OpenCode run streamed through local Cloud into the existing agent detail; durable-storage checks found no assistant-text sentinel. | Complete locally |
| 5. Claude and Codex projections | Fake browser runs cover both; Claude's real approved run delivered 195 envelopes to SSE. The additional Claude attempt did not reach Cloud because the backend failed startup. | Adapter/cloud paths complete; real Claude browser cadence remains open |
| 6. Grok Build | A real Grok run streamed text/tool events into the attached browser, completed planning/build after one retry, and passed validation. Review was blocked by the blanket `Bash` deny. The sample now uses scoped read-only Git rules. | Experimental; verify the updated review rules in a fresh real run |
| 7. Release and operations | Windows package smoke and current local regression suites pass. Production Cloud deployment/topology/logging and live-provider gates remain. | Local release prep complete; rollout blocked on gates |

## Remaining rollout gates

- Verify the real Claude stream in the browser panel during a run. Completed on 2026-10-16 against local Cloud: a real Claude workflow rendered in the attached agent detail and completed plan/build/validation/review. Grok also rendered live assistant text and tool activity, but its run stopped in build before validation/review.
- Confirm production Cloud deployment topology, WebSocket/SSE proxy behavior, runtime log redaction, and production health after Cloud deployment.
- Keep Grok Build experimental until a real Windows run completes planning, build, validation, and review.
- Review operational rollout and user-facing enablement after those gates pass.

Historical implementation notes are in LIVE_STREAM_HISTORY.md.
**Render topology evidence:** Render routes each WebSocket handshake to a randomly selected service instance and closes connections when that instance is replaced. Blueprint `numInstances` configures manual scaling, but an existing service retains autoscaling unless scaling configuration is explicitly changed. The Render request-log documentation lists method, status, and requested URL; this does not prove that application errors or external tracing omit payloads. See [WebSockets](https://render.com/docs/websocket), [Blueprint YAML scaling](https://render.com/docs/blueprint-spec), and [Render request logs](https://render.com/docs/logging). The production release must confirm autoscaling is disabled and one instance is active, or implement cross-instance transient fan-out.

## Decisions

1. Parse each harness JSON/JSONL stream once. Continue writing local raw artifacts and local progress as today; fan out normalized events to an optional Cloud sink.
2. Keep Cloud live content out of durable run events, artifacts, logs, analytics, replay buffers, and disk outboxes.
3. Use one authenticated outbound WebSocket from Felix to Cloud per opted-in run. Cloud sends `viewer_active` state over that connection. Felix sends coalesced content only while at least one authorized browser viewer is attached.
4. Keep the Cloud-to-browser display on the existing authenticated SSE pattern. The user opens an agent's existing Orchestration detail/console to subscribe for its active Cloud run; closing or leaving that detail view removes the subscription.
5. Use a non-blocking bounded in-memory queue for live content. A network failure, slow consumer, or full queue must not delay the harness, local console, artifact writes, validation, or state transitions.
6. Never stream private chain-of-thought, opaque provider objects, raw tool arguments/results, or question wording. Raw prompts/spec files are not sent as separate inputs; surfaced assistant text may quote or summarize information from them, so enable it only when run viewers are authorized for that project content. Redact credential-like values and absolute machine paths before sending; relative project filenames may appear.
7. Do not install an always-on Windows service for the first implementation. The Felix CLI owns the publisher worker. Add a local helper only if the CLI-to-PowerShell process seam requires one.
8. Add Grok Build (`grok`) as a distinct harness adapter, not as a model choice inside another adapter. Its protocol and event coverage must pass the common harness contract before Felix advertises it as supported. Keep it experimental until a clean Windows plan/build/validation/review smoke succeeds.
9. Keep local-spec mirroring into Cloud explicit. When opted in, upload the Markdown spec and create its requirement mapping before run creation; never upload local specs implicitly as a side effect of enabling telemetry or live output.

## Target architecture

```text
Harness stdout (provider JSON/JSONL)
        │
        ▼
Provider adapter parser ── writes raw output locally
        │
        ▼
Felix normalized event sink ── local journal / console / workflow state
        │
        └── allowlist projection ── bounded in-memory async queue
                                      │
                              Felix CLI publisher
                                      │ authenticated WebSocket
                                      ▼
                         Cloud transient run postbox
                                      │ in-memory fan-out
                                      ▼
                          Cloud authenticated SSE
                                      │
                                      ▼
                          Open run live activity view
```

Cloud durable metadata sync remains a separate path. It contains only the existing compact event summaries and run metadata; it never receives the live content projection.

### Local event handoff

The harness parser already has the only trustworthy view of provider-specific JSON. Do not add a second process reader or reparse raw output in the publisher. The integration spike must establish how the parsed normalized events reach the CLI-owned publisher without coupling to human-readable console text.

Preferred seam: the CLI creates a per-run local named pipe with a random name and current-user-only access, passes its address to the PowerShell child through an environment variable, and consumes versioned NDJSON event envelopes. PowerShell writes each envelope opportunistically after local journaling; it must not wait for Cloud acknowledgement. If named-pipe support across the supported Windows PowerShell/.NET runtimes proves unreliable, use a short-lived supervised helper or another local IPC mechanism. Do not use a watched disk file or durable local queue for live content.

The CLI publisher owns the Cloud credential and socket. Do not pass the project API key to harness processes or include it in arguments, environment variables inherited by harnesses, events, or run artifacts. Confirm inheritance behavior when implementing the chosen IPC seam.

## Event and transport contracts

### Normalized live event envelope

Use a versioned envelope with fields equivalent to:

| Field | Purpose |
|---|---|
| `schema` | Contract version, initially `felix3-live-event-v1` |
| `run_id` | Felix local run identity |
| `seq` | Monotonic order within the run |
| `timestamp` | UTC event time |
| `harness` | `claude-code`, `opencode`, `codex`, or `grok-build` |
| `phase` | Planning, building, reviewing, or coordinator status |
| `kind` | Allowlisted event kind |
| `text` | Optional surfaced assistant text delta, size-limited |
| `tool` / `status` | Optional allowlisted tool identity and lifecycle status |
| `summary` | Short fixed/sanitized status line |

Only include fields required for display. Never embed the original provider JSON as an opaque payload. Treat tool arguments and tool output as private by default. If users later request richer detail, make each additional content category an explicit, separately-reviewed allowlist.

### Supported display events

- `assistant.delta`: surfaced user-visible assistant text; coalesce adjacent chunks before network send.
- `tool.started`, `tool.completed`, `tool.failed`: tool name from a strict identifier allowlist plus lifecycle state. Do not send arguments or unrestricted result text.
- `phase.started`, `phase.completed`, `phase.failed`, `run.completed`, `run.blocked`, `run.interrupted`: compact lifecycle state.
- `question.requested`, `plan.approval_requested`: generic prompt-to-user indicators only. Question bodies and plan artifacts are not sent as separate fields/files. Assistant output may quote or summarize project/spec context when live text is enabled.

Exclude reasoning/thinking fields even when a provider exposes them. A short progress/status summary can indicate what phase is active without reproducing private reasoning.

### Felix-to-Cloud WebSocket

- Authenticate with the existing project-scoped key using a secure handshake/header supported by the backend; never put credentials in a URL.
- Bind the connection to one validated Cloud run and its project. Validate agent ownership and authorization before accepting events.
- On connect, Cloud sends the current `viewer_active` boolean. It sends updates when authorized run-view subscribers attach/detach; use a short lease/heartbeat so stale viewer state expires after browser or publisher disconnects.
- Felix sends a `live_event` only while `viewer_active=true`. Use batched text deltas with both a short time bound and a maximum byte bound. Lifecycle/tool/question transitions flush promptly.
- Cloud fans accepted events to currently subscribed browser clients through the existing SSE flow. Cloud returns no durable event ID and keeps no replay buffer.
- On socket failure, the publisher drops live content and reconnects with bounded backoff. It never writes transcript content to the existing `.felix3/outbox`, retries it from disk, or blocks local work.
- Treat close, timeout, protocol/version mismatch, auth rejection, and oversized messages as explicit states visible in local diagnostics without exposing payload content.

### Browser stream

- The Orchestration overview remains compact. A user opens a specific active run to attach to its live stream.
- Open the SSE connection only while that view is open; close it on navigation, run completion, or component teardown.
- Filter by project and run server-side as well as client-side. Verify the viewer's project access before subscribing.
- Live view starts at subscription time. It does not backfill events from before the user opened the view and does not replay after reconnect. The UI says when output is live, when the viewer joined late, and when the connection has gaps.
- Render text and code as escaped content/Markdown with no executable HTML. Visually separate assistant output, tool activity, and Felix workflow state. Do not create a misleading “thinking” panel.

## Bounded async behavior and traffic controls

- Use a non-blocking producer (`TryWrite`/equivalent). The parser never awaits the network or queue capacity.
- Keep the queue in memory with a strict event-count and byte ceiling. Establish concrete limits in implementation (initial proposal: small single-digit MiB per run, configurable only if evidence requires it).
- Coalesce text deltas by run/phase into small batches (initial proposal: flush at 150–250 ms or 4 KiB, whichever comes first). Tool/lifecycle transitions flush immediately.
- When full, replace/coalesce pending text deltas for the same message. Drop old text before dropping terminal/tool/question events; if critical events cannot be retained, publish a compact gap marker and preserve final run state locally.
- When no viewer is active, do not enqueue assistant text or tool content for later. Continue local rendering and journaling.
- No durable retries for live content. Durable metadata continues on the existing outbox path.
- Track only aggregate diagnostics locally: bytes sent/dropped, queue high-water mark, reconnect count, and last error category. Do not log event text.

## Felix implementation workstreams

### F0. Protocol spike and contract fixtures

- Confirm the child-process handoff from the packaged C# CLI to the PowerShell normalized event sink. Prototype local IPC with no Cloud dependency.
- Establish envelope schema, event kind allowlist, byte limits, and viewer-active lifecycle.
- Make fixtures from sanitized provider events, not real prompts or user transcripts.
- Confirm cancellation and disposal close the IPC stream and Cloud socket deterministically.

**Exit:** fake normalized events reach local output and a mock publisher through one parse/fan-out path; slow/mock publisher never blocks the parser.

### F1. Felix async publisher

- Add a C# publisher/queue owned by the V3 CLI invocation. Keep configuration, auth, reconnection, backpressure, and socket lifetime out of the harness adapters.
- Connect only when Cloud sync and live activity are enabled. Keep the socket open to receive `viewer_active`; send content only when active.
- Add run identity, cancellation, graceful close, reconnect-without-replay, and safe diagnostic counters.
- Remove synchronous `PublishRunActivity` of live content from the PowerShell callback. Preserve durable metadata sync unchanged and content-free.
- Add fake-server tests for slow server, socket loss/reconnect, viewer toggles, full queue, and no content when disabled/unwatched.

**Exit:** local run output and final state are identical with Cloud live streaming disabled, enabled-but-unwatched, watched, and disconnected.

### C0. Cloud transient postbox and publisher channel

- Add authenticated WebSocket ingest for one run, validating project, run, agent ownership, protocol version, event schema, sizes, rate, and allowed fields.
- Associate publisher sockets with run IDs. Emit viewer-active changes based on authenticated SSE subscriptions and expire stale publisher/viewer state on disconnect.
- Reuse the current in-memory transient broadcaster for same-process fan-out. If deployment has multiple API processes, select an ephemeral pub/sub or routing approach before enabling production traffic.
- Guarantee no write to `run_events`, artifacts, database, object storage, analytics, access logs, request-body traces, or durable queue for live payloads.
- Test project/run isolation, auth failures, malformed payloads, oversize/rate limits, empty subscriber behavior, queue overflow, publisher disconnect, viewer disconnect, and no persistence.

**Exit:** authenticated publisher delivers to authorized live viewers only; tests prove live content leaves no durable trace in Cloud storage/logs.

### C1. Cloud run UI

- Add an active-run detail panel/page from the Orchestration view. Keep summary panel as a lightweight overview.
- Subscribe to run SSE only while opened. Show phase, harness, readable assistant output, tool state, question/approval indicator, connection status, joined-late state, and dropped-event gap marker.
- Handle multiple active runs and viewers without mixing run events. Preserve current project scope.
- Add component tests for rendering/escaping, stream lifecycle, reconnect, run filtering, no history, no-content states, and access errors.

**Exit:** a user can open/close one active run and receive only its future transient activity; no content is stored by the browser.

### F2. Adapter event normalization

Reuse the adapter process readers; add/adjust projections rather than another stdout consumer.

| Harness | Existing observed stream | Planned surfaced content handling |
|---|---|---|
| OpenCode | JSONL `text`, `tool_use`, `step_finish`, `error` | Emit `assistant.delta` from text events; tool lifecycle from `tool_use`; exclude question contents and raw tool data. |
| Claude Code | `stream-json` partial events, assistant/user/result | Emit only assistant text deltas and safe tool lifecycle; exclude thinking blocks, prompts, tool inputs/results. |
| Codex CLI | JSONL thread/turn/item events; current adapter uses completed agent messages | Stream incremental agent text only if the CLI emits a stable delta event; otherwise emit completed message chunks and document that it is less live. Keep command/tool details summarized. |
| Grok Build | Official CLI supports headless `streaming-json`; ACP emits assistant message chunks | Compare the supported headless format with ACP; implement the most stable non-interactive interface that provides sessions, cancellation, and clear event boundaries. Normalize assistant chunks and safe tool state. |

For every adapter, fixtures must show that reasoning fields, raw prompts/spec inputs, credentials, tool arguments/results, and absolute machine paths do not enter the live projection. Surface-text tests must show that quoted credentials and absolute paths are redacted; relative project filenames and assistant quotations may remain. Differences in native capability are documented rather than hidden behind false parity.

### F3. Grok Build harness adapter

- Use canonical harness ID `grok-build`; use executable name `grok`.
- Add config example and validation for model/auth/executable/phase policy without storing credentials in config or artifacts.
- Add setup detection and actionable install/auth instructions for supported Windows use. Verify current official prebuilt behavior; do not assume building from source on Windows is supported.
- Implement plan/build/review invocation, session capture/resume, cancellation, stderr/raw output artifacts, usage where available, and normalized event emission through the same sink.
- Start with fake-process contract tests. Run an opt-in live smoke in the Felix sample project and verify validation/review state end to end.
- Track Grok Build beta/API changes; gate support status on repeatable smoke results, not mere CLI startup.

**Exit:** Grok Build passes the same workflow outcome contract as existing harnesses and preserves local artifacts on interrupted/failed runs.

## Test and verification matrix

| Area | Required checks |
|---|---|
| Event contract | Schema/version validation; ordering; safe projection; provider-specific fixtures; hidden reasoning and unsafe fields excluded. |
| Non-blocking behavior | Artificially stalled publisher; full queue; local output continues; queue stays within byte/event limits; no durable retry. |
| WebSocket | Auth, run ownership, viewer-active toggles, heartbeats, backoff, cancellation, malformed frames, oversize/rate limiting, reconnect without replay. |
| Cloud transient behavior | No database/artifact/outbox/log persistence; project and run isolation; same-process and deployment-topology fan-out. |
| UI | Lazy subscribe/unsubscribe; no pre-open replay; safe Markdown/code; multiple runs; reconnect/gap labels; no browser storage. |
| Harnesses | Existing Claude/OpenCode/Codex adapter contracts plus Grok Build fake and opt-in live cycles; Windows smoke where supported. |
| End-to-end | Open run while active; close it; verify publisher stops content; reopen and see only new events; disconnect Cloud and verify local validation, review, and final status still complete. |

Run repository-prescribed checks and Cloud frontend/backend suites. Do not use production user runs for stream tests; use the disposable Felix test project and test requirements.

## Delivery sequence

1. **Topology and protocol gate:** inspect Cloud deployment worker count/routing and logging/tracing. Decide ephemeral cross-instance fan-out if needed. Freeze the event/WS/SSE schemas and limits.
2. **Local vertical spike:** fake harness JSON → current adapter parser → local output + bounded C# publisher queue via local IPC. Prove no blocking and no live payload on disk.
3. **Cloud backend:** implement publisher WebSocket, viewer-active control, and transient fan-out. Verify persistence/logging constraints before building the UI.
4. **Cloud UI:** implement the opened-run view on authenticated SSE, then validate lazy subscription and multi-run isolation.
5. **First live provider:** OpenCode end-to-end, as its current adapter already emits incremental JSONL text events.
6. **Provider coverage:** Claude, Codex, then Grok Build; record per-harness streaming capabilities and run opt-in smoke tests.
7. **Release gate:** run full regression matrix, check privacy and disabled behavior, document configuration, failure modes, and Grok beta caveat, then deploy Felix Cloud before packaging/releasing the matching Felix CLI.

## Execution backlog

This is the implementation order. Keep each stage independently reviewable and mergeable. A stage may be split into smaller PRs, but do not start a dependent stage until its exit check passes. The Cloud UI can be developed against a local backend after the Cloud contract is frozen; Felix's publisher should not be wired to a production endpoint until the Cloud privacy and topology gates pass.

### Stage 0 — Freeze the interface and deployment assumptions

**Repositories:** Felix and Felix Cloud.
**Deliverables:** protocol note/fixtures, endpoint contract, verified Cloud deployment topology, and explicit opt-in configuration name/default.

1. Verify Cloud's actual Render instance count, process workers, request routing/affinity, WebSocket idle timeout, proxy/body logging, error reporting, and access-log behavior. Source configuration alone is insufficient to prove runtime topology.
2. Choose one supported delivery topology. Prefer a single Cloud instance only if operations can guarantee it; otherwise add an in-memory-to-in-memory transient relay such as Redis pub/sub. Do not add a durable broker or database table for live payloads.
3. Freeze schema/version, message size limits, rate limits, event allowlist, text coalescing limits, ping/lease cadence, close codes, and reconnect behavior. Store sanitized fixtures for each event kind.
4. Confirm the existing per-project Cloud opt-in and define whether a separate `live_output` switch is needed. Default live output off. UI subscription is an additional demand gate, not consent by itself.
5. Decide the exact ownership check for a Felix publisher key against the Cloud run/agent/project, and the authorization check for a browser viewer.

**Exit check:** written contract covers success, disabled, no-viewer, disconnect, queue overflow, auth failure, and topology. Cloud ops confirms the selected topology and that live payloads are excluded from logs/traces.

### Stage 1 — Prove local event fan-out without Cloud

**Repository:** Felix.
**Deliverables:** versioned normalized envelope, current-user local IPC prototype, bounded publisher queue, and deterministic slow-consumer tests.

1. Follow one OpenCode JSONL event through its existing parser. Preserve current local raw artifact, console output, and event journal behavior.
2. Add a strict allowlist projection after normalization. Construct a new envelope field by field; never clone or redact an opaque provider object.
3. Connect the PowerShell coordinator to the C# CLI process through a run-scoped, random, current-user-only IPC channel. Pass only the IPC address and non-secret stream settings in pipe control frames; never include Cloud credentials in those frames. The coordinator may use configured credentials for its existing metadata sync, but must remove sync credentials from harness child environments.
4. Make the producer opportunistic: local writes happen first; IPC/queue delivery uses non-blocking writes and can fail closed without affecting the run.
5. Bound queue by both event count and bytes. Coalesce adjacent assistant text. Preserve lifecycle transitions; record aggregate drop/gap counters without recording text.
6. Verify cancellation and every exit path dispose pipe, queue, and worker; verify no stream content reaches a disk queue or Felix Cloud metadata outbox.

**Exit check:** fake harness run has identical local output/artifacts/final state with publisher disabled, stalled, full, and disconnected. Tests demonstrate the parser and workflow do not await network/queue capacity.

### Stage 2 — Implement and prove Cloud's transient transport

**Repository:** Felix Cloud.
**Deliverables:** authenticated publisher WebSocket, authorized run-scoped subscriber stream, viewer-demand signaling, and transient fan-out.

1. Validate publisher key, run existence, project membership, agent ownership, schema version, allowed kinds/fields, event size, and message rate before fan-out.
2. Add a run-scoped publisher registry and viewer count. Send current viewer state at connect and state changes on browser attach/detach. Expire stale state on disconnect and heartbeat timeout.
3. Keep fan-out memory-only. Do not persist, replay, add a Cloud run event, or return a durable event ID. Exclude live bodies from request logging, exception messages, tracing attributes, and analytics.
4. Enforce run/project isolation in the broker and in route authorization. A project-wide subscriber must not receive content unless the product explicitly chooses that behavior; default to run-only.
5. Exercise same-process fan-out and the verified deployment topology. If using a transient relay, verify TTL/no persistence and publish/subscribe authorization.
6. Add explicit no-viewer behavior: reject or discard content before it enters a queue when no viewer is attached; never buffer for later viewers.

**Exit check:** endpoint tests prove valid delivery only to an authorized viewer and prove no durable database/object-store/outbox/log path receives the content. Topology test proves publisher and viewer communicate under actual deployment routing.

### Stage 3 — Add live output to the existing Orchestration agent view

**Repository:** Felix Cloud frontend.
**Deliverables:** transient surfaced output inside the existing Orchestration agent detail/console view, lazy run-scoped SSE subscription, accessible status states, and component tests.

1. Reuse the existing Orchestration agent click-through and console area; do not add a second top-level place to watch an agent.
2. Mount the run-scoped live panel only while an agent detail view has an active Cloud run, and subscribe only while that view is open. Close the stream on navigation, agent/run change, or completion.
3. Render escaped surfaced assistant text, tool lifecycle summaries, phase state, generic question/approval indicators, and connection/gap states. No arbitrary HTML.
4. Start at join time and show that earlier output is unavailable. Do not write streamed output to browser storage, analytics, or error reports.
5. Support two open runs in separate views/tabs without cross-delivery. Reconnect is live-only and visibly marks possible gaps.

**Exit check:** browser tests cover the existing agent click-through, lazy subscribe/unsubscribe, late join/no history, rendering safety, reconnect, inaccessible run, multiple runs, and streaming disabled.

### Stage 4 — Wire Felix and Cloud for the OpenCode vertical slice

**Repositories:** Felix and Felix Cloud.
**Deliverables:** end-to-end OpenCode output inside the existing Orchestration agent detail/console for its active Cloud run, plus documented local config.

1. Implement the CLI-owned WebSocket publisher over the Stage 1 IPC queue. Connect only when project Cloud sync and the explicit live-output setting are enabled.
2. Send only while Cloud reports an active authorized viewer. Coalesce text on the chosen time/byte threshold; flush tool and lifecycle transitions promptly.
3. Reconnect with bounded backoff and no replay. Do not fail the run on auth/network/protocol errors; surface a local diagnostic category and preserve local artifacts.
4. Remove synchronous live-content HTTP calls from the PowerShell event sink. Keep compact durable metadata on its existing outbox path unchanged and ensure that path cannot accept text deltas.
5. Run a disposable local Felix Cloud smoke: open the existing agent detail view, observe new OpenCode text/tool state there, navigate away and verify content stops, reopen and verify only later events appear; break Cloud connectivity and verify local run completes.

**Exit check:** all Stage 4 behaviors are repeatable against local Cloud, and the Cloud database, logs, browser storage, and Felix durable outbox contain no streamed text.

### Stage 5 — Extend safe projections to existing harnesses

**Repository:** Felix.
**Deliverables:** explicit provider capability table and fixture-backed adapter mappings for Claude Code, Codex, and OpenCode.

1. OpenCode: cover text deltas, safe tool state, errors, and step completion.
2. Claude Code: allow only surfaced assistant text deltas; explicitly reject thinking/reasoning deltas, user prompts, tool inputs/results, and raw message objects.
3. Codex: use incremental text only if a stable delta event exists in the supported CLI version; otherwise publish completed assistant chunks and label the slower cadence accurately.
4. Add privacy fixtures containing realistic decoy secrets, absolute local paths, raw prompt/spec fields, reasoning, and tool output. Assert unsafe fields are excluded and secrets/absolute paths are redacted from surfaced assistant text.
5. Add provider version/capability diagnostics without logging payloads.

**Exit check:** each supported adapter passes the same schema/privacy tests, and documentation states whether it streams deltas or completed chunks.

### Stage 6 — Add Grok Build as an independent harness

**Repository:** Felix.
**Deliverables:** `grok-build` adapter, setup/config support, packaged executable integration, contract tests, and opt-in live smoke.

1. Verify official Windows install/auth, headless `streaming-json` and ACP behavior, plan/build/review role support, cancellation, session continuation, permission controls, and usage reporting against the actual supported CLI release. The installed `grok 1.0.50` CLI is authenticated and emitted headless `streaming-json` events in a real smoke; a complete successful workflow is not yet verified.
2. Choose one native protocol based on repeatable event boundaries, Windows support, cancellation, and session behavior. Keep protocol parsing private to the adapter; emit only Felix normalized events.
3. Implement explicit harness registration, configuration validation, setup detection, friendly missing/auth error messages, executable launch, artifact capture, cancellation, session handling, and usage metadata where available.
4. Add fake executable contract tests for success, malformed JSON, partial lines, exit failure, cancel, resume, redaction, and preserved local artifacts.
5. Package and run the live Grok smoke against a disposable sample spec. Earlier approved `grok-4.6` attempts did not complete: one stopped at a three-turn planning cap; one ended after three cancelled build attempts; the third (`S-0002-20261015-205132-6b754141`, reported cost $0.0270402) completed planning but stopped during its single build invocation after `run_terminal_command` returned a failed/cancelled update. The fourth (`S-0001-20261015-220940-57377d78`) used a one-turn cap, disabled shell and Cloud sync, and stopped in planning at $0.01470772. The latest authorized retry (`S-0001-20261015-223819-247e4f97`) allowed one request per phase, kept Cloud sync off, and stopped during planning when `read_file` reached `max_turn_requests`; reported cost was $0.01474104, below the $0.05 cap. The original `.felix3/config.json` bytes were restored. Neither one-turn run reached building, so neither provides evidence about the `run_terminal_command` permission mapping. The saved update from the third attempt contains only `User cancelled the execution`. Local `grok inspect --json` confirmed that `run_terminal_command` was unqualified and absent from its configured MCP servers; the speculative `MCPTool(...)` rule has been removed. xAI documents `Bash` as the shell permission filter, but the live smoke does not establish whether the tool host maps `run_terminal_command` to it. Felix persists only failed tool name/status and stop reason in the local normalized result, covered by a fake-provider regression. The 2026-10-16 browser-attached retry confirmed live assistant/tool output delivery, but the run again exhausted three build attempts because `run_terminal_command` returned `cancelled`; plan completed, validation/review did not run, reported total cost $0.11271. Preserve Grok as experimental until the permission/tool cancellation issue is understood and a full Windows plan/build/validation/review smoke passes.

**Exit check:** same plan/build/validation/review outcome contract as existing adapters, plus installation and interruption behavior verified. CLI startup alone does not meet this gate.

**Latest cancellation diagnosis (2026-10-18):** The first post-fix Grok 4.6 run completed planning, building, and independent validation, but review failed when Grok issued a compound terminal command beginning with `git status --porcelain`; the tool returned `failed` and the provider stopped as cancelled. Felix now applies the single-terminal-command rule to every Grok phase. The local-only workflow cost $0.11427128 because the local Cloud/PostgreSQL stack could not be started. A review-only retry on the saved session returned an approved review without failed tool calls and cost $0.0411502. The original coordinator run remains terminal-blocked, so the retry did not update its state. The contract suite asserts the guidance for planning, building, and reviewing. A fresh full coordinator run is still required; keep Grok experimental until it passes.

**Initial cancellation diagnosis (2026-10-16):** A controlled Grok 4.6 probe reproduced the build failure only when the terminal command chained the validation with `; Write-Host` to echo its exit code. The single validation command passed from both the project root and Felix worktree, through both direct Grok and Felix's redirected adapter. The six bounded diagnostic calls cost a combined $0.11269368.

### Stage 7 — Release and operational readiness

**Repositories:** Felix and Felix Cloud.
**Deliverables:** deployed compatible Cloud backend/UI, matching Felix release, operator/user docs, and support checklist.

1. Run Cloud backend/frontend tests and Felix CLI/PowerShell/package tests; run the end-to-end matrix from the disposable project.
2. Verify default-off behavior, opt-in behavior, viewer-demand gating, privacy, bandwidth/coalescing limits, queue/drop metrics, cancellation, and reconnect gaps.
3. Deploy Cloud first; verify the exact deployed build, instance topology, WebSocket/SSE route behavior, and log redaction before publishing the matching Felix CLI.
4. Document what is sent, when it is sent, when it stops, what is never sent, no-history behavior, harness capability differences, and troubleshooting.
5. Keep Grok experimental or omit it from supported-harness lists if its Windows/auth/session smoke is not repeatable. Do not delay safe OpenCode/Claude/Codex streaming release solely to market Grok as supported.

**Exit check:** all completion criteria below pass, Cloud and CLI versions are compatible, and a user can disable the feature without losing local run output or workflow reliability.

## Explicit out of scope for this iteration

- Persisting, replaying, exporting, or searching live output in Felix Cloud.
- Uploading raw transcripts, spec/prompt files, chain-of-thought, tool arguments/results, credentials, absolute local paths, or session identifiers. Surfaced assistant output may quote project/spec context while an authorized viewer is attached.
- Sending live content while no eligible viewer is attached.
- A machine-wide Felix Windows service or a general-purpose event broker.
- Cross-machine run takeover, remote interaction/approval, or answering questions through the live viewer.
- Promising uniform token-by-token streaming across harnesses.
- Treating Grok as a model selection inside another harness.

## Risks and mitigations

- **In-memory broker is process-local:** verify deployment; add only transient pub/sub or routing needed for real topology.
- **No viewer presence at publisher:** viewer-active control is a required protocol feature; without it, traffic is still sent while nobody watches.
- **Slow consumers:** bounded non-blocking queue and deliberate text coalescing/drops; preserve local output and final state.
- **Sensitive provider content:** strict event projection before enqueue/upload, no opaque JSON, no content logs, no durable Cloud stores.
- **Reconnect gaps:** explicitly live-only and no replay; show gap state; local artifacts remain the complete record.
- **Provider mismatch:** document event coverage; avoid promising character-by-character streaming for providers that only emit completed message items.
- **Grok Build beta changes:** isolate adapter and fixtures; pin or detect supported CLI versions; keep it opt-in until repeatable tests pass.
- **Process ownership complexity:** use the C# CLI's per-run worker and local IPC; avoid a Windows service unless evidence shows a need.

## Completion criteria

- Opening an authorized Cloud run view causes live content publishing to become active; closing the last view stops content publishing after bounded state propagation.
- Local console, run artifacts, validation, review, cancellation, and work-source status do not depend on Cloud live-stream health.
- Assistant text/tool/question/lifecycle output is readable and safely rendered; hidden reasoning, raw prompt/spec inputs as separate payloads, credentials, absolute machine paths, and unrestricted tool I/O are not transmitted. Live assistant text may reference or quote project/spec information and relative filenames.
- Live event content is never persisted or replayed by Felix Cloud or the Felix durable metadata outbox.
- Cloud deployment topology is supported and tested; cross-project/run delivery is impossible under tests.
- Claude Code, OpenCode, Codex, and Grok Build pass shared contract tests; live-provider smokes are documented with any capability limits.
- Felix and Cloud documentation describe opt-in, no-replay behavior, content scope, privacy, connectivity gaps, and harness-specific limitations.
