# Felix Agent Configuration

This file documents the configuration options in `felix/config.json` for customizing the Felix agent's behavior, particularly the LLM agent integration.

## Agent Configuration

The `agent` section configures which coding agent to use for LLM calls. Felix supports pluggable agents that accept prompts via stdin and output responses to stdout.

```json
{
  "agent": {
    "executable": "path/to/agent",
    "args": ["arg1", "arg2"],
    "working_directory": ".",
    "environment": {
      "KEY": "value"
    }
  }
}
```

### Fields

- **`executable`**: Path to the agent executable. Can be absolute or relative to the project root.
- **`args`**: Array of command-line arguments to pass to the executable.
- **`working_directory`**: Directory to run the agent from (relative to project root). Defaults to ".".
- **`environment`**: Object of environment variables to set for the agent process.

## Supported Agents

### OpenAI Codex

The OpenAI Codex CLI provides access to GPT models optimized for coding.

#### Installation

```bash
npm install -g @openai/codex
```

#### Configuration

```json
{
  "agent": {
    "executable": "C:\\Users\\<username>\\AppData\\Roaming\\npm\\codex.cmd",
    "args": ["exec", "--model", "gpt-5-codex", "-"],
    "working_directory": ".",
    "environment": {}
  }
}
```

- **executable**: Full path to codex.cmd (varies by npm installation)
- **args**:
  - `exec`: Run non-interactively
  - `--model`: Specify model (e.g., "gpt-5-codex", "gpt-4o")
  - `-`: Read prompt from stdin
- **environment**: Add API keys if needed (e.g., `{"OPENAI_API_KEY": "sk-..."}`)

### Factory.ai Droid

Factory.ai's droid tool provides enterprise LLM integration.

#### Installation

Contact Factory.ai for installation instructions. Droid should be available in your PATH.

#### Configuration

Felix agent calls `droid exec --skip-permissions-unsafe` directly (no configuration needed).

Authentication is handled via the `FACTORY_API_KEY` environment variable.

## Switching Agents

To switch agents:

1. Install the desired agent
2. Update the `agent` section in `felix/config.json`
3. Restart any running Felix agents

The agent executable must:

- Accept input via stdin
- Output responses to stdout
- Exit with code 0 on success
- Support the expected command-line interface

## Troubleshooting

- **Agent not found**: Verify the `executable` path exists and is accessible
- **Authentication errors**: Check `environment` variables for required API keys
- **Command failures**: Test the agent manually with `echo "test" | <executable> <args>`

For more information, see the Felix documentation in the project root.
