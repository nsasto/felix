---
name: felix-swarm-ship
description: >
  Set up Felix as the engineering harness, co-author a requirement spec with the user,
  publish it to Felix Cloud, configure Codex (plan/review) + OpenCode Go (build) phase
  agents, and start remote/swarm execution. Use when the user wants to ship work through
  Felix, publish a requirement to runfelix.io, deploy to a Felix swarm/fleet, or runs
  /felix-swarm-ship.
---

# Felix swarm ship

Drive Felix as the development base. You configure the repo, write one requirement with the user, push it to Felix Cloud, then let Felix plan/review (Codex) and build (OpenCode Go) via the remote work queue.

## Preconditions

Confirm these exist (install/configure if missing):

| Tool | Check | Notes |
|---|---|---|
| Felix CLI | `felix version` | Install from https://github.com/nsasto/felix/releases or repo `scripts\install.ps1` |
| Codex CLI | `codex --version` | `npm i -g @openai/codex` then `codex login` |
| OpenCode | `opencode --version` | `npm i -g opencode-ai`; `/connect` → **OpenCode Go** (Zen API key) or DeepSeek BYOK |
| Sync creds | `FELIX_SYNC_URL`, `FELIX_SYNC_KEY` | Or `.felix/config.json` `sync.*` from `felix setup` |

Do not invent API keys. Ask the user for `fsk_...` if sync is not configured.

## Workflow

### 1. Project setup

In the target repo:

```powershell
felix setup
```

Ensure sync is enabled for cloud/swarm:

```json
"sync": {
  "enabled": true,
  "provider": "http",
  "base_url": "https://api.runfelix.io",
  "api_key": "fsk_..."
}
```

Or set `$env:FELIX_SYNC_ENABLED="true"`, `$env:FELIX_SYNC_URL`, `$env:FELIX_SYNC_KEY`.

### 2. Agent profiles + phase map

Ensure `.felix/agents.json` has at least:

- Codex profile for planning/review (Astra / `gpt-6-astra` if supported; otherwise strongest available Codex model)
- OpenCode profile for building via **OpenCode Go**: `opencode-go/deepseek-v4-pro`

Write `.felix/config.json` phase routing:

```json
"agent": {
  "agent_id": "<codex-profile-key>",
  "by_phase": {
    "planning": "<codex-profile-key-or-name>",
    "building": "<opencode-profile-key-or-name>",
    "reviewing": "<codex-profile-key-or-name>"
  }
},
"review": {
  "enabled": true
}
```

Use `felix agent list` / `felix agent setup` / `felix agent use` for keys. Prefer keys (`ag_...`) in `by_phase`.

### 3. Spec with the user

Interview briefly for goal, constraints, acceptance checks, and out-of-scope.

```powershell
felix spec create "<short title>"
```

Fill acceptance/validation criteria. Only put real shell commands in backticks under Validation Criteria.

```powershell
felix spec fix
```

One requirement → one detailed plan inside Felix. Do not split into child requirements unless the user asks.

### 4. Publish to Felix Cloud

```powershell
felix spec push --force
```

Confirm success. If sync is misconfigured, fix URL/key and retry — do not claim publish succeeded without command output.

### 5. Deploy to swarm

```powershell
felix loop --sync
# or
felix run-next --sync
# denser local parallelism
felix loop --sync --parallel 2
```

Other machines with the same project + sync key can also run `felix loop --sync` / `felix run-next --sync`.

Felix owns plan → build → validate → review. Do not reimplement that loop in chat.

### 6. Monitor

```powershell
felix status
felix query runs --json
felix query requirements --json
felix dashboard --html --no-open
```

On exit code 2/3 (blocked): fix tests/validation, set status from `blocked` → `planned` in `.felix/requirements.json`, then restart the loop.

## Rules

- Felix is the harness; you are the orchestrator and spec partner.
- Prefer existing Felix commands over custom scripts.
- Keep planning/review on Codex and building on OpenCode via `agent.by_phase`.
- With `review.enabled` (default true), `ALL_COMPLETE` schedules architecture **reviewing**. `REVIEW_CHANGES_REQUESTED` returns to building; `REVIEW_COMPLETE` finishes and writes `.felix/memory/requirement/<id>/review-*.md`.
- `felix review` (CLI) is learnings/prompt curation — distinct from the reviewing phase.
- Portable: copy this `SKILL.md` (or the whole skill directory) into Grok/Codex/Claude skill folders — see **INSTALL.md**.
