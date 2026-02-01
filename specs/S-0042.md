# S-0042: Frontend API Client and Dashboard

**Phase:** 1 (Core Orchestration)  
**Effort:** 6-8 hours  
**Priority:** High  
**Dependencies:** S-0041

---

## Narrative

This specification covers implementing a frontend API client to communicate with the new database-backed backend endpoints, and updating the agent dashboard to display real-time agent status and run information. This replaces the file-based polling removed in Phase -1 with API-driven updates (with temporary polling until Phase 3 implements Realtime subscriptions).

---

## Acceptance Criteria

### API Client Module

- [ ] Create **app/frontend/src/api/client.ts** with functions:
  - `registerAgent(agent_id, name, type, metadata)`
  - `listAgents()`
  - `getAgent(agent_id)`
  - `createRun(agent_id, requirement_id, metadata)`
  - `stopRun(run_id)`
  - `listRuns(limit)`
  - `getRun(run_id)`

### API Types

- [ ] Create **app/frontend/src/api/types.ts** with TypeScript interfaces:
  - `Agent`
  - `Run`
  - `AgentListResponse`
  - `RunListResponse`

### Agent Dashboard Component

- [ ] Create **app/frontend/src/components/AgentDashboard.tsx**
- [ ] Display list of agents with status indicators
- [ ] Display list of recent runs
- [ ] Show agent connection status (connected/disconnected)
- [ ] "Start Run" button for each agent
- [ ] "Stop Run" button for active runs

### Polling Mechanism (Temporary)

- [ ] Poll `/api/agents` every 3 seconds to refresh agent list
- [ ] Poll `/api/agents/runs` every 3 seconds to refresh run list
- [ ] Clear polling intervals on component unmount

### Wire Up in Main App

- [ ] Import AgentDashboard component in **app/frontend/src/App.tsx**
- [ ] Render AgentDashboard in main layout
- [ ] Ensure console panel still works

---

## Technical Notes

### API Client (api/client.ts)

```typescript
const API_BASE = "http://localhost:8080/api";

export async function registerAgent(
  agent_id: string,
  name: string,
  type: string = "ralph",
  metadata: Record<string, any> = {},
) {
  const response = await fetch(`${API_BASE}/agents/register`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ agent_id, name, type, metadata }),
  });
  return response.json();
}

export async function listAgents() {
  const response = await fetch(`${API_BASE}/agents`);
  return response.json();
}

export async function getAgent(agent_id: string) {
  const response = await fetch(`${API_BASE}/agents/${agent_id}`);
  return response.json();
}

export async function createRun(
  agent_id: string,
  requirement_id: string | null = null,
  metadata: Record<string, any> = {},
) {
  const response = await fetch(`${API_BASE}/agents/runs`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ agent_id, requirement_id, metadata }),
  });
  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.detail || "Failed to create run");
  }
  return response.json();
}

export async function stopRun(run_id: string) {
  const response = await fetch(`${API_BASE}/agents/runs/${run_id}/stop`, {
    method: "POST",
  });
  return response.json();
}

export async function listRuns(limit: number = 50) {
  const response = await fetch(`${API_BASE}/agents/runs?limit=${limit}`);
  return response.json();
}

export async function getRun(run_id: string) {
  const response = await fetch(`${API_BASE}/agents/runs/${run_id}`);
  return response.json();
}
```

### API Types (api/types.ts)

```typescript
export interface Agent {
  id: string;
  project_id: string;
  name: string;
  type: string;
  status: "idle" | "running" | "stopped" | "error";
  heartbeat_at: string | null;
  metadata: Record<string, any>;
  created_at: string;
  updated_at: string;
}

export interface Run {
  id: string;
  project_id: string;
  agent_id: string;
  requirement_id: string | null;
  status: "pending" | "running" | "completed" | "failed" | "cancelled";
  started_at: string | null;
  completed_at: string | null;
  error: string | null;
  metadata: Record<string, any>;
  agent_name?: string;
  requirement_title?: string;
}

export interface AgentListResponse {
  agents: Agent[];
  count: number;
}

export interface RunListResponse {
  runs: Run[];
  count: number;
}
```

### Agent Dashboard Component (components/AgentDashboard.tsx)

