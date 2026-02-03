# Felix Agent Configuration

This file documents the agent-related configuration in `.felix/config.json` and `~/..felix/agents.json`.

## How Agent Selection Works

- `.felix/config.json` selects an agent by ID: `agent.agent_id`
- The agent preset (executable/args/etc) lives in `~/..felix/agents.json`

```json
{
  "agent": {
    "agent_id": 0
  }
}
```

## Agent Presets (`~/..felix/agents.json`)

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
  "args": ["-C", ".", "-s", "workspace-write", "-a", "never", "exec", "--color", "never", "-"],
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

