# S-0020: Consolidate Agent Settings Management

## Narrative

As a Felix user, I want to manage all agent configurations in one centralized location with clear visual indicators, so I understand which agent is active, which is the system default, and can safely add, edit, or remove agents without breaking my configuration.

## Problem

Currently, agent configuration is split between two locations:

- `felix/agents.json` contains a list of available agent configurations
- `felix/config.json` contains the active agent configuration inline

This creates several issues:

- **Duplication**: Active agent config exists in both files
- **Sync problems**: Changes in one location don't automatically reflect in the other
- **Unclear relationship**: Users don't know if agents.json is a "library" or if config.json is the source of truth
- **Orphaned references**: If config references an agent that doesn't exist, the system breaks
- **Deletion safety**: No protection against deleting the last available agent

## Solution

Implement an ID-based reference system where:

1. `felix/agents.json` is the single source of truth for all agent configurations
2. `felix/config.json` references the active agent by ID: `agent.agent_id`
3. Agent ID 0 is the system default and cannot be deleted
4. UI clearly shows which agent is active and which is the protected default

## Acceptance Criteria

### Agent ID System

- [ ] Add `id` field to each agent in agents.json (integer, starting from 0)
- [ ] Agent ID 0 is reserved as the system default
- [ ] Agent ID 0 always exists and cannot be deleted
- [ ] New agents receive next available ID (1, 2, 3, etc.)
- [ ] IDs are never reused after deletion

### Configuration Structure

- [ ] `felix/config.json` contains `agent.agent_id` (integer) instead of full agent object
- [ ] Felix agent reads `agent.agent_id` from config.json at startup
- [ ] Felix agent looks up full agent configuration from agents.json by ID
- [ ] If referenced agent_id doesn't exist, fallback to ID 0 with warning logged

### Backend API

- [ ] GET `/api/agents` returns all agents from agents.json
- [ ] POST `/api/agents` creates new agent with next available ID
- [ ] PUT `/api/agents/{id}` updates agent configuration
- [ ] DELETE `/api/agents/{id}` deletes agent (rejects if id = 0)
- [ ] GET `/api/settings` includes current agent_id from config.json
- [ ] PUT `/api/settings` updates agent_id in config.json

### UI - Agents List Screen

- [ ] Single "Agents" section in Settings (global, not project-dependent)
- [ ] Display all agents from agents.json in a list/grid
- [ ] Each agent card shows: name, executable, args, ID
- [ ] Agent ID 0 displays **🔒 System Default** badge
- [ ] Currently active agent (matching config.agent_id) displays **✓ Active** badge
- [ ] Agent ID 0's delete button is disabled with tooltip: "System default cannot be deleted"
- [ ] Other agents show enabled delete button
- [ ] "Set as Active" button on each agent (updates config.agent_id)

### Agent Actions

- [ ] **Add Agent**: Form with name, executable, args; creates with next ID
- [ ] **Edit Agent**: Modal/form to update agent settings (including ID 0)
- [ ] **Delete Agent**: Confirmation dialog, only enabled for ID > 0
- [ ] **Set Active**: Clicking updates config.json's agent_id field
- [ ] All changes immediately persist to agents.json and config.json

### Validation & Safety

- [ ] Backend rejects DELETE request for agent ID 0 (returns 403 Forbidden)
- [ ] Frontend disables delete button for agent ID 0
- [ ] On startup, verify config.agent_id exists in agents.json
- [ ] If agent_id missing/invalid, auto-correct to 0 and log warning
- [ ] Display warning banner in UI if fallback to ID 0 occurred

### Migration

- [ ] If config.json has legacy inline `agent` object (not agent_id):
  - Create agents.json with that agent as ID 0
  - Update config.json to use `agent.agent_id: 0`
- [ ] If agents.json exists but config.json has no agent_id:
  - Set `agent.agent_id: 0` (use first/default agent)
- [ ] Migration runs automatically on backend startup

### Error Handling

- [ ] If agent_id references non-existent agent: log warning, fallback to ID 0
- [ ] Display user-friendly error: "⚠️ Configured agent (ID X) not found. Using system default."
- [ ] Backend returns 404 for operations on non-existent agent IDs
- [ ] Frontend shows inline validation errors on agent form

