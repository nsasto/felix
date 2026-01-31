"""
Felix Backend - Agent Registry API
Handles agent registration, heartbeat, status tracking, and console streaming.
"""
import asyncio
import json
import os
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional, AsyncGenerator
from pathlib import Path

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

import storage


router = APIRouter(prefix="/api/agents", tags=["agents"])


# --- Request/Response Models ---

class AgentRegistration(BaseModel):
    """Request body for agent registration"""
    agent_id: int = Field(..., description="Unique agent ID from config")
    agent_name: str = Field(..., description="Agent display name (for logging)")
    pid: int = Field(..., description="Process ID of the agent")
    hostname: str = Field(..., description="Hostname where agent is running")
    started_at: Optional[str] = Field(None, description="ISO timestamp when agent started")


class AgentHeartbeat(BaseModel):
    """Request body for heartbeat update"""
    current_run_id: Optional[str] = Field(None, description="Current requirement ID being worked on")


class AgentEntry(BaseModel):
    """Agent entry in the registry"""
    agent_id: int = Field(..., description="Agent ID from config (stable identifier)")
    agent_name: str = Field(..., description="Agent display name")
    pid: int
    hostname: str
    status: str = Field(default="active", description="Agent status: active, inactive, stopped")
    current_run_id: Optional[str] = None
    started_at: Optional[str] = None
    last_heartbeat: Optional[str] = None
    stopped_at: Optional[str] = None
    # Workflow stage fields (S-0030: Agent Workflow Visualization)
    current_workflow_stage: Optional[str] = Field(None, description="Current workflow stage ID from state.json")
    workflow_stage_timestamp: Optional[str] = Field(None, description="ISO timestamp when workflow stage was set")


class AgentRegistryResponse(BaseModel):
    """Response containing all registered agents"""
    agents: Dict[int, AgentEntry]


class AgentStatusResponse(BaseModel):
    """Response for a single agent status"""
    agent_id: int
    agent_name: str
    status: str
    pid: int
    hostname: str
    current_run_id: Optional[str] = None
    started_at: Optional[str] = None
    last_heartbeat: Optional[str] = None
    stopped_at: Optional[str] = None
    # Workflow stage fields (S-0030: Agent Workflow Visualization)
    current_workflow_stage: Optional[str] = None
    workflow_stage_timestamp: Optional[str] = None


class AgentStopResponse(BaseModel):
    """Response for stopping an agent"""
    message: str
    agent_id: int
    agent_name: str
    status: str


class AgentStartRequest(BaseModel):
    """Request body for starting an agent with a specific requirement"""
    requirement_id: str = Field(..., description="Requirement ID to work on (e.g., 'S-0012')")


class AgentStartResponse(BaseModel):
    """Response for starting an agent"""
    message: str
    agent_id: int
    agent_name: str
    requirement_id: str
    status: str


class StopMode(str):
    """Stop mode options"""
    GRACEFUL = "graceful"
    FORCE = "force"


# --- Agent Configuration Models (for S-0021: Agent Orchestration Enhancement) ---

class AgentConfigEntry(BaseModel):
    """Agent configuration entry from agents.json"""
    id: int = Field(..., description="Unique agent ID (0 = system default)")
    name: str = Field(..., description="Display name for the agent")
    executable: str = Field(default="droid", description="Agent executable path")
    args: List[str] = Field(default_factory=list, description="Command line arguments")
    working_directory: str = Field(default=".", description="Working directory")
    environment: Dict[str, str] = Field(default_factory=dict, description="Environment variables")


class AgentConfigsListResponse(BaseModel):
    """Response containing configured agents from agents.json"""
    agents: List[AgentConfigEntry]


# --- Workflow Configuration Models (for S-0030: Agent Workflow Visualization) ---

