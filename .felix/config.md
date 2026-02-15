# Felix Agent Configuration

This file documents the configuration options in `felix/config.json` for customizing the Felix agent's behavior, particularly the LLM agent integration.

> **Note (Phase -1)**: As of v0.1-cleanup-complete, **felix/state.json** is no longer read by the backend for runtime state management. The backend endpoints for agent registry and status are stubbed pending the Phase 0 database implementation. The state.json file is still written by felix-agent.ps1 for local agent execution, but the backend does not consume it.

## How Agent Selection Works

- `felix/config.json` selects a local CLI agent by ID: `agent.agent_id`
- Local CLI presets (executable/args/etc) live in **.felix/agents.json** in the repo
- Felix CLI configuration and execution are always local to the machine running it.
- Backend agent profiles are stored in the database and managed via the API

```json
{
  "agent": {
    "agent_id": 0
  }
}
```

## Local CLI Presets (**.felix/agents.json**)

Each preset is an entry under `agents`:

```json
{
  "agents": [
    {
      "id": 0,
      "name": "felix-primary",
      "executable": "droid",
      "args": ["exec", "--skip-permissions-unsafe"],
      "working_directory": ".",
      "environment": {}
    }
  ]
}
```

### Fields

- `id`: Unique integer (0 is system default)
- `name`: Display name
- `executable`: Command to run (must be on PATH or absolute)
- `args`: Arguments (array)
- `working_directory`: Working dir (relative to project root)
- `environment`: Env vars for the agent process

## Example Presets

### OpenAI Codex CLI

Install:

```json
{
  "id": 1,
  "name": "codex-cli",
  "executable": "codex",
  "args": [
    "-C",
    ".",
    "-s",
    "workspace-write",
    "-a",
    "never",
    "exec",
    "--color",
    "never",
    "-"
  ],
  "working_directory": ".",
  "environment": {}
}
```

Notes:

- `-` makes `codex exec` read the prompt from stdin
- `-C .` pins the workspace root for the agent

### Claude Code (Anthropic)

Install:

```json
{
  "id": 2,
  "name": "claude-code",
  "executable": "claude",
  "args": ["-p", "--output-format", "text"],
  "working_directory": ".",
  "environment": {}
}
```

## Troubleshooting

- **Agent not found**: Verify the `executable` path exists and is accessible
- **Authentication errors**: Check `environment` variables for required API keys
- **Command failures**: Test the agent manually by piping a prompt into the executable

For more information, see the Felix documentation in the project root.