## Technical Notes

**felix/agents.json Schema:**

```json
{
  "agents": [
    {
      "id": 0,
      "name": "Felix Primary",
      "executable": "droid",
      "args": ["exec", "--skip-permissions-unsafe"],
      "working_directory": ".",
      "environment": {}
    },
    {
      "id": 1,
      "name": "Claude Sonnet",
      "executable": "claude",
      "args": ["--model", "sonnet"],
      "working_directory": ".",
      "environment": { "ANTHROPIC_API_KEY": "..." }
    }
  ]
}
```

**felix/config.json Changes:**

```json
{
  "version": "0.1.0",
  "executor": {
    "mode": "local",
    "max_iterations": 100
  },
  "agent": {
    "agent_id": 0
  },
  "paths": {
    "specs": "specs"
  }
}
```

**Agent Lookup Logic (PowerShell agent):**

```powershell
# Load config
$config = Get-Content "felix/config.json" | ConvertFrom-Json
$agentId = $config.agent.agent_id

# Load agents registry
$agentsData = Get-Content "felix/agents.json" | ConvertFrom-Json
$agent = $agentsData.agents | Where-Object { $_.id -eq $agentId }

if (-not $agent) {
    Write-Warning "Agent ID $agentId not found. Falling back to system default (ID 0)."
    $agent = $agentsData.agents | Where-Object { $_.id -eq 0 }

    # Auto-correct config
    $config.agent.agent_id = 0
    $config | ConvertTo-Json -Depth 10 | Set-Content "felix/config.json"
}

# Use $agent.executable, $agent.args, etc.
```

**Backend Validation:**

```python
@app.delete("/api/agents/{agent_id}")
def delete_agent(agent_id: int):
    if agent_id == 0:
        raise HTTPException(
            status_code=403,
            detail="Cannot delete system default agent (ID 0)"
        )

    agents_data = load_agents_json()
    agents_data["agents"] = [a for a in agents_data["agents"] if a["id"] != agent_id]
    save_agents_json(agents_data)

    return {"status": "deleted", "agent_id": agent_id}
```

**UI Component Structure:**

- `AgentsListScreen.tsx` - Main settings screen for agents
- `AgentCard.tsx` - Individual agent display with badges
- `AgentForm.tsx` - Add/edit agent modal
- `AgentDeleteDialog.tsx` - Confirmation dialog
- Reuse existing Settings screen infrastructure from S-0007

**Don't assume not implemented**: Check existing SettingsScreen.tsx and backend agents.py router. May have partial implementation that needs refactoring rather than building from scratch.

## Dependencies

- S-0007 (Settings Screen) - requires settings UI infrastructure
- S-0013 (Agent Settings Registry) - builds on agent registry concept
- S-0019 (Settings Not Project Dependent) - settings must be global, not per-project

## Non-Goals

- Multiple active agents running simultaneously (single active agent only)
- Agent capability negotiation or versioning
- Cloud-based agent registry sync
- Agent authentication or permissions
- Automatic agent discovery

## Validation Criteria

- [ ] Backend starts: `python app/backend/main.py` (exit code 0)
- [ ] Agents endpoint works: `curl http://localhost:8080/api/agents` (status 200, returns agents array)
- [ ] Frontend starts: `cd app/frontend && npm run dev` (exit code 0)
- [ ] Delete system default rejected: `curl -X DELETE http://localhost:8080/api/agents/0` (status 403)
- [x] Agent ID 0 shows locked badge: Manual verification - view Agents screen, verify ID 0 has system default indicator
- [x] Active agent shows badge: Manual verification - verify currently selected agent displays active indicator
- [x] Delete disabled for ID 0: Manual verification - confirm delete button disabled/hidden for agent ID 0
- [x] Set active works: Manual verification - click "Set as Active" on different agent, verify config.json updated
- [x] Orphaned reference handled: Manual verification - manually edit config.json with invalid agent_id, verify fallback to ID 0 with warning