class WorkflowStage(BaseModel):
    """A single workflow stage definition"""
    id: str = Field(..., description="Unique stage identifier")
    name: str = Field(..., description="Short display name")
    icon: str = Field(..., description="Icon name for the stage")
    description: str = Field(..., description="Full description of what this stage does")
    order: int = Field(..., description="Order in the workflow sequence")
    conditional: Optional[str] = Field(None, description="Condition when this stage applies (e.g., 'planning_mode')")


class WorkflowConfigResponse(BaseModel):
    """Response containing workflow configuration"""
    version: str = Field(..., description="Workflow config version")
    layout: str = Field(default="horizontal", description="Layout direction: horizontal or vertical")
    stages: List[WorkflowStage] = Field(..., description="List of workflow stages in order")


# Default workflow configuration (fallback when felix/workflow.json is missing or invalid)
DEFAULT_WORKFLOW_CONFIG = WorkflowConfigResponse(
    version="1.0",
    layout="horizontal",
    stages=[
        WorkflowStage(id="select_requirement", name="Select Req", icon="target", description="Select next planned requirement", order=1),
        WorkflowStage(id="start_iteration", name="Start", icon="play", description="Begin new agent iteration", order=2),
        WorkflowStage(id="determine_mode", name="Mode", icon="git-branch", description="Determine planning vs building mode", order=3),
        WorkflowStage(id="gather_context", name="Context", icon="folder", description="Load specs, requirements, git state", order=4),
        WorkflowStage(id="build_prompt", name="Prompt", icon="file-text", description="Construct full prompt with context", order=5),
        WorkflowStage(id="execute_llm", name="LLM", icon="cpu", description="Execute droid with prompt", order=6),
        WorkflowStage(id="process_output", name="Output", icon="file-code", description="Parse and process LLM response", order=7),
        WorkflowStage(id="check_guardrails", name="Guardrails", icon="shield", description="Planning mode safety checks", order=8, conditional="planning_mode"),
        WorkflowStage(id="detect_task", name="Task Check", icon="check-square", description="Check for task completion signal", order=9),
        WorkflowStage(id="run_backpressure", name="Tests", icon="flask", description="Run validation tests/build/lint", order=10),
        WorkflowStage(id="commit_changes", name="Commit", icon="git-commit", description="Git add and commit changes", order=11),
        WorkflowStage(id="validate_requirement", name="Validate", icon="check-circle", description="Run requirement validation", order=12),
        WorkflowStage(id="update_status", name="Status", icon="bar-chart", description="Update requirement status", order=13),
        WorkflowStage(id="iteration_complete", name="Done", icon="flag", description="Iteration complete, check continue", order=14),
    ]
)


# --- Agent Registry File Operations ---

def get_agents_file_path() -> Path:
    """
    Get the path to felix/agents.json.
    Uses the Felix project in current working directory.
    """
    # The backend runs from the project root, so felix/agents.json is relative
    # Check if we're in app/backend and adjust accordingly
    cwd = Path.cwd()
    
    # Check multiple possible locations
    possible_paths = [
        cwd / "felix" / "agents.json",
        cwd.parent.parent / "felix" / "agents.json",  # If running from app/backend
        Path(__file__).parent.parent.parent.parent / "felix" / "agents.json",  # Relative to this file
    ]
    
    for path in possible_paths:
        if path.parent.exists():
            return path
    
    # Default to cwd-relative
    return cwd / "felix" / "agents.json"


def load_agents_registry() -> Dict[int, AgentEntry]:
    """Load agents from felix/agents.json"""
    agents_file = get_agents_file_path()
    
    if not agents_file.exists():
        # Create default empty registry if file doesn't exist
        if agents_file.parent.exists():
            agents_file.write_text(json.dumps({"agents": {}}, indent=2), encoding='utf-8')
        return {}
    
    try:
        data = json.loads(agents_file.read_text(encoding='utf-8'))
        agents_dict = data.get("agents", {})
        
        # Convert string keys to int and to AgentEntry objects
        result = {}
        for id_str, entry_data in agents_dict.items():
            agent_id = int(id_str)
            result[agent_id] = AgentEntry(**entry_data)
        return result
    except (json.JSONDecodeError, ValueError) as e:
        # Return empty on parse error
        print(f"Warning: Failed to parse agents.json: {e}")
        return {}


