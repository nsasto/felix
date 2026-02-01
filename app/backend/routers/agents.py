"""
Felix Backend - Agent Registry API
Handles agent registration, heartbeat, status tracking, and console streaming.

NOTE: S-0032 - File-based agent registry operations have been removed.
Endpoints are stubbed to return 501 Not Implemented or empty responses.
The WebSocket console streaming endpoint is preserved for runs/ directory output.
"""
import asyncio
import json
from typing import Dict, List, Optional
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
# NOTE: S-0032 - All file operations removed. Project-level felix/agents.json is no longer used.
# Endpoints have been stubbed to prepare for database-driven state management in Phase 0.
# The following functions have been removed:
# - get_agents_file_path() - located project-level felix/agents.json
# - load_agents_registry() - read project-level felix/agents.json
# - save_agents_registry() - wrote project-level felix/agents.json  
# - check_agent_liveness() - agent status checking
# - update_agent_statuses() - status updates
# - _load_project_state() - read felix/state.json
# - populate_workflow_stage_fields() - read felix/state.json for workflow info


# --- API Endpoints ---

@router.post("/register")
async def register_agent(request: AgentRegistration):
    """
    Register an agent with the registry.
    
    NOTE: S-0032 - This endpoint is stubbed. File-based agent registry has been removed.
    Will be re-implemented with database storage in Phase 0.
    """
    raise HTTPException(
        status_code=501,
        detail="Agent registration is temporarily disabled. File-based registry has been removed in preparation for database-driven state management."
    )


@router.post("/{agent_id}/heartbeat")
async def agent_heartbeat(agent_id: int, request: AgentHeartbeat):
    """
    Update agent heartbeat and optionally the current run ID.
    
    NOTE: S-0032 - This endpoint is stubbed. File-based agent registry has been removed.
    Will be re-implemented with database storage in Phase 0.
    """
    raise HTTPException(
        status_code=501,
        detail="Agent heartbeat is temporarily disabled. File-based registry has been removed in preparation for database-driven state management."
    )


@router.get("", response_model=AgentRegistryResponse)
async def get_agents():
    """
    Get all registered agents with their current status.
    
    NOTE: S-0032 - This endpoint returns an empty registry. File-based agent registry has been removed.
    Will be re-implemented with database storage in Phase 0.
    """
    # Return empty agents registry (stubbed response)
    return AgentRegistryResponse(agents={})


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


@router.post("/{agent_id}/stop")
async def stop_agent(agent_id: int, mode: str = "graceful"):
    """
    Stop an agent and mark it as stopped in the registry.
    
    NOTE: S-0032 - This endpoint is stubbed. File-based agent registry has been removed.
    Will be re-implemented with database storage in Phase 0.
    """
    raise HTTPException(
        status_code=501,
        detail="Agent stop is temporarily disabled. File-based registry has been removed in preparation for database-driven state management."
    )


@router.post("/{agent_id}/start")
async def start_agent(agent_id: int, request: AgentStartRequest):
    """
    Start an agent to work on a specific requirement.
    
    NOTE: S-0032 - This endpoint is stubbed. File-based agent registry has been removed.
    Will be re-implemented with database storage in Phase 0.
    """
    raise HTTPException(
        status_code=501,
        detail="Agent start is temporarily disabled. File-based registry has been removed in preparation for database-driven state management."
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
    
    NOTE: S-0032 - This endpoint no longer reads agent registry from felix/agents.json.
    It streams console output from runs/ directory without agent validation.
    
    Messages sent to client:
    - {"type": "connected", "agent_id": 0, "message": "..."}
    - {"type": "output", "content": "...", "run_id": "..."}
    - {"type": "run_changed", "run_id": "...", "message": "..."}
    - {"type": "idle", "message": "..."}
    - {"type": "error", "message": "..."}
    
    The client can send:
    - {"type": "ping"} - keepalive
    - Any message to keep connection alive
    """
    await websocket.accept()
    
    # Send connected message (no agent validation - registry is stubbed)
    await websocket.send_json({
        "type": "connected",
        "agent_id": agent_id,
        "message": f"Connected to console stream for agent ID {agent_id}"
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
    
    try:
        while True:
            # Find current run directory (without agent registry validation)
            run_dir = _find_current_run_dir(project_path, str(agent_id))
            
            if run_dir:
                current_run_id = run_dir.name
                output_log = run_dir / "output.log"
                
                # Check if run changed
                if current_run_id != last_run_id:
                    last_run_id = current_run_id
                    last_file_position = 0  # Reset position for new run
                    
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
