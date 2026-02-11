# S-0048: Project State Management with Realtime

**Phase:** 3 (Realtime Subscriptions)  
**Effort:** 6-8 hours  
**Priority:** High  
**Dependencies:** S-0047

---

## Narrative

This specification covers creating a React hook that manages project state (agents, runs, requirements) using Supabase Realtime subscriptions. This replaces all polling mechanisms with event-driven updates, providing instant state synchronization across all connected clients.

---

## Acceptance Criteria

### Project State Hook

- [ ] Create **app/frontend/src/hooks/useProjectState.ts** with:
  - Subscribe to `agents` table changes
  - Subscribe to `runs` table changes
  - Subscribe to `requirements` table changes
  - Maintain synchronized state in React
  - Handle initial data load
  - Handle real-time updates (INSERT, UPDATE, DELETE)

### Update Agent Dashboard

- [ ] Update **app/frontend/src/components/AgentDashboard.tsx** to:
  - Use `useProjectState()` hook instead of polling
  - Remove all `setInterval` calls
  - Remove API client calls for listing
  - Keep API client calls for actions (createRun, stopRun)

### Type Definitions

- [ ] Update **app/frontend/src/api/types.ts** with complete type definitions
- [ ] Ensure types match database schema exactly

---

## Technical Notes

### Project State Hook (hooks/useProjectState.ts)

```typescript
import { useState, useEffect } from "react";
import { supabase } from "../lib/supabase";
import { useSupabaseRealtime } from "./useSupabaseRealtime";
import { Agent, Run, Requirement } from "../api/types";

interface ProjectState {
  agents: Agent[];
  runs: Run[];
  requirements: Requirement[];
  loading: boolean;
  error: string | null;
}

export function useProjectState(projectId: string) {
  const [state, setState] = useState<ProjectState>({
    agents: [],
    runs: [],
    requirements: [],
    loading: true,
    error: null,
  });

  // Load initial data
  useEffect(() => {
    const loadInitialData = async () => {
      try {
        const [agentsRes, runsRes, requirementsRes] = await Promise.all([
          supabase.from("agents").select("*").eq("project_id", projectId),
          supabase
            .from("runs")
            .select("*, agent:agents(name), requirement:requirements(title)")
            .eq("project_id", projectId)
            .order("created_at", { ascending: false })
            .limit(50),
          supabase
            .from("requirements")
            .select("*")
            .eq("project_id", projectId)
            .order("created_at", { ascending: false }),
        ]);

        setState({
          agents: agentsRes.data || [],
          runs: runsRes.data || [],
          requirements: requirementsRes.data || [],
          loading: false,
          error: null,
        });
      } catch (err) {
        setState((prev) => ({
          ...prev,
          loading: false,
          error:
            err instanceof Error ? err.message : "Failed to load project state",
        }));
      }
    };

    loadInitialData();
  }, [projectId]);

  // Subscribe to agents changes
  useSupabaseRealtime<Agent>({
    table: "agents",
    filter: `project_id=eq.${projectId}`,
    onInsert: (agent) => {
      setState((prev) => ({
        ...prev,
        agents: [...prev.agents, agent],
      }));
    },
    onUpdate: ({ old, new: updated }) => {
      setState((prev) => ({
        ...prev,
        agents: prev.agents.map((a) => (a.id === updated.id ? updated : a)),
      }));
    },
    onDelete: (agent) => {
      setState((prev) => ({
        ...prev,
        agents: prev.agents.filter((a) => a.id !== agent.id),
      }));
    },
  });

  // Subscribe to runs changes
  useSupabaseRealtime<Run>({
    table: "runs",
    filter: `project_id=eq.${projectId}`,
    onInsert: (run) => {
      setState((prev) => ({
        ...prev,
        runs: [run, ...prev.runs].slice(0, 50), // Keep only 50 most recent
      }));
    },
    onUpdate: ({ old, new: updated }) => {
      setState((prev) => ({
        ...prev,
        runs: prev.runs.map((r) => (r.id === updated.id ? updated : r)),
      }));
    },
    onDelete: (run) => {
      setState((prev) => ({
        ...prev,
        runs: prev.runs.filter((r) => r.id !== run.id),
      }));
    },
  });

  // Subscribe to requirements changes
  useSupabaseRealtime<Requirement>({
    table: "requirements",
    filter: `project_id=eq.${projectId}`,
    onInsert: (requirement) => {
      setState((prev) => ({
        ...prev,
        requirements: [...prev.requirements, requirement],
      }));
    },
    onUpdate: ({ old, new: updated }) => {
      setState((prev) => ({
        ...prev,
        requirements: prev.requirements.map((r) =>
          r.id === updated.id ? updated : r,
        ),
      }));
    },
    onDelete: (requirement) => {
      setState((prev) => ({
        ...prev,
        requirements: prev.requirements.filter((r) => r.id !== requirement.id),
      }));
    },
  });

  return state;
}
```

### Updated Agent Dashboard (components/AgentDashboard.tsx)