def save_agents_registry(agents: Dict[int, AgentEntry]):
    """Save agents to felix/agents.json"""
    agents_file = get_agents_file_path()
    
    # Ensure felix directory exists
    if not agents_file.parent.exists():
        raise HTTPException(
            status_code=500, 
            detail="Felix directory not found. Cannot save agents registry."
        )
    
    # Convert int keys to strings and AgentEntry objects to dicts
    agents_dict = {str(agent_id): entry.model_dump() for agent_id, entry in agents.items()}
    
    data = {"agents": agents_dict}
    agents_file.write_text(json.dumps(data, indent=2), encoding='utf-8')


def check_agent_liveness(agent: AgentEntry) -> str:
    """
    Check if an agent should be considered active or inactive.
    
    An agent is inactive if:
    - last_heartbeat is more than 10 seconds old
    - status is already 'stopped'
    
    Returns updated status string.
    """
    # If already stopped, keep stopped
    if agent.status == "stopped":
        return "stopped"
    
    # Check heartbeat staleness
    if agent.last_heartbeat:
        try:
            # Parse ISO timestamp
            heartbeat_time = datetime.fromisoformat(agent.last_heartbeat.replace('Z', '+00:00'))
            now = datetime.now(timezone.utc)
            
            age = now - heartbeat_time
            if age > timedelta(seconds=10):
                return "inactive"
        except (ValueError, TypeError):
            # If we can't parse the timestamp, mark as inactive
            return "inactive"
    else:
        # No heartbeat ever, check started_at age
        if agent.started_at:
            try:
                started_time = datetime.fromisoformat(agent.started_at.replace('Z', '+00:00'))
                now = datetime.now(timezone.utc)
                age = now - started_time
                if age > timedelta(seconds=10):
                    return "inactive"
            except (ValueError, TypeError):
                return "inactive"
        else:
            # No timestamps at all, mark inactive
            return "inactive"
    
    return "active"


def update_agent_statuses(agents: Dict[int, AgentEntry]) -> Dict[int, AgentEntry]:
    """
    Update status of all agents based on liveness checks.
    Returns the updated agents dict.
    """
    for agent_id, agent in agents.items():
        new_status = check_agent_liveness(agent)
        agent.status = new_status
    return agents


def _load_project_state(project_path: Path) -> Optional[dict]:
    """
    Load felix/state.json from a project directory.
    
    Returns:
        dict: State data if successfully loaded, None otherwise
    """
    state_file = project_path / "felix" / "state.json"
    
    if not state_file.exists():
        return None
    
    try:
        return json.loads(state_file.read_text(encoding='utf-8-sig'))
    except (json.JSONDecodeError, ValueError, IOError) as e:
        print(f"Warning: Failed to parse state.json at {state_file}: {e}")
        return None


def populate_workflow_stage_fields(agents: Dict[int, AgentEntry]) -> Dict[int, AgentEntry]:
    """
    Populate workflow stage fields from state.json for active agents.
    
    This function reads felix/state.json from registered projects and populates
    the current_workflow_stage and workflow_stage_timestamp fields on agents
    that are currently working on requirements in those projects.
    
    The association is determined by:
    1. Get all registered projects
    2. For each project, read felix/state.json
    3. Match the current_requirement_id from state.json to agent.current_run_id
    4. Populate workflow stage fields from state.json
    
    Returns:
        Updated agents dict with workflow stage fields populated
    """
    # Get all registered projects
    projects = storage.get_all_projects()
    
    if not projects:
        return agents
    
    # Build a map of current_requirement_id -> project state data
    req_to_state_map: Dict[str, dict] = {}
    
    for project in projects:
        project_path = Path(project.path)
        state_data = _load_project_state(project_path)
        
        if state_data and "current_requirement_id" in state_data:
            req_id = state_data.get("current_requirement_id")
            if req_id:
                req_to_state_map[req_id] = state_data
    
    # Populate workflow stage fields for matching agents
    for agent_id, agent in agents.items():
        # Reset workflow fields (they're not persisted in agents.json)
        agent.current_workflow_stage = None
        agent.workflow_stage_timestamp = None
        
        # Check if agent is working on a requirement that matches a project state
        if agent.current_run_id and agent.status == "active":
            state_data = req_to_state_map.get(agent.current_run_id)
            
            if state_data:
                agent.current_workflow_stage = state_data.get("current_workflow_stage")
                agent.workflow_stage_timestamp = state_data.get("workflow_stage_timestamp")
    
    return agents


