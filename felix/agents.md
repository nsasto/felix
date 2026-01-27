# Felix Agents - Configuration and Registration

This document explains how Felix agents work, including configuration management and runtime registration.

## Overview

Felix uses a **two-part system** for managing agents:

1. **Agent Configuration** (`agents.json`) - Static profiles defining available agents
2. **Agent Registration** (Backend runtime) - Dynamic tracking of running agent processes

## Agent Configuration (agents.json)

### Purpose

Defines available agent "profiles" that can be used to execute Felix requirements. Think of this as your library of available agents.

### Location

`felix/agents.json`

### Schema

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
    },
    {
      "id": 1,
      "name": "claude-sonnet",
      "executable": "claude",
      "args": ["--model", "sonnet"],
      "working_directory": ".",
      "environment": {
        "ANTHROPIC_API_KEY": "..."
      }
    }
  ]
}
```

### Fields

- **id** (integer): Unique identifier for the agent. ID 0 is special (system default, cannot be deleted)
- **name** (string): Human-readable agent name
- **executable** (string): Command to execute (e.g., "droid", "claude", "python")
- **args** (array): Command-line arguments for the executable
- **working_directory** (string): Directory to run commands in (usually ".")
- **environment** (object): Environment variables to set when running the agent

### Agent ID 0 - System Default

- Agent ID 0 is **protected** and cannot be deleted
- Serves as fallback if referenced agent is not found
- Always guaranteed to exist
- Can be edited but not removed

### Managing Agents

Agents can be managed through:

- **Settings UI**: Add, edit, delete agents (coming in S-0020)
- **Manual editing**: Edit `felix/agents.json` directly

## Active Agent Selection (config.json)

### Purpose

Specifies which agent configuration should be used when running `felix-agent.ps1`.

### Location

`felix/config.json`

### Configuration

```json
{
  "agent": {
    "agent_id": 0
  }
}
```

The `agent_id` field references an agent by ID from `agents.json`.

### How It Works

When `felix-agent.ps1` starts:

1. Reads `agent_id` from `config.json`
2. Looks up that agent in `agents.json`
3. Uses that agent's `executable` and `args` to run iterations
4. If agent not found, falls back to ID 0 and auto-corrects config.json

## Agent Registration (Runtime)

### Purpose

Tracks which agent processes are **currently running**, their status, and what they're working on.

### When It Happens

Agent registration occurs automatically when you start `felix-agent.ps1`:

1. **Startup**: Agent calls `POST /api/agents/register`
2. **Heartbeat**: Every 5 seconds, agent sends heartbeat to `POST /api/agents/{name}/heartbeat`
3. **Shutdown**: Agent calls `POST /api/agents/{name}/stop` on clean exit

### Registration Data

When an agent registers, it sends:

```json
{
  "agent_name": "felix-primary",
  "pid": 12345,
  "hostname": "LAPTOP-XYZ",
  "started_at": "2026-01-27T20:00:00Z"
}
```

### Backend Registry

The backend maintains a runtime registry:

```json
{
  "agents": {
    "felix-primary": {
      "pid": 12345,
      "hostname": "LAPTOP-XYZ",
      "status": "active",
      "current_run_id": "S-0018",
      "started_at": "2026-01-27T20:00:00Z",
      "last_heartbeat": "2026-01-27T20:05:22Z",
      "stopped_at": null
    }
  }
}
```

### Agent Status Values

- **active**: Agent is running and heartbeat is current (< 10 seconds old)
- **inactive**: Heartbeat is stale (> 10 seconds) or process not found
- **stopped**: Agent cleanly shut down

### Heartbeat Updates

Every 5 seconds, the agent sends:

```json
{
  "current_run_id": "S-0018"
}
```

This updates:

- `last_heartbeat` timestamp
- `current_run_id` (which requirement it's working on)
- `status` (backend validates heartbeat freshness)

## Key Differences

### agents.json (Configuration)

- **Static**: User-defined, manually edited or via UI
- **Purpose**: "What agents CAN I run?"
- **Contains**: Executable, args, environment
- **Persistence**: Committed to git, shared across team
- **Management**: Settings UI, manual editing

### Backend Registry (Runtime)

- **Dynamic**: Updated automatically by running agents
- **Purpose**: "What agents ARE running right now?"
- **Contains**: PID, status, heartbeat, current work
- **Persistence**: In-memory or temporary file, not committed
- **Management**: Automatic, no manual editing

## Workflow Example

### Scenario: Starting an Agent

1. **User configures agents** (one-time setup)

   ```json
   // felix/agents.json
   {
     "agents": [
       { "id": 0, "name": "felix-primary", "executable": "droid", ... }
     ]
   }
   ```

2. **User selects active agent** (via Settings UI or manual edit)

   ```json
   // felix/config.json
   {
     "agent": { "agent_id": 0 }
   }
   ```

3. **User starts agent**

   ```powershell
   .\felix-agent.ps1 .
   ```

4. **Agent loads configuration**
   - Reads `agent_id: 0` from config.json
   - Looks up agent ID 0 in agents.json
   - Gets: `executable="droid"`, `args=["exec", "--skip-permissions-unsafe"]`

5. **Agent registers with backend**
   - Calls `POST /api/agents/register`
   - Backend adds entry to runtime registry
   - Status: "active"

6. **Agent sends heartbeats**
   - Every 5 seconds: `POST /api/agents/felix-primary/heartbeat`
   - Updates `current_run_id` with requirement being worked on
   - Backend updates `last_heartbeat` timestamp

7. **Agent executes iterations**
   - Uses `droid exec --skip-permissions-unsafe` from agents.json
   - Works on requirements sequentially

8. **Agent shuts down**
   - Calls `POST /api/agents/felix-primary/stop`
   - Backend marks status as "stopped"
   - Sets `stopped_at` timestamp

### Scenario: Agent Crash

1. Agent process terminates unexpectedly
2. Heartbeats stop
3. After 10 seconds, backend marks agent as "inactive"
4. UI can display: "felix-primary (inactive - last seen 2 minutes ago)"

### Scenario: Multiple Agents (Future)

1. Configure multiple agents in agents.json:

   ```json
   {
     "agents": [
       { "id": 0, "name": "felix-primary", ... },
       { "id": 1, "name": "claude-sonnet", ... },
       { "id": 2, "name": "local-llama", ... }
     ]
   }
   ```

2. Each agent instance can register with unique name
3. Backend tracks all simultaneously
4. UI shows: "3 agents available, 1 active"

## Error Handling

### Agent Not Found

If `config.json` references a non-existent agent ID:

1. Agent logs warning: "Agent ID 5 not found. Falling back to system default (ID 0)."
2. Agent uses ID 0 configuration
3. Agent auto-corrects `config.json` to `agent_id: 0`
4. Execution continues normally

### Agent ID 0 Missing

If system default (ID 0) is not in agents.json:

1. Agent logs error: "System default agent (ID 0) not found in agents.json"
2. Agent exits with code 1
3. User must fix agents.json before retrying

### Registration Failure

If backend is unavailable:

1. Agent logs: "Registration failed (backend may be unavailable)"
2. Agent continues execution anyway (best-effort registration)
3. No heartbeat job started
4. Agent still works, just not tracked in UI

## Best Practices

### Configuration

- **Always keep agent ID 0**: It's the safety net
- **Use descriptive names**: "claude-sonnet-3.5", not "agent1"
- **Document args**: Use environment variables for sensitive data
- **Version control**: Commit agents.json for team sharing

### Registration

- **Start backend first**: For registration to work
- **Monitor heartbeats**: Check UI for agent health
- **Clean shutdowns**: Use Ctrl+C for proper unregistration
- **Multiple instances**: Use unique agent names per machine

## API Reference

### Register Agent

```http
POST /api/agents/register
Content-Type: application/json

{
  "agent_name": "felix-primary",
  "pid": 12345,
  "hostname": "LAPTOP-XYZ",
  "started_at": "2026-01-27T20:00:00Z"
}
```

### Send Heartbeat

```http
POST /api/agents/{agent_name}/heartbeat
Content-Type: application/json

{
  "current_run_id": "S-0018"
}
```

### Stop Agent

```http
POST /api/agents/{agent_name}/stop
```

### List Agents

```http
GET /api/agents

Response:
{
  "agents": {
    "felix-primary": {
      "pid": 12345,
      "hostname": "LAPTOP-XYZ",
      "status": "active",
      "current_run_id": "S-0018",
      "started_at": "2026-01-27T20:00:00Z",
      "last_heartbeat": "2026-01-27T20:05:22Z",
      "stopped_at": null
    }
  }
}
```

## Related Documentation

- **S-0013**: Agent Settings & Registry (original runtime registry spec)
- **S-0020**: Consolidate Agent Settings (ID-based configuration)
- **felix/config.md**: General Felix configuration reference
