# S-0014: Agent Orchestration Dashboard

## Narrative

As a developer managing Felix agents, I need a real-time control panel to monitor active agents, view their live console output, manage their lifecycle, and review historical run data, so I can effectively coordinate agent work, debug issues, and track progress across multiple agents and requirements.

The current Orchestration tab provides basic run monitoring but lacks agent-level visibility, live console streaming, and comprehensive control features. This spec redesigns the Orchestration tab as a full-featured agent dashboard with three-panel layout: agent list, live console, and run history, with toolbar controls for starting/stopping agents and viewing process details.

**Design Principle**: The dashboard is a command center for agent operations. Left panel shows "all registered agents and their current status", middle panel shows "what they're doing right now", right panel shows "what they've done". Toolbar provides direct control.

## Acceptance Criteria

### Layout & Navigation

- [ ] Replace current Orchestration tab with new Agent Dashboard
- [ ] Three-panel horizontal layout: Agent List, Live Console , Run History 
- [ ] Toolbar at top of dashboard (above all panels)
- [ ] Default selected agent: first active agent, or none if no agents active

### Left Panel: Agent List

- [ ] Grouped by status: "Active Agents (N)", "Inactive Agents (N)"
- [ ] Each agent card shows:
  - Status icon (🟢 active, 🟡 stale, ⚪ inactive, 🔴 stopped)
  - Agent name (bold, truncated with ellipsis if long)
  - Current requirement ID badge (e.g., "S-0012") if active
  - Hostname (small, muted text)
  - Last heartbeat relative time (e.g., "2s ago") if active
- [ ] Selected agent highlighted with border/background color
- [ ] Clicking agent selects it and updates middle/right panels
- [ ] Empty state when no agents: "No agents registered" with link to Settings
- [ ] Auto-refresh agent list every 2 seconds

### Middle Panel: Live Console

- [ ] Header shows selected agent name and current requirement ID
- [ ] Console displays real-time output from selected agent's current run
- [ ] Output styled with:
  - Monospace font (Fira Code)
  - Dark background (theme-bg-deepest)
  - ANSI color code support (errors red, success green, etc.)
  - Auto-scroll to bottom when new output arrives
