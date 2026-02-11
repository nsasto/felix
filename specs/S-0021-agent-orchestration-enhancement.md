# S-0021: Agent Orchestration Enhancement - Display All Configured Agents

## Summary

Enhance the Agent Orchestration Dashboard (S-0014) to display **all configured agents from `agents.json`**, not just agents currently registered in the runtime registry. This provides complete visibility into available agent profiles and their current runtime status, enabling users to see what agents they can launch and manage the full agent lifecycle from a single view.

**Design Principle**: The dashboard is a command center for agent operations. Left panel shows "all registered agents and their current status", middle panel shows "what they're doing right now", right panel shows "what they've done". Toolbar provides direct control.

## Narrative

Currently, the Agent Orchestration Dashboard (S-0014) only displays agents that have actively registered themselves by running (stored in the backend's runtime registry from S-0013). This creates a "chicken-and-egg" problem: users can't see what agents are available to start, and the agent list appears empty until something is already running.

With the introduction of ID-based agent configuration in S-0020, we have a canonical source of "all possible agents" in `..felix/agents.json`. The dashboard should leverage this to show:

1. **Configured agents** that have never been started (status: `not-started`)
2. **Active agents** currently running with live heartbeats (status: `active`, `stale`)
3. **Inactive agents** that were running but have stopped (status: `inactive`, `stopped`)

This enhancement changes the **data source** for the agent list panel while keeping all UI layout, console streaming, run history, and control features exactly as specified in S-0014.

## Current Behavior (S-0014)

**Agent List Panel** displays only agents from runtime registry:

- Loads agents from `GET /api/agents` (runtime registry)
- Shows agents grouped by status: "Active Agents (N)", "Inactive Agents (N)"
- Empty state when no agents have registered: "No agents registered"

**Problem**: Users can't see or start agents that haven't been launched yet.

## Enhanced Behavior (S-0021)

**Agent List Panel** displays all configured agents with runtime status overlay:

- Loads **configured agents** from `GET /api/agents/config` (`..felix/agents.json`)
- Loads **runtime status** from `GET /api/agents` (runtime registry)
- Merges both sources to show complete picture
- Shows agents grouped by availability:
  - "Available Agents (N)" - not-started (never launched)
  - "Active Agents (N)" - active, stale (currently running)
  - "Inactive Agents (N)" - inactive, stopped (were running, now stopped)

**Benefit**: Users see all agents they've configured and can launch any of them directly from the dashboard.

## Acceptance Criteria

### Agent List Data Source

- [ ] Frontend loads configured agents from `GET /api/agents/config` endpoint
- [ ] Frontend loads runtime status from existing `GET /api/agents` endpoint
- [ ] Frontend merges both datasets:
  - For each configured agent, check if runtime status exists
  - If runtime status exists, use it (active, stale, inactive, stopped)
  - If no runtime status, mark as `not-started`
- [ ] Merged agent objects contain:
  ```typescript
  {
    id: number;              // From agents.json
    name: string;            // From agents.json
    executable: string;      // From agents.json
    args: string[];          // From agents.json
    status: 'not-started' | 'active' | 'stale' | 'inactive' | 'stopped';
    pid?: number;            // From runtime (if running)
    hostname?: string;       // From runtime (if running)
    current_run_id?: string; // From runtime (if running)
    last_heartbeat?: string; // From runtime (if running)
    started_at?: string;     // From runtime (if running)
  }
  ```

### Agent List Grouping

- [ ] Group agents into three sections (collapsible):
  1. **Available Agents (N)** - status: `not-started`
  2. **Active Agents (N)** - status: `active`, `stale`
  3. **Inactive Agents (N)** - status: `inactive`, `stopped`
- [ ] Default: All sections expanded
- [ ] Section headers show count in parentheses
- [ ] Sections can be collapsed/expanded independently

### Agent Card Display

**All Agents Show**:

- Agent name (from agents.json)
- Executable + args preview (e.g., "droid exec --skip...")
- Status icon based on merged status

**Not-Started Agents** (status: `not-started`):

- Status icon: ⚫ (gray dot)
- Text: "Ready to start"
- No PID, hostname, or heartbeat data
- Clicking selects agent but shows empty console ("Agent not running")

**Active/Running Agents** (status: `active`, `stale`):

- Status icon: 🟢 (active, pulsing slowly) or 🟡 (stale, static)
- Current requirement ID badge (e.g., "S-0012")
- Hostname (small, muted)
- Last heartbeat relative time (e.g., "2s ago")
- Clicking selects agent and loads live console output
- Active agent icon pulses with 2-second cycle (scale 1.0 → 1.2 → 1.0)

**Inactive Agents** (status: `inactive`, `stopped`):

- Status icon: ⚪ (inactive) or 🔴 (stopped)
- Last known requirement ID badge (if available)
- Last active timestamp (e.g., "Stopped 5m ago")
- Clicking selects agent but shows empty console ("Agent stopped")

### Toolbar Start Button Behavior

**When Not-Started Agent Selected**:

- Start button (▶️) is **enabled**
- Clicking Start opens requirement dropdown
- Selecting requirement calls `POST /api/agents/{agent_name}/start` with:
  ```json
  {
    "requirement_id": "S-0012",
    "agent_id": 0 // From selected agent's config
  }
  ```
- Backend spawns agent process using executable/args from agents.json

**When Running Agent Selected**:

- Start button is **disabled** (already running)
- Stop button is **enabled**

**When Stopped Agent Selected**:

- Start button is **enabled** (can restart)
- Stop button is **disabled**

### Empty States

- [ ] When no agents configured in agents.json:
  - "No agents configured" message
  - Link to Settings screen to add agents
- [ ] When agents configured but none selected:
  - Console panel: "Select an agent to view output"
  - Run history panel: Shows all runs across all agents

### Backend API Changes

- [ ] **New endpoint**: `GET /api/agents/config`
  - Returns array of agents from `..felix/agents.json`
  - Schema matches agents.json structure:
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
- [ ] **Modified endpoint**: `POST /api/agents/{agent_name}/start`
  - Accepts `agent_id` parameter to look up agent config
  - Spawns process using executable/args from agents.json
  - Registers agent in runtime registry on successful start

### Real-Time Updates

- [ ] Agent list refreshes every 2 seconds (same as S-0014)
- [ ] Refresh updates both:
  - Runtime status (active agents' heartbeats, current requirements)
  - Configured agents list (if agents.json changes, though rare)
- [ ] Status icons update based on heartbeat freshness:
  - 🟢 active: heartbeat < 10s
  - 🟡 stale: heartbeat 10s-60s
  - ⚪ inactive: heartbeat > 60s or process not found
  - ⚫ not-started: no runtime entry

## Technical Notes

### Frontend Agent Merge Logic

```typescript
// Load both data sources
const configuredAgents = await fetch("/api/agents/config").then((r) =>
  r.json(),
);
const runtimeAgents = await fetch("/api/agents").then((r) => r.json());

// Merge: configured agents are source of truth
const displayAgents = configuredAgents.agents.map((config) => {
  const runtime = runtimeAgents.agents?.[config.name];

  if (!runtime) {
    return {
      ...config,
      status: "not-started" as const,
    };
  }

  return {
    ...config,
    status: runtime.status,
    pid: runtime.pid,
    hostname: runtime.hostname,
    current_run_id: runtime.current_run_id,
    last_heartbeat: runtime.last_heartbeat,
    started_at: runtime.started_at,
    stopped_at: runtime.stopped_at,
  };
});

// Group by status
const available = displayAgents.filter((a) => a.status === "not-started");
const active = displayAgents.filter((a) =>
  ["active", "stale"].includes(a.status),
);
const inactive = displayAgents.filter((a) =>
  ["inactive", "stopped"].includes(a.status),
);
```

### Backend Agent Start Implementation

```python
@app.post("/api/agents/{agent_name}/start")
async def start_agent(agent_name: str, request: StartAgentRequest):
    # Load agent config from agents.json
    agents_config = load_agents_json()
    agent_config = next((a for a in agents_config['agents'] if a['name'] == agent_name), None)

    if not agent_config:
        raise HTTPException(404, f"Agent {agent_name} not found in configuration")

    # Spawn process using agent's executable and args
    executable = agent_config['executable']
    args = agent_config['args']

    process = subprocess.Popen(
        [executable] + args + [project_path, '--requirement-id', request.requirement_id],
        cwd=agent_config.get('working_directory', '.'),
        env={**os.environ, **agent_config.get('environment', {})}
    )

    # Agent will self-register via POST /api/agents/register when it starts
    return {"status": "started", "pid": process.pid}
```

### Status Determination Logic

Backend determines agent status based on heartbeat:

```python
def get_agent_status(agent_name: str, registry: dict) -> str:
    if agent_name not in registry:
        return 'not-started'

    agent = registry[agent_name]

    if agent.get('stopped_at'):
        return 'stopped'

    if not agent.get('last_heartbeat'):
        return 'inactive'

    heartbeat_age = (datetime.now() - parse_timestamp(agent['last_heartbeat'])).seconds

    if heartbeat_age < 10:
        return 'active'
    elif heartbeat_age < 60:
        return 'stale'
    else:
        return 'inactive'
```

## UI Impact Summary

**No Changes** (stays exactly as S-0014):

- Three-panel layout
- Console streaming (WebSocket)
- Run history panel
- Toolbar controls (start, stop, settings, refresh)
- Resizable panels
- Run detail slide-out
- Responsive design

**Only Changes**:

- Agent list data source (configured + runtime instead of runtime only)
- Agent grouping (3 sections instead of 2)
- Agent card display (shows executable/args for not-started agents)
- Start button availability (enabled for not-started agents)
- Empty state messaging

## Dependencies

- **S-0020** (Consolidate Agent Settings) - Requires `..felix/agents.json` with ID-based configuration
- **S-0013** (Agent Settings & Registry) - Requires runtime registry for active agent status
- **S-0014** (Agent Orchestration Dashboard) - Enhances this spec's agent list panel
- **S-0003** (Frontend Observer UI) - Requires React infrastructure
- **S-0002** (Backend API) - Requires agent management endpoints

## Non-Goals

- Editing agent configuration from dashboard (use Settings screen, S-0020)
- Creating new agents from dashboard (use Settings screen, S-0020)
- Deleting agents from dashboard (use Settings screen, S-0020)
- Showing agent configuration details in dashboard (just name/executable preview)
- Multi-agent selection or batch operations
- Agent templates or presets

## Validation Criteria

- [ ] Backend endpoint works: `curl http://localhost:8080/api/agents/config` returns agents from ..felix/agents.json
- [ ] Dashboard shows not-started agents: Add agent to agents.json, refresh dashboard, verify it appears in "Available Agents"
- [ ] Start not-started agent: Select not-started agent, click Start, select requirement, verify agent launches
- [ ] Agent transitions to active: After starting, verify agent moves from "Available" to "Active Agents" section
- [ ] Agent grouping correct: Have mix of not-started, active, and stopped agents, verify correct grouping
- [ ] Manual verification: Open dashboard, confirm all configured agents visible regardless of runtime status
- [ ] Manual verification: Start a not-started agent, confirm it begins streaming console output
- [ ] Manual verification: Stop an active agent, confirm it moves to "Inactive Agents" section

## Migration Notes

**For Existing Deployments**:

- No database migration needed (agents.json already exists from S-0020)
- No breaking changes to runtime registry (S-0013 remains unchanged)
- Frontend gracefully handles missing runtime data (shows as not-started)
- Backend /api/agents/config endpoint is new, additive (doesn't break existing UI)

**Backward Compatibility**:

- If agents.json doesn't exist, falls back to showing only runtime agents (S-0014 behavior)
- If backend doesn't support /api/agents/config, frontend shows only runtime agents
- Existing start/stop/register flows unchanged



