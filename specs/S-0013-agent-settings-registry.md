# S-0013: Agent Settings & Registry

## Narrative

As a developer managing Felix agents, I need a centralized configuration system and registry to identify agents, track their status, and configure their runtime settings, so I can coordinate multiple agents across different machines and environments without confusion or conflicts.

Currently, Felix agents run without formal identity or registration. When scaling to multiple agents (cloud-managed or multi-machine), there's no way to distinguish them, track their activity, or configure agent-specific settings. This spec introduces `felix/agents.json` as the agent registry and extends `felix/config.json` with agent identity settings, accessible via a global Settings screen.

**Design Principle**: Agent identity and registration are global concerns (not project-specific). The registry tracks runtime state (PID, heartbeat), while config stores user-defined settings (name, executable).

## Acceptance Criteria

### Agent Identity in Config

- [ ] Add `agent.name` field to `felix/config.json` (user-configurable string)
- [ ] Default agent name: `"felix-primary"` if not specified
- [ ] Agent name must be unique per registry (validation on save)
- [ ] Agent name used as identifier for registration and API calls
- [ ] Existing `agent.executable` and `agent.args` remain unchanged

### Agent Registry File

- [ ] Create `felix/agents.json` file structure in project root
- [ ] Schema includes: agents object with agent_name as key
- [ ] Each agent entry contains: `pid`, `hostname`, `status`, `current_run_id`, `started_at`, `last_heartbeat`, `stopped_at`
- [ ] Status values: `"active"`, `"inactive"`, `"stopped"`
- [ ] File created automatically if missing (empty agents object)
- [ ] File tracked in git (with .gitignore exception for user-specific overrides if needed)

### Backend Agent Management

- [ ] Endpoint: `POST /api/agents/register` - registers agent with name, pid, hostname
- [ ] Endpoint: `POST /api/agents/{name}/heartbeat` - updates last_heartbeat timestamp
- [ ] Endpoint: `GET /api/agents` - returns all registered agents with status
- [ ] Endpoint: `POST /api/agents/{name}/stop` - marks agent as stopped
- [ ] Backend reads/writes `felix/agents.json` on agent operations
- [ ] Backend validates agent name uniqueness on registration
- [ ] Backend marks agents inactive if heartbeat > 10 seconds old

### Agent Startup Registration

- [ ] Felix agent reads `agent.name` from config on startup
- [ ] Agent calls `/api/agents/register` with: name, PID, hostname, timestamp
- [ ] Agent sends heartbeat every 5 seconds to `/api/agents/{name}/heartbeat`
- [ ] Registration updates `felix/agents.json` with current agent state
- [ ] If agent_name already exists, updates existing entry (handles restarts)

### Settings Screen UI (Global)

- [ ] Add "Agents" section to Settings screen (not under Projects)
- [ ] Show "Agent Configuration" card with editable fields:
  - Agent Name (text input)
  - Executable (text input, default: "droid")
  - Arguments (text input, default: "exec --skip-permissions-unsafe")
- [ ] "Save" button writes changes to `felix/config.json`
- [ ] Validation: Agent name cannot be empty, must be alphanumeric with hyphens/underscores
- [ ] Show registered agents list (read-only) below configuration:
  - Agent name, status badge (🟢 active, ⚪ inactive, 🔴 stopped)
  - Current requirement ID (if active)
  - Last heartbeat timestamp (relative time: "2s ago", "5m ago")
  - Hostname
- [ ] Refresh button to reload agent registry from backend

### Agent State Tracking

- [ ] Backend checks agent liveness on startup (if PID in registry still exists)
- [ ] Mark agents inactive if process not found or heartbeat stale
- [ ] When agent reconnects after backend restart, status updates to active
- [ ] Stopped agents remain in registry with stopped_at timestamp

### Error Handling

- [ ] Agent registration fails gracefully if backend unreachable (agent continues)
- [ ] Settings UI shows error if agent name conflicts with existing active agent
- [ ] Backend returns 409 Conflict if duplicate agent name with active status
- [ ] Frontend displays validation errors inline in settings form

## Technical Notes

**felix/agents.json Schema:**

```json
{
  "agents": {
    "felix-primary": {
      "pid": 12345,
      "hostname": "DESKTOP-ABC",
      "status": "active",
      "current_run_id": "S-0012",
      "started_at": "2026-01-27T14:30:00Z",
      "last_heartbeat": "2026-01-27T14:35:22Z",
      "stopped_at": null
    },
    "felix-backend": {
      "pid": 12346,
      "hostname": "LAPTOP-XYZ",
      "status": "inactive",
      "current_run_id": null,
      "started_at": "2026-01-27T13:00:00Z",
      "last_heartbeat": "2026-01-27T13:45:00Z",
      "stopped_at": "2026-01-27T13:45:10Z"
    }
  }
}
```

**felix/config.json Changes:**

```json
{
  "agent": {
    "name": "felix-primary", // NEW: User-configurable agent name
    "executable": "droid",
    "args": ["exec", "--skip-permissions-unsafe"],
    "working_directory": ".",
    "environment": {}
  }
}
```

**PowerShell Agent Registration (felix-agent.ps1):**

```powershell
# On startup
$config = Get-Content "felix/config.json" | ConvertFrom-Json
$agentName = $config.agent.name ?? "felix-primary"

$registration = @{
    agent_name = $agentName
    pid = $PID
    hostname = $env:COMPUTERNAME
    started_at = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json

Invoke-RestMethod -Method POST `
    -Uri "http://localhost:8080/api/agents/register" `
    -Body $registration `
    -ContentType "application/json"

# Heartbeat loop (background job)
while ($true) {
    Start-Sleep -Seconds 5
    $heartbeat = @{
        current_run_id = $currentRequirementId
    } | ConvertTo-Json

    Invoke-RestMethod -Method POST `
        -Uri "http://localhost:8080/api/agents/$agentName/heartbeat" `
        -Body $heartbeat `
        -ContentType "application/json"
}
```

**Backend Agent Liveness Check:**

```python
import psutil
from datetime import datetime, timedelta

def check_agent_status(agent: AgentEntry) -> str:
    # Check heartbeat staleness
    if agent.last_heartbeat:
        age = datetime.utcnow() - agent.last_heartbeat
        if age > timedelta(seconds=10):
            return "inactive"

    # Check if process still exists (local agents only)
    if agent.hostname == current_hostname():
        if not psutil.pid_exists(agent.pid):
            return "inactive"

    return agent.status
```

**Settings Component Integration:**

- Reuse existing Settings screen infrastructure from S-0007
- Add AgentSettings component below ProjectSettings
- No project selection required (agent settings are global)

## Dependencies

- S-0007 (Settings Screen) - requires settings UI infrastructure
- S-0002 (Backend API) - requires API server for endpoints

## Non-Goals

- Multi-user authentication for agent operations (all agents trusted)
- Agent-to-agent communication or coordination
- Cloud-based agent registry (local file-based only)
- Agent capability negotiation or versioning
- Automatic agent discovery (manual registration only)

## Validation Criteria

- [ ] Agent registers on startup: `curl http://localhost:8080/api/agents` shows new agent
- [ ] Heartbeat updates: Check felix/agents.json file, verify last_heartbeat field updates every 5s
- [x] Settings UI saves config: Manual verification - edit agent name, save, check config.json
- [x] Agent list shows status: Manual verification - view registered agents in settings
- [x] Stale agents marked inactive: Manual verification - stop agent, wait 15s, check status changes