- [ ] Lock scroll button (📌 icon) to disable auto-scroll
- [ ] Clear console button (🗑️ icon) to clear current view (doesn't affect logs)
- [ ] Empty state when no agent selected: "Select an agent to view console output"
- [ ] Empty state when agent idle: "Agent idle - waiting for work"
- [ ] WebSocket connection for real-time streaming (or 1s polling fallback)

### Right Panel: Run History

- [ ] Header shows "Run History" with filter/search icon
- [ ] List of all runs, sorted by start time descending (newest first)
- [ ] Each run item shows:
  - Run ID (e.g., "2026-01-27T14:30:00")
  - Requirement ID badge (e.g., "S-0012")
  - Status badge (✅ complete, ❌ failed, ⚠️ blocked, 🔄 running)
  - Agent name (small, muted)
  - Start time (relative, e.g., "5m ago")
  - Exit code if completed (e.g., "exit: 0")
- [ ] Clicking run opens slide-out with full run details (reuse S-0011 pattern)
- [ ] Slide-out shows: Report, Output Log, Plan tabs
- [ ] Filter controls:
  - Requirement ID dropdown (all requirements)
  - Status checkboxes (completed, failed, blocked, running)
  - Agent name dropdown (all agents)
  - Date range picker
- [ ] Search box for text search in run IDs
- [ ] Pagination or infinite scroll for large run lists
- [ ] Auto-refresh run list every 5 seconds

### Toolbar (Top Bar)

- [ ] Positioned above three panels, full width
- [ ] Left section shows selected agent info:
  - Agent name
  - Process ID (PID)
  - Uptime (e.g., "Running for 2h 15m")
  - Hostname
- [ ] Right section shows controls:
  - Start button (▶️) - opens dropdown to select requirement ID
  - Stop button (⏹️) - opens dropdown with "Graceful Stop" and "Force Kill" options
  - Settings button (⚙️) - opens global Settings screen (S-0013)
  - Refresh button (🔄) - manually refreshes all data
- [ ] Start dropdown lists available requirements (status: planned or blocked)
- [ ] Stop actions:
  - Graceful Stop: sends SIGTERM, waits for current task to finish
  - Force Kill: sends SIGKILL, terminates immediately
- [ ] Buttons disabled when no agent selected or action not applicable

### Real-Time Updates

- [ ] Agent list updates every 2 seconds (status, heartbeat, current requirement)
- [ ] Console output streams in real-time via WebSocket or 1s polling
- [ ] Run history updates every 5 seconds (new runs, status changes)
- [ ] Toolbar info updates when agent selection changes
- [ ] Visual indicator (pulsing dot) shows live data streaming

### Run Detail Slide-Out (Reuse S-0011)

- [ ] Clicking run from history list opens slide-out from right
- [ ] Slide-out displays run artifacts in tabs: Report, Output Log, Plan
- [ ] Report tab: Markdown-rendered report.md
- [ ] Output Log tab: Markdown-rendered output.log
- [ ] Plan tab: Markdown-rendered plan-{requirement_id}.md
- [ ] Slide-out width: 60vw (min 500px, max 800px)
- [ ] ESC key or backdrop click closes slide-out
- [ ] Close button (X) in top-right corner

### Responsive Design

- [ ] Dashboard layout works on screens 1280px+ width
- [ ] Panels collapse to minimum widths on smaller screens
- [ ] Mobile layout: stacked panels (out of scope for MVP)

### Error Handling

- [ ] Show error banner if backend connection lost
- [ ] Retry failed WebSocket connections automatically
- [ ] Gracefully handle agent disconnection (mark as stale/inactive)
- [ ] Display error message if start/stop commands fail

## Technical Notes

**Component Architecture:**

```
AgentDashboard
├── DashboardToolbar
│   ├── AgentInfo (left)
│   └── AgentControls (right: start, stop, settings, refresh)
├── PanelContainer (resizable)
│   ├── AgentListPanel (~20%)
│   │   └── AgentCard[] (grouped by status)
│   ├── LiveConsolePanel (~50%)
│   │   ├── ConsoleHeader (agent name, clear, lock)
│   │   └── ConsoleOutput (ANSI terminal)
│   └── RunHistoryPanel (~30%)
│       ├── HistoryFilters (search, filters)
│       └── RunListItem[] (clickable)
└── RunDetailSlideOut (conditional, reuse from S-0011)
```

**WebSocket for Console Streaming:**

```typescript
// Frontend
const ws = new WebSocket(`ws://localhost:8080/api/agents/${agentName}/console`);
ws.onmessage = (event) => {
  const output = event.data;
  appendToConsole(output);
};

// Backend (Python with FastAPI)
@app.websocket("/api/agents/{agent_name}/console")
async def agent_console_stream(websocket: WebSocket, agent_name: str):
    await websocket.accept()
    # Tail current run's output.log and stream new lines
    async for line in tail_run_output(agent_name):
        await websocket.send_text(line)
```

**Resizable Panels (React):**

Use `react-resizable-panels` or custom implementation:

```typescript
import { Panel, PanelGroup, PanelResizeHandle } from 'react-resizable-panels';

<PanelGroup direction="horizontal">
  <Panel defaultSize={20} minSize={15}>
    <AgentListPanel />
  </Panel>
  <PanelResizeHandle />
  <Panel defaultSize={50} minSize={30}>
    <LiveConsolePanel />
  </Panel>
  <PanelResizeHandle />
  <Panel defaultSize={30} minSize={20}>
    <RunHistoryPanel />
  </Panel>
</PanelGroup>
```

**Start Agent Action:**

```typescript
const startAgent = async (requirementId: string) => {
  await fetch(`/api/agents/${selectedAgent.name}/start`, {
    method: "POST",
    body: JSON.stringify({ requirement_id: requirementId }),
    headers: { "Content-Type": "application/json" },
  });
};
```

**Stop Agent Actions:**

```typescript
// Graceful stop
await fetch(`/api/agents/${agentName}/stop?mode=graceful`, { method: "POST" });

// Force kill
await fetch(`/api/agents/${agentName}/stop?mode=force`, { method: "POST" });
```

**ANSI Color Support:**

Use `ansi-to-react` or similar library:

```typescript
import Ansi from 'ansi-to-react';

<div className="console-output">
  <Ansi>{consoleOutput}</Ansi>
</div>
```

## Dependencies

- S-0013 (Agent Settings & Registry) - requires agents.json and agent identity
- S-0011 (Kanban Detail Artifact Viewer) - reuses slide-out pattern for run details
- S-0003 (Frontend Observer UI) - requires React infrastructure
- S-0002 (Backend API) - requires agent management endpoints

## Non-Goals

- Multi-agent parallel execution control (start multiple agents at once)
- Agent resource usage metrics (CPU, memory, disk)
- Agent log aggregation across machines (local only)
- Console input/REPL for interactive agent control
- Video/screen recording of agent sessions
- Agent performance analytics or benchmarking

## Validation Criteria

- [ ] Backend serves agent console WebSocket: `wscat -c ws://localhost:8080/api/agents/felix-primary/console` receives output
- [ ] Start agent via API: `curl -X POST http://localhost:8080/api/agents/felix-primary/start -d '{"requirement_id":"S-0012"}' -H "Content-Type: application/json"` (status 200)
- [x] Dashboard loads: Manual verification - open Orchestration tab, verify 3-panel layout
- [x] Agent selection works: Manual verification - click agent in list, verify console/history update
- [x] Run detail slide-out: Manual verification - click run, verify slide-out opens with tabs
- [x] Resizable panels: Manual verification - drag panel borders, verify resize works
- [x] Stop agent: Manual verification - click Stop > Graceful, verify agent stops after task
