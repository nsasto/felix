# S-0030: Agent Workflow Visualization Panel

## Narrative

As a developer monitoring Felix agents, I need a live visual representation of the agent's execution workflow showing which stage the agent is currently in, so that I can quickly understand where the agent is in its iteration cycle and identify bottlenecks or stuck stages without reading through console logs.

The current Agent Dashboard shows live console output but provides no visual indication of the agent's execution state. Users must read console logs to understand whether the agent is gathering context, executing the LLM, running tests, or committing changes. A visual workflow diagram with animated stage highlighting would provide instant situational awareness.

**User Experience Goal:** Glance at the workflow panel and immediately know "The agent is currently running backpressure validation tests" or "The agent is waiting for LLM execution" without reading any text.

## Acceptance Criteria

### Layout Changes

- [ ] Live Console panel is split into two sections:
  - Top section: Console output (takes ~65% of panel height)
  - Bottom section: Workflow visualization (takes ~35% of panel height)
- [ ] Resizable divider between console and workflow sections
- [ ] Workflow panel has header showing "Agent Workflow" title
- [ ] Workflow panel maintains visibility when console is scrolled

### Workflow Visualization Display

- [ ] Workflow diagram shows all agent execution stages as connected nodes
- [ ] Each stage node displays:
  - Stage SVG icon (clean line icons matching existing Icons.tsx style)
  - Stage name (short label, e.g., "LLM Exec", "Tests")
  - Visual connector arrows showing flow direction
- [ ] Current active stage is highlighted with:
  - Distinct border color (felix-500 accent)
  - Pulsing animation (subtle glow effect)
  - Brighter background color
- [ ] Completed stages show checkmark icon overlay (✓)
- [ ] Failed stages show error icon overlay (✕) with red color
- [ ] Pending stages show muted/inactive styling
- [ ] Vertical or horizontal flow layout (configurable via JSON)

### Stage Definitions

The workflow includes these stages (loaded from **..felix/workflow.json**):

1. **Select Requirement** - Target/crosshair icon
2. **Start Iteration** - Play/triangle icon
3. **Determine Mode** - Branch/fork icon
4. **Gather Context** - Folder/document stack icon
5. **Build Prompt** - Document/edit icon
6. **Execute LLM** - CPU/processor icon
7. **Process Output** - File text icon
8. **Check Guardrails** - Shield icon
9. **Detect Task** - Checkbox icon
10. **Run Backpressure** - Beaker/flask icon
11. **Commit Changes** - Git commit/save icon
12. **Validate Requirement** - Check circle icon
13. **Update Status** - Bar chart icon
14. **Iteration Complete** - Flag/finish icon

### Real-Time Stage Updates

- [ ] Workflow panel updates using existing agent polling interval (2 seconds, same as agent list)
- [ ] State file includes new field: `current_workflow_stage` (string)
- [ ] felix-agent.ps1 updates state.json with current stage at each transition
- [ ] state.json is updated with a helper script to simplify process and allow for plugin architecture later
- [ ] Workflow visualization animates transition to new stage (smooth highlight movement)
- [ ] Active stage glows with a debounce/slow throbbing effect
- [ ] When agent is idle, all stages show inactive state

### Workflow Configuration

- [ ] Workflow stages defined in **..felix/workflow.json** (new file)
- [ ] JSON structure includes:
  - Stage ID (unique key)
  - Display name (short label)
  - Icon name (references Icons.tsx or new icon)
  - Description (tooltip text)
  - Order/position in flow
  - Conditional stages (e.g., "guardrails" only for planning mode)
- [ ] JSON file can be edited to customize workflow visualization
- [ ] Frontend loads workflow.json on dashboard mount
- [ ] Invalid/missing workflow.json falls back to default hardcoded stages

### Visual Design

- [ ] Compact flowchart layout fits within panel height (~300-400px)
- [ ] Nodes sized for readability (min 80px wide x 50px tall)
- [ ] Stage names truncated with ellipsis if too long
- [ ] Tooltips on hover show full stage description
- [ ] Color coding:
  - Active stage: felix-500 (cyan/blue)
  - Completed: green-500
  - Failed: red-500
  - Inactive: text-muted gray
- [ ] Responsive to panel resize (maintains aspect ratio)

### Error Handling

- [ ] Show "No workflow data" message if state.json is missing
- [ ] Show "Agent idle" message if no current stage set
- [ ] Handle workflow.json parse errors gracefully (use defaults)
- [ ] Handle stage name mismatches between state and config (show as "Unknown Stage")

## Technical Notes
These are guidelines. make your plan with this as input but feel free to select the most optimal approach as per your planning instructions. 