# --- API Endpoints ---

@router.post("/register", response_model=AgentStatusResponse)
async def register_agent(request: AgentRegistration):
    """
    Register an agent with the registry.
    
    If an agent with the same ID exists:
    - If status is 'stopped' or 'inactive', update the entry (allow restart)
    - If status is 'active', return 409 Conflict (duplicate active agent)
    
    Creates felix/agents.json if it doesn't exist.
    """
    agents = load_agents_registry()
    
    # Update statuses before checking
    agents = update_agent_statuses(agents)
    
    # Validate agent name format
    if not request.agent_name or not request.agent_name.strip():
        raise HTTPException(status_code=400, detail="Agent name cannot be empty")
    
    # Check for alphanumeric with hyphens/underscores
    import re
    if not re.match(r'^[a-zA-Z0-9_-]+$', request.agent_name):
        raise HTTPException(
            status_code=400, 
            detail="Agent name must be alphanumeric with hyphens and underscores only"
        )
    
    # Check if agent already exists and is active
    if request.agent_id in agents:
        existing = agents[request.agent_id]
        if existing.status == "active":
            raise HTTPException(
                status_code=409, 
                detail=f"Agent ID {request.agent_id} ('{existing.agent_name}') is already active (PID: {existing.pid}, Host: {existing.hostname})"
            )
    
    # Get current UTC timestamp
    now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    
    # Create or update agent entry
    agent_entry = AgentEntry(
        agent_id=request.agent_id,
        agent_name=request.agent_name,
        pid=request.pid,
        hostname=request.hostname,
        status="active",
        current_run_id=None,
        started_at=request.started_at or now,
        last_heartbeat=now,
        stopped_at=None
    )
    
    agents[request.agent_id] = agent_entry
    save_agents_registry(agents)
    
    return AgentStatusResponse(
        agent_id=agent_entry.agent_id,
        agent_name=agent_entry.agent_name,
        status=agent_entry.status,
        pid=agent_entry.pid,
        hostname=agent_entry.hostname,
        current_run_id=agent_entry.current_run_id,
        started_at=agent_entry.started_at,
        last_heartbeat=agent_entry.last_heartbeat,
        stopped_at=agent_entry.stopped_at,
        current_workflow_stage=agent_entry.current_workflow_stage,
        workflow_stage_timestamp=agent_entry.workflow_stage_timestamp
    )


@router.post("/{agent_id}/heartbeat", response_model=AgentStatusResponse)
async def agent_heartbeat(agent_id: int, request: AgentHeartbeat):
    """
    Update agent heartbeat and optionally the current run ID.
    
    Should be called every 5 seconds by running agents.
    Updates last_heartbeat timestamp and status to 'active'.
    """
    agents = load_agents_registry()
    
    if agent_id not in agents:
        raise HTTPException(status_code=404, detail=f"Agent ID {agent_id} not found")
    
    agent = agents[agent_id]
    
    # Update heartbeat
    now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    agent.last_heartbeat = now
    agent.status = "active"
    
    # Update current run ID if provided
    if request.current_run_id is not None:
        agent.current_run_id = request.current_run_id
    
    # Clear stopped_at since agent is active again
    agent.stopped_at = None
    
    agents[agent_id] = agent
    save_agents_registry(agents)
    
    return AgentStatusResponse(
        agent_id=agent.agent_id,
        agent_name=agent.agent_name,
        status=agent.status,
        pid=agent.pid,
        hostname=agent.hostname,
        current_run_id=agent.current_run_id,
        started_at=agent.started_at,
        last_heartbeat=agent.last_heartbeat,
        stopped_at=agent.stopped_at,
        current_workflow_stage=agent.current_workflow_stage,
        workflow_stage_timestamp=agent.workflow_stage_timestamp
    )


