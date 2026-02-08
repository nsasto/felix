# Felix Agent Config: One Source of Truth (for now)

This repo keeps agent presets in one place to avoid confusion and ID mismatches.

## Source Of Truth

Agent presets live in `.felix/agents.json`.

- This file defines what each `agent_id` means for this repo (e.g., “2 = codex”).
- This is the file you should edit when you want to change executable/args/env for an agent.

The active agent is selected in `.felix/config.json`:

```json
{
  "agent": { "agent_id": 2 }
}
```

## What Happened To “Two agents.json Files”?

Some parts of Felix historically used a **global** presets file:

- `%USERPROFILE%\.felix\agents.json` (or `$env:FELIX_HOME\agents.json`)

If your global file and the repo file disagree, you can see symptoms like:

- `agent_id` is `2`
- but Felix runs the agent that global `agents.json` calls “2”

To avoid that, Felix’s PowerShell runner in this repo reads the repo-local `.felix/agents.json` for agent presets.

## Runtime Status Is Not A File

The “which agents are currently running” view is not tracked in a project `agents.json`.

- Agents register and heartbeat to the backend (best-effort).
- Runtime status comes from backend state (API/database), not a local JSON registry.

## `.felix/agents.json` Schema (Presets)

Each entry describes how to run an agent CLI:

```json
{
  "id": 2,
  "name": "codex",
  "adapter": "codex",
  "executable": "codex",
  "args": ["-C", ".", "-s", "workspace-write", "-a", "never"],
  "working_directory": ".",
  "environment": {},
  "description": "OpenAI Codex CLI - Diff-based workflow, OAuth auth"
}
```

Guidelines:

- Use `id` for logic/references. Treat it as stable.
- Use `name`/`description` for display only.
- Keep `args` explicit (avoid hidden defaults).

## Debug Checklist (Wrong Agent)

1. Check `.felix/config.json` → `agent.agent_id`
2. Check `.felix/agents.json` → the entry with that `id`
3. Confirm the logs show: `Using agent: <name> (ID: <id>)`

## Future Direction

As Felix moves toward web-managed configuration, we can revisit whether a global presets file makes sense. Until then: keep agent presets in `.felix/agents.json` for this repo.