### Component Architecture

```
LiveConsolePanel (existing)
├── ConsoleOutput (top 65%)
│   └── ANSI terminal display
├── ResizableHandle (draggable divider)
└── WorkflowVisualization (bottom 35%)
    ├── WorkflowHeader (title, minimize button)
    └── WorkflowDiagram
        └── StageNode[] (connected flowchart)
```

### State Management

**..felix/state.json additions:**

```json
{
  "current_requirement_id": "S-0012",
  "current_iteration": 3,
  "current_workflow_stage": "execute_llm",
  "workflow_stage_timestamp": "2026-01-29T14:32:15Z",
  "workflow_stage_history": [
    { "stage": "select_requirement", "timestamp": "2026-01-29T14:30:00Z" },
    { "stage": "start_iteration", "timestamp": "2026-01-29T14:30:01Z" },
    { "stage": "determine_mode", "timestamp": "2026-01-29T14:30:02Z" }
  ]
}
```

**..felix/workflow.json (new file):**

```json
{
  "version": "1.0",
  "layout": "horizontal",
  "stages": [
    {
      "id": "select_requirement",
      "name": "Select Req",
      "icon": "target",
      "description": "felix-loop.ps1 selects next planned/in_progress requirement",
      "order": 1
    },
    {
      "id": "start_iteration",
      "name": "Start",
      "icon": "play",
      "description": "Begin new agent iteration",
      "order": 2
    },
    {
      "id": "determine_mode",
      "name": "Mode",
      "icon": "git-branch",
      "description": "Determine planning vs building mode",
      "order": 3
    },
    {
      "id": "gather_context",
      "name": "Context",
      "icon": "folder",
      "description": "Load specs, requirements, git state",
      "order": 4
    },
    {
      "id": "build_prompt",
      "name": "Prompt",
      "icon": "file-text",
      "description": "Construct full prompt with context",
      "order": 5
    },
    {
      "id": "execute_llm",
      "name": "LLM",
      "icon": "cpu",
      "description": "Execute droid with prompt",
      "order": 6
    },
    {
      "id": "process_output",
      "name": "Output",
      "icon": "file-code",
      "description": "Parse and process LLM response",
      "order": 7
    },
    {
      "id": "check_guardrails",
      "name": "Guardrails",
      "icon": "shield",
      "description": "Planning mode safety checks",
      "order": 8,
      "conditional": "planning_mode"
    },
    {
      "id": "detect_task",
      "name": "Task Check",
      "icon": "check-square",
      "description": "Check for task completion signal",
      "order": 9
    },
    {
      "id": "run_backpressure",
      "name": "Tests",
      "icon": "flask",
      "description": "Run validation tests/build/lint",
      "order": 10
    },
    {
      "id": "commit_changes",
      "name": "Commit",
      "icon": "git-commit",
      "description": "Git add and commit changes",
      "order": 11
    },
    {
      "id": "validate_requirement",
      "name": "Validate",
      "icon": "check-circle",
      "description": "Run requirement validation",
      "order": 12
    },
    {
      "id": "update_status",
      "name": "Status",
      "icon": "bar-chart",
      "description": "Update requirement status",
      "order": 13
    },
    {
      "id": "iteration_complete",
      "name": "Done",
      "icon": "flag",
      "description": "Iteration complete, check continue",
      "order": 14
    }
  ]
}
```

### PowerShell Integration

felix-agent.ps1 needs to update state.json at each workflow stage:

```powershell
function Set-WorkflowStage {
    param([string]$Stage)

    if (-not (Test-Path $StateFile)) {
        return
    }

    $state = Get-Content $StateFile -Raw | ConvertFrom-Json
    $state.current_workflow_stage = $Stage
    $state.workflow_stage_timestamp = Get-Date -Format "o"

    # Add to history (keep last 10)
    if (-not $state.workflow_stage_history) {
        $state | Add-Member -NotePropertyName "workflow_stage_history" -NotePropertyValue @() -Force
    }
    $state.workflow_stage_history += @{
        stage = $Stage
        timestamp = Get-Date -Format "o"
    }
    if ($state.workflow_stage_history.Count -gt 10) {
        $state.workflow_stage_history = $state.workflow_stage_history[-10..-1]
    }

    $state | ConvertTo-Json -Depth 10 | Set-Content $StateFile
}

# Usage throughout felix-agent.ps1:
Set-WorkflowStage -Stage "select_requirement"
Set-WorkflowStage -Stage "execute_llm"
Set-WorkflowStage -Stage "run_backpressure"
```

### Frontend Implementation