@router.get("", response_model=AgentRegistryResponse)
async def get_agents():
    """
    Get all registered agents with their current status.
    
    Automatically updates status based on heartbeat staleness:
    - Agents with heartbeat > 10s old are marked 'inactive'
    - Stopped agents remain 'stopped'
    
    Also populates workflow stage fields from felix/state.json for active agents
    (S-0030: Agent Workflow Visualization).
    """
    agents = load_agents_registry()
    
    # Update statuses based on liveness
    agents = update_agent_statuses(agents)
    
    # Populate workflow stage fields from state.json
    agents = populate_workflow_stage_fields(agents)
    
    # Save updated statuses (but not workflow fields - they come from state.json)
    save_agents_registry(agents)
    
    return AgentRegistryResponse(agents=agents)


@router.get("/config", response_model=AgentConfigsListResponse)
async def get_agents_config():
    """
    Get all configured agents from felix/agents.json.
    
    This endpoint returns agent configurations (templates/presets) from the
    global Felix home directory. These are distinct from the runtime registry
    which tracks currently running agent instances.
    
    Used by the Agent Orchestration Dashboard (S-0021) to display all available
    agents regardless of whether they've been started yet.
    
    Returns:
        AgentConfigsListResponse with list of configured agents
    """
    # Load agents config from the global Felix home agents.json
    agents_config_path = storage.get_felix_home() / "agents.json"
    
    if not agents_config_path.exists():
        # Return default agent configuration
        default_agents = [
            AgentConfigEntry(
                id=0,
                name="felix-primary",
                executable="droid",
                args=["exec", "--skip-permissions-unsafe"],
                working_directory=".",
                environment={}
            )
        ]
        return AgentConfigsListResponse(agents=default_agents)
    
    try:
        data = json.loads(agents_config_path.read_text(encoding='utf-8'))
        agents_list = data.get("agents", [])
        
        # Convert to AgentConfigEntry objects
        agents = [AgentConfigEntry(**agent) for agent in agents_list]
        
        return AgentConfigsListResponse(agents=agents)
    except (json.JSONDecodeError, ValueError) as e:
        # Return default on parse error
        print(f"Warning: Failed to parse global agents.json: {e}")
        default_agents = [
            AgentConfigEntry(
                id=0,
                name="felix-primary",
                executable="droid",
                args=["exec", "--skip-permissions-unsafe"],
                working_directory=".",
                environment={}
            )
        ]
        return AgentConfigsListResponse(agents=default_agents)