```typescript
import React from 'react';
import { useProjectState } from '../hooks/useProjectState';
import { createRun, stopRun } from '../api/client';

export default function AgentDashboard({ projectId }: { projectId: string }) {
  const { agents, runs, loading, error } = useProjectState(projectId);

  const handleStartRun = async (agent_id: string) => {
    try {
      await createRun(agent_id);
      // Realtime subscription will update state automatically
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to start run');
    }
  };

  const handleStopRun = async (run_id: string) => {
    try {
      await stopRun(run_id);
      // Realtime subscription will update state automatically
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Failed to stop run');
    }
  };

  if (loading) return <div>Loading project state...</div>;
  if (error) return <div>Error: {error}</div>;

  return (
    <div className="agent-dashboard">
      <h2>Agents ({agents.length})</h2>
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
                <button onClick={() => handleStartRun(agent.id)} disabled={agent.status !== 'idle'}>
                  Start Run
                </button>
              </td>
            </tr>
          ))}
          {agents.length === 0 && (
            <tr>
              <td colSpan={4}>No agents registered. Start felix-agent.ps1 to register.</td>
            </tr>
          )}
        </tbody>
      </table>

      <h2>Recent Runs ({runs.length})</h2>
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
                  <button onClick={() => handleStopRun(run.id)}>Stop</button>
                )}
              </td>
            </tr>
          ))}
          {runs.length === 0 && (
            <tr>
              <td colSpan={5}>No runs yet. Click "Start Run" to begin.</td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
}
```

### Type Definitions (api/types.ts)

```typescript
export interface Requirement {
  id: string;
  project_id: string;
  title: string;
  spec_path: string;
  status: "planned" | "in-progress" | "completed" | "blocked";
  priority: "critical" | "high" | "medium" | "low";
  metadata: Record<string, any>;
  created_at: string;
  updated_at: string;
}
```

---

## Dependencies

**Depends On:**

- S-0047: Frontend Supabase Client and Realtime Hooks

**Blocks:**

- S-0049: Organization Context and Switcher

---

## Validation Criteria

### File Creation

- [ ] File exists: **app/frontend/src/hooks/useProjectState.ts**
- [ ] AgentDashboard updated to use useProjectState

### Build Verification

- [ ] Frontend builds: `cd app/frontend && npm run build` (exit code 0)
- [ ] No TypeScript errors: `npx tsc --noEmit`

### Polling Removal Verification

- [ ] No `setInterval` in AgentDashboard.tsx: `grep -n "setInterval" app/frontend/src/components/AgentDashboard.tsx` (should be empty)
- [ ] No polling intervals in useProjectState.ts
- [ ] Network tab shows no repeated API calls for list agents/runs

### Real-Time Update Test

**Setup:**

1. Start backend: `cd app/backend && python main.py`
2. Sign in to frontend with test user
3. Open AgentDashboard component
4. Open browser DevTools → Console

**Test INSERT:**

1. In Supabase Table Editor, insert a new agent
2. Verify agent appears in dashboard immediately (no page refresh)
3. Check console for "[Realtime] INSERT on agents" log

**Test UPDATE:**

1. Register an agent via API
2. In Table Editor, update agent status to 'running'
3. Verify status changes in dashboard immediately
4. Check console for "[Realtime] UPDATE on agents" log

**Test DELETE:**

1. In Table Editor, delete an agent
2. Verify agent disappears from dashboard immediately
3. Check console for "[Realtime] DELETE on agents" log

**Test Run Creation:**

1. Click "Start Run" button in dashboard
2. Verify new run appears in runs table immediately
3. Verify run status updates to 'running' automatically
4. No page refresh or manual reload needed

### Latency Test

- [ ] Use browser DevTools → Network → WebSocket tab
- [ ] Verify WebSocket connection to Supabase Realtime
- [ ] Measure latency: Insert agent in Table Editor → observe time until dashboard updates
- [ ] Expected: < 500ms latency (typically 50-200ms)

### Multi-Tab Test

- [ ] Open dashboard in 2 browser tabs
- [ ] In Tab 1, start a run
- [ ] Verify Tab 2 updates automatically
- [ ] Both tabs show identical state

---

## Rollback Strategy

If real-time updates fail:

1. Revert AgentDashboard to polling version (S-0042)
2. Keep useProjectState hook for future debugging
3. Investigate Supabase Realtime configuration

---

## Notes

- This spec removes ALL polling from frontend - fully event-driven
- useProjectState hook is reusable across multiple components
- Initial data load is still via REST API (one-time)
- Real-time updates handled by Realtime subscriptions (WebSocket)
- State updates are instant (< 500ms typical latency)
- Multiple tabs/windows stay synchronized automatically
- Runs table limited to 50 most recent (performance)
- Agent and requirement tables show all records
- Console logs help debug real-time events during development
- Production build can remove console.log statements
- RLS policies ensure users only see their org's data
- Personal org pattern (S-0046) ensures every user has a project