```typescript
// Load workflow config
const [workflowConfig, setWorkflowConfig] = useState(null);
useEffect(() => {
  fetch(`/api/workflow-config?project_id=${projectId}`)
    .then(res => res.json())
    .then(setWorkflowConfig);
}, [projectId]);

// Workflow stage updates using existing agent polling (2 seconds)
// No new polling needed - workflow stage comes from state.json via existing agent data refresh
useEffect(() => {
  // Existing agent polling already runs every 2 seconds
  // Just read current_workflow_stage from agent state
  if (selectedAgent?.agent?.current_workflow_stage) {
    setCurrentStage(selectedAgent.agent.current_workflow_stage);
  }
}, [selectedAgent]);

// Render workflow
<div className="workflow-container">
  {workflowConfig?.stages.map(stage => (
    <StageNode
      key={stage.id}
      stage={stage}
      isActive={currentStage === stage.id}
      isComplete={stageHistory.includes(stage.id)}
    />
  ))}
</div>
```

### Backend API

Add endpoint to serve workflow.json:

```python
@router.get("/api/workflow-config")
async def get_workflow_config(project_id: str):
    workflow_path = Path(project_id) / "felix" / "workflow.json"
    if workflow_path.exists():
        return JSONResponse(content=json.loads(workflow_path.read_text()))
    return JSONResponse(content=DEFAULT_WORKFLOW_CONFIG)
```

Extend existing agent status response to include workflow stage from state.json:

```python
# In update_agent_statuses() or similar
state_path = Path(agent_path) / "felix" / "state.json"
if state_path.exists():
    state = json.loads(state_path.read_text())
    agent["current_workflow_stage"] = state.get("current_workflow_stage")
    agent["workflow_stage_timestamp"] = state.get("workflow_stage_timestamp")
```

### Icon Implementation

Icons should match the existing icon style in **app/frontend/components/Icons.tsx**. Use the same stroke-width, viewBox (24x24), and styling conventions. For icons not yet in Icons.tsx, add them following the established pattern (24x24 viewBox, 2px stroke, no fill).

New icons needed:

- `IconTarget` - crosshair/target (select requirement)
- `IconGitBranch` - git branch (mode selection)
- `IconFlask` - laboratory flask (tests)
- `IconGitCommit` - git commit dot (commit changes)
- `IconBarChart` - bar chart (status update)
- `IconFlag` - flag (completion)

Reuse existing icons:

- `IconPlay` - play button (start iteration)
- `IconFolder` - folder (context gathering)
- `IconFileText` - document (prompt building)
- `IconCpu` - processor (LLM execution)
- `IconFileCode` - code file (output processing)
- `IconShield` - shield (guardrails) - if exists, or add
- `IconCheckSquare` - checkbox (task detection) - if exists, or add
- `IconCheckCircle` - check circle (validation)

### Visual Reference

The user provided a simple flowchart with connected boxes. The workflow visualization should:

- Use connected boxes/cards with clean borders
- Show directional flow with subtle connector lines or arrows
- Current stage highlighted with accent color and subtle animation
- Minimal, scannable design
- Professional appearance (no emoji)

## Dependencies

- S-0014 (Agent Orchestration Dashboard) - requires existing Live Console panel
- S-0002 (Backend API Server) - requires API endpoints for workflow config
- felix-agent.ps1 must be updated to write workflow stage to state.json
- felix-loop.ps1 may need updates to write "select_requirement" stage

## Non-Goals

- Interactive workflow (clicking stages to jump) - read-only visualization only
- Historical workflow replay - only shows current/recent state
- Custom workflow designer UI - editing workflow.json is manual/code-based
- Multi-agent workflow comparison - single agent view only
- Performance metrics per stage (duration, timing) - future enhancement
- Workflow branching visualization (conditional paths) - simplified linear flow only
- Custom polling intervals - reuses existing 2-second agent polling

## Validation Criteria

- [ ] Manual verification: Split Live Console panel shows workflow visualization below console output
- [ ] Manual verification: Start agent, observe workflow highlighting moving through stages in real-time
- [ ] Manual verification: Resize divider between console and workflow, both sections resize properly
- [ ] Manual verification: Hover over stage nodes, tooltips show full stage descriptions
- [ ] Manual verification: Edit ..felix/workflow.json stage names, refresh dashboard, see updated Tags
- [ ] Manual verification: Stop agent, workflow stages return to inactive state
- [ ] Backend serves workflow config: `curl http://localhost:8080/api/workflow-config?project_id=<path>` returns JSON
- [ ] Backend includes workflow stage in agent status: `curl http://localhost:8080/api/agents` includes current_workflow_stage field