@router.get("/workflow-config", response_model=WorkflowConfigResponse)
async def get_workflow_config(project_id: Optional[str] = None):
    """
    Get workflow configuration for the agent workflow visualization.
    
    Loads felix/workflow.json from the project directory to define the workflow
    stages displayed in the Agent Workflow Visualization panel.
    
    Args:
        project_id: Optional project ID. If provided, loads workflow.json from that project.
                   If not provided, uses the first registered project.
    
    Returns:
        WorkflowConfigResponse with version, layout, and stages array
    
    Falls back to DEFAULT_WORKFLOW_CONFIG if:
    - No projects are registered
    - Project not found
    - workflow.json is missing or invalid
    """
    # Get project path
    project_path: Optional[Path] = None
    
    if project_id:
        # Load specific project
        project = storage.get_project_by_id(project_id)
        if project:
            project_path = Path(project.path)
    else:
        # Use first registered project
        projects = storage.get_all_projects()
        if projects:
            project_path = Path(projects[0].path)
    
    if not project_path:
        # No project available, return default
        return DEFAULT_WORKFLOW_CONFIG
    
    # Try to load workflow.json from project
    workflow_file = project_path / "felix" / "workflow.json"
    
    if not workflow_file.exists():
        # File doesn't exist, return default
        return DEFAULT_WORKFLOW_CONFIG
    
    try:
        data = json.loads(workflow_file.read_text(encoding='utf-8'))
        
        # Validate required fields
        version = data.get("version", "1.0")
        layout = data.get("layout", "horizontal")
        stages_data = data.get("stages", [])
        
        if not stages_data:
            # No stages defined, return default
            return DEFAULT_WORKFLOW_CONFIG
        
        # Convert to WorkflowStage objects
        stages = [WorkflowStage(**stage) for stage in stages_data]
        
        return WorkflowConfigResponse(
            version=version,
            layout=layout,
            stages=stages
        )
    except (json.JSONDecodeError, ValueError, TypeError) as e:
        # Parse error, return default
        print(f"Warning: Failed to parse workflow.json: {e}")
        return DEFAULT_WORKFLOW_CONFIG


@router.post("/{agent_id}/stop", response_model=AgentStopResponse)
async def stop_agent(agent_id: int, mode: str = "graceful"):
    """
    Stop an agent and mark it as stopped in the registry.
    
    Args:
        agent_id: The ID of the agent to stop
        mode: Stop mode - "graceful" (wait for current task) or "force" (terminate immediately)
    
    Graceful mode:
    - Marks the agent as stopped in the registry
    - The agent should check its status and stop after completing current task
    
    Force mode:
    - Attempts to terminate the agent process immediately using SIGTERM/SIGKILL
    - Marks the agent as stopped in the registry
    """
    import signal
    import os
    
    agents = load_agents_registry()
    
    if agent_id not in agents:
        raise HTTPException(status_code=404, detail=f"Agent ID {agent_id} not found")
    
    agent = agents[agent_id]
    
    # Validate mode
    if mode not in ["graceful", "force"]:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid stop mode: {mode}. Must be 'graceful' or 'force'"
        )
    
    # For force mode, attempt to kill the process
    if mode == "force" and agent.status == "active":
        try:
            pid = agent.pid
            if sys.platform == "win32":
                # Windows: use taskkill for more reliable termination
                import subprocess
                subprocess.run(
                    ["taskkill", "/F", "/PID", str(pid)],
                    capture_output=True,
                    timeout=10,
                )
            else:
                # Unix: send SIGTERM first, then SIGKILL if needed
                try:
                    os.kill(pid, signal.SIGTERM)
                    # Give it a moment
                    import time
                    time.sleep(1)
                    # Check if still running
                    try:
                        os.kill(pid, 0)  # Check if process exists
                        os.kill(pid, signal.SIGKILL)  # Force kill
                    except (OSError, ProcessLookupError):
                        pass  # Process already dead
                except (OSError, ProcessLookupError):
                    pass  # Process already dead
        except Exception as e:
            # Log but don't fail - still mark as stopped
            print(f"Warning: Failed to force kill agent process: {e}")
    
    # Update status
    now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    agent.status = "stopped"
    agent.stopped_at = now
    agent.current_run_id = None
    
    agents[agent_id] = agent
    save_agents_registry(agents)
    
    stop_message = f"Agent ID {agent_id} ('{agent.agent_name}') stopped ({mode} mode)"
    
    return AgentStopResponse(
        message=stop_message,
        agent_id=agent.agent_id,
        agent_name=agent.agent_name,
        status="stopped"
    )


