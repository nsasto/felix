# Felix 3 compatibility

Status checked: 2026-10-14. Felix 3 is a breaking preview; do not treat this matrix as a stable-release promise.

| Area | Felix 2.2.0 (final V2) | Felix 3.0.0-preview.1 | Cutover position |
| --- | --- | --- | --- |
| CLI | V2 command surface (`felix run`, `felix loop`, and related commands) | V3 bridge under `felix v3`; the V2 surface remains available in this preview build | Stable V3 may replace the V2 workflow; migration is required for the V3 project model |
| Project state | `.felix/` configuration, requirements database, and V2 agent profiles | Separate `.felix3/config.json`, Markdown specs with readiness frontmatter, and durable `.felix3` run/work-source state | V3 migration previews before writing and does not convert V2 requirements or agent settings |
| Harnesses | V2 agent/profile integration | Claude Code, OpenCode, and Codex CLI adapters; each has passed a live Felix-driven plan/build/validation/review smoke | Install and authenticate the selected harness separately; Felix does not replace its native loop |
| Local work source | V2 requirement selection | Explicit spec, `felix v3 next`, and `felix v3 loop` over `ready-for-agent` Markdown specs | Local V3 queue is supported in the preview |
| Felix Cloud | Existing V2 sync client | Requires claim status on `/work/next` plus agent ownership checks on start/complete/release; event/artifact sync remains opt-in | The production endpoint returned a claim without `status` on 2026-10-14. Cloud V3 claiming is not ready until the pending server changes are deployed and live-verified. Do not set a cutover date yet |
| Recovery | V2 run recovery behavior | Durable same-checkout resume; missing local state on an active Cloud claim stops safely for recovery | Cross-machine takeover is not supported because harness session and working-tree state are local |
| Release availability | [Felix 2.2.0](https://github.com/nsasto/felix/releases/tag/v2.2.0) | `3.0.0-preview.1` package is built and locally verified; it is not yet published | Do not rely on an online V3 download until the preview release is published |

## Upgrade guidance

Run `felix v3 migrate --harness <claude-code|opencode|codex>` to inspect the V3 configuration preview. Add `--apply` only after reviewing it. Migration creates separate V3 configuration and installs the provider-neutral Felix skill; it does not rewrite V2 project data. To start a new V3 project, use `felix v3 setup --harness <provider>`.

Use the canonical [Felix 3 guide](README.md), [V3 skill](skills/felix/SKILL.md), and [rollout checklist](V3_ROLLOUT.md) for current details. V3 remains a preview until release acceptance gates pass.