```typescript
import React, { useEffect, useState } from 'react';
import { listAgents, listRuns, createRun, stopRun } from '../api/client';
import { Agent, Run } from '../api/types';

export default function AgentDashboard() {
  const [agents, setAgents] = useState<Agent[]>([]);
  const [runs, setRuns] = useState<Run[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Poll agents and runs every 3 seconds
  useEffect(() => {
    const fetchData = async () => {
      try {
        const [agentData, runData] = await Promise.all([
          listAgents(),
          listRuns(20)
        ]);
        setAgents(agentData.agents);
        setRuns(runData.runs);
        setLoading(false);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to fetch data');
        setLoading(false);
      }
    };

    fetchData();
    const interval = setInterval(fetchData, 3000);

    return () => clearInterval(interval);
  }, []);

  const handleStartRun = async (agent_id: string) => {
    try {
      await createRun(agent_id);
      // Poll will pick up new run shortly
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to start run');
    }
  };

  const handleStopRun = async (run_id: string) => {
    try {
      await stopRun(run_id);
      // Poll will pick up status change shortly
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to stop run');
    }
  };

  if (loading) return <div>Loading...</div>;
  if (error) return <div>Error: {error}</div>;

  return (
    <div className="agent-dashboard">
      <h2>Agents</h2>
      <table>
        <thead>
          <tr>
            <th>Name</th>
            <th>Status</th>
            <th>Last Heartbeat</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {agents.map(agent => (
            <tr key={agent.id}>
              <td>{agent.name}</td>
              <td>
                <span className={`status-${agent.status}`}>{agent.status}</span>
              </td>
              <td>{agent.heartbeat_at ? new Date(agent.heartbeat_at).toLocaleTimeString() : 'Never'}</td>
              <td>
                <button onClick={() => handleStartRun(agent.id)}>
                  Start Run
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <h2>Recent Runs</h2>
      <table>
        <thead>
          <tr>
            <th>Agent</th>
            <th>Status</th>
            <th>Started</th>
            <th>Completed</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {runs.map(run => (
            <tr key={run.id}>
              <td>{run.agent_name || run.agent_id}</td>
              <td>
                <span className={`status-${run.status}`}>{run.status}</span>
              </td>
              <td>{run.started_at ? new Date(run.started_at).toLocaleTimeString() : '-'}</td>
              <td>{run.completed_at ? new Date(run.completed_at).toLocaleTimeString() : '-'}</td>
              <td>
                {run.status === 'running' && (
                  <button onClick={() => handleStopRun(run.id)}>
                    Stop
                  </button>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
```

---

## Dependencies

**Depends On:**

- S-0041: Console Streaming WebSocket

**Blocks:**

- S-0043: Supabase Project Setup and Schema Migration (Phase 2)

---

## Validation Criteria

### File Creation

- [ ] File exists: **app/frontend/src/api/client.ts**
- [ ] File exists: **app/frontend/src/api/types.ts**
- [ ] File exists: **app/frontend/src/components/AgentDashboard.tsx**

### Build Verification

- [ ] Frontend builds: `cd app/frontend && npm run build` (exit code 0)
- [ ] No TypeScript errors: `npx tsc --noEmit`

### Integration Test

1. **Start backend:**

```bash
cd app/backend && python main.py
```

2. **Register test agent:**

```bash
curl -X POST http://localhost:8080/api/agents/register \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "test-agent-1", "name": "Test Agent"}'
```

3. **Connect agent to control WebSocket:**

```bash
wscat -c ws://localhost:8080/api/agents/test-agent-1/control
```

4. **Start frontend:**

```bash
cd app/frontend && npm run dev
```

5. **Verify dashboard:**

- [ ] Dashboard shows test agent in agents table
- [ ] Agent status is 'idle'
- [ ] "Start Run" button is visible
- [ ] Click "Start Run" → new run appears in runs table
- [ ] Run status changes from 'pending' to 'running'
- [ ] Click "Stop" button → run status changes to 'cancelled'

### Polling Verification

- [ ] Open browser DevTools → Network tab
- [ ] Verify requests to `/api/agents` every 3 seconds
- [ ] Verify requests to `/api/agents/runs` every 3 seconds
- [ ] Close dashboard → verify polling stops

---

## Rollback Strategy

If issues arise:

1. Remove api/ directory
2. Remove AgentDashboard component
3. Restore previous dashboard from Phase -1 backup

---

## Notes

- Polling is temporary - Phase 3 will replace with Supabase Realtime subscriptions
- 3-second poll interval balances responsiveness and server load
- Console streaming WebSocket (preserved from Phase -1) continues to work
- Dashboard provides basic orchestration UI for testing
- Error handling displays user-friendly messages
- Status indicators use CSS classes for color coding
- Agent connection status derived from heartbeat_at timestamp
- Phase 2 will add proper authentication
- Phase 3 will remove polling and add real-time updates