@router.post("/{agent_id}/start", response_model=AgentStartResponse)
async def start_agent(agent_id: int, request: AgentStartRequest):
    """
    Start an agent to work on a specific requirement.
    
    This endpoint:
    1. Validates the agent exists and is registered
    2. Updates the agent's current_run_id to the requested requirement
    3. Signals the agent to start working (via file-based mechanism)
    
    Note: This doesn't spawn a new process - it assumes the agent is already running
    or will be started externally. The agent polls for work assignments.
    
    For actually spawning agent processes, use the project runs API:
    POST /api/projects/{project_id}/runs/start
    
    Args:
        agent_id: The ID of the agent to assign work to
        request: Contains requirement_id to work on
    
    Returns:
        AgentStartResponse with status information
    
    Raises:
        404: Agent not found in registry
        400: Requirement ID validation failed
        409: Agent is already working on a task
    """
    agents = load_agents_registry()
    
    if agent_id not in agents:
        raise HTTPException(status_code=404, detail=f"Agent ID {agent_id} not found")
    
    agent = agents[agent_id]
    
    # Validate requirement_id format (e.g., "S-0012")
    import re
    if not request.requirement_id or not re.match(r'^[A-Za-z0-9_-]+$', request.requirement_id):
        raise HTTPException(
            status_code=400,
            detail="Invalid requirement_id format. Must be alphanumeric with hyphens/underscores (e.g., 'S-0012')"
        )
    
    # Check if agent is already working on something
    if agent.status == "active" and agent.current_run_id:
        raise HTTPException(
            status_code=409,
            detail=f"Agent ID {agent_id} ('{agent.agent_name}') is already working on requirement '{agent.current_run_id}'"
        )
    
    # Update agent's current_run_id (this signals what the agent should work on)
    now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    agent.current_run_id = request.requirement_id
    agent.last_heartbeat = now
    
    # If agent was stopped or inactive, note that it needs to be started externally
    was_active = agent.status == "active"
    
    agents[agent_id] = agent
    save_agents_registry(agents)
    
    if was_active:
        message = f"Agent ID {agent_id} ('{agent.agent_name}') assigned to work on requirement '{request.requirement_id}'"
    else:
        message = f"Agent ID {agent_id} ('{agent.agent_name}') assigned requirement '{request.requirement_id}'. Note: Agent is {agent.status}, start the agent process separately."
    
    return AgentStartResponse(
        message=message,
        agent_id=agent.agent_id,
        agent_name=agent.agent_name,
        requirement_id=request.requirement_id,
        status=agent.status
    )


# --- Console Streaming WebSocket ---

def _get_project_path_for_agent() -> Optional[Path]:
    """
    Get the project path from registered projects.
    For now, we assume the first registered project is the active one.
    In the future, this could be extended to track which project each agent is working on.
    """
    projects = storage.list_projects()
    if projects:
        return Path(projects[0].path)
    return None


def _find_current_run_dir(project_path: Path, agent_name: str) -> Optional[Path]:
    """
    Find the current run directory for an agent.
    
    Looks for the most recent run directory in the project's runs/ folder.
    In the future, this could use agent.current_run_id to find the exact run.
    """
    runs_dir = project_path / "runs"
    if not runs_dir.exists():
        return None
    
    # Get most recent run directory by name (ISO timestamp format)
    run_dirs = sorted(
        [d for d in runs_dir.iterdir() if d.is_dir()],
        key=lambda d: d.name,
        reverse=True
    )
    
    if run_dirs:
        return run_dirs[0]
    return None


async def _tail_file(file_path: Path, last_position: int = 0) -> tuple[str, int]:
    """
    Read new content from a file starting from last_position.
    
    Returns:
        tuple: (new_content, new_position)
    """
    try:
        if not file_path.exists():
            return "", last_position
        
        file_size = file_path.stat().st_size
        
        # If file was truncated, start from beginning
        if file_size < last_position:
            last_position = 0
        
        # Read new content
        with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
            f.seek(last_position)
            new_content = f.read()
            new_position = f.tell()
        
        return new_content, new_position
    except (IOError, OSError) as e:
        return f"[Error reading file: {e}]", last_position


@router.websocket("/{agent_id}/console")
async def agent_console_stream(websocket: WebSocket, agent_id: int):
    """
    WebSocket endpoint for streaming agent console output.
    
    Tails the current run's output.log and streams new lines in real-time.
    
    Messages sent to client:
    - {"type": "connected", "agent_id": 0, "agent_name": "...", "message": "..."}
    - {"type": "output", "content": "...", "run_id": "..."}
    - {"type": "run_changed", "run_id": "...", "message": "..."}
    - {"type": "idle", "message": "..."}
    - {"type": "error", "message": "..."}
    
    The client can send:
    - {"type": "ping"} - keepalive
    - Any message to keep connection alive
    """
    await websocket.accept()
    
    # Load agents and validate
    agents = load_agents_registry()
    agents = update_agent_statuses(agents)
    
    if agent_id not in agents:
        await websocket.send_json({
            "type": "error",
            "message": f"Agent ID {agent_id} not found"
        })
        await websocket.close(code=4004, reason="Agent not found")
        return
    
    agent = agents[agent_id]
    
    # Send connected message
    await websocket.send_json({
        "type": "connected",
        "agent_id": agent_id,
        "agent_name": agent.agent_name,
        "status": agent.status,
        "message": f"Connected to console stream for agent ID {agent_id} ('{agent.agent_name}')"
    })
    
    # Get project path
    project_path = _get_project_path_for_agent()
    if not project_path:
        await websocket.send_json({
            "type": "error",
            "message": "No project registered. Cannot stream console output."
        })
        await websocket.close(code=4004, reason="No project")
        return
    
    # State for tailing
    last_run_id: Optional[str] = None
    last_file_position: int = 0
    current_output_log: Optional[Path] = None
    
    try:
        while True:
            # Refresh agent status
            agents = load_agents_registry()
            agents = update_agent_statuses(agents)
            
            if agent_name not in agents:
                await websocket.send_json({
                    "type": "error",
                    "message": f"Agent no longer registered: {agent_name}"
                })
                break
            
            agent = agents[agent_name]
            
            # Check if agent is active and has a current run
            if agent.status != "active":
                # Agent is idle
                await websocket.send_json({
                    "type": "idle",
                    "status": agent.status,
                    "message": f"Agent is {agent.status} - waiting for activity"
                })
                await asyncio.sleep(2)  # Longer sleep when idle
                continue
            
            # Find current run directory
            run_dir = _find_current_run_dir(project_path, agent_name)
            
            if run_dir:
                current_run_id = run_dir.name
                output_log = run_dir / "output.log"
                
                # Check if run changed
                if current_run_id != last_run_id:
                    last_run_id = current_run_id
                    last_file_position = 0  # Reset position for new run
                    current_output_log = output_log
                    
                    await websocket.send_json({
                        "type": "run_changed",
                        "run_id": current_run_id,
                        "message": f"Now streaming from run: {current_run_id}"
                    })
                
                # Read new output
                if output_log.exists():
                    new_content, last_file_position = await _tail_file(output_log, last_file_position)
                    
                    if new_content:
                        await websocket.send_json({
                            "type": "output",
                            "content": new_content,
                            "run_id": current_run_id
                        })
            else:
                # No run directory found
                if last_run_id is not None:
                    # Previously had a run, now gone
                    await websocket.send_json({
                        "type": "idle",
                        "message": "No active run found"
                    })
                    last_run_id = None
                    last_file_position = 0
            
            # Poll interval
            await asyncio.sleep(0.5)  # 500ms for responsive streaming
            
    except WebSocketDisconnect:
        # Client disconnected normally
        pass
    except asyncio.CancelledError:
        # Task was cancelled
        pass
    except Exception as e:
        try:
            await websocket.send_json({
                "type": "error",
                "message": f"Stream error: {str(e)}"
            })
        except Exception:
            pass
    finally:
        try:
            await websocket.close()
        except Exception:
            pass
