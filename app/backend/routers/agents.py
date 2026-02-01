"""
Felix Backend - Agent Registry API
Handles agent registration, heartbeat, status tracking, and console streaming.

NOTE: S-0032 - File-based agent registry operations have been removed.
Database-backed endpoints implemented in S-0038.
The WebSocket console streaming endpoint is preserved for runs/ directory output.
"""
import asyncio
import json
from typing import Dict, List, Optional, Any
from pathlib import Path

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect, Depends
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from databases import Database
import aiofiles

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

import storage
import config
from auth import get_current_user
from database.db import get_db
from database.writers import AgentWriter
from models import AgentRegisterRequest, AgentStatusUpdate, AgentResponse, AgentListResponse, RunCreateRequest, RunResponse, RunListResponse
from websocket.control import control_manager, CommandType
from database.writers import AgentWriter, RunWriter


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

@router.post("/register", response_model=AgentResponse, status_code=201)
async def register_agent(
    request: AgentRegisterRequest,
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Register an agent with the database-backed registry.
    
    Creates a new agent or updates an existing one (upsert).
    Returns the agent record with status 201.
    
    Args:
        request: AgentRegisterRequest with agent_id, name, type, metadata
        db: Database connection from dependency injection
        user: Current user from authentication dependency
    
    Returns:
        AgentResponse with the created/updated agent data
    """
    try:
        # Get project_id from config (dev mode)
        project_id = config.DEV_PROJECT_ID
        
        # Create writer and upsert agent
        writer = AgentWriter(db)
        agent_record = await writer.upsert_agent(
            agent_id=request.agent_id,
            project_id=project_id,
            name=request.name,
            type=request.type,
            metadata=request.metadata,
        )
        
        # Convert to response model
        return AgentResponse(
            id=agent_record["id"],
            project_id=agent_record["project_id"],
            name=agent_record["name"],
            type=agent_record["type"],
            status=agent_record["status"],
            heartbeat_at=agent_record.get("heartbeat_at"),
            metadata=agent_record.get("metadata") or {},
            created_at=agent_record["created_at"],
            updated_at=agent_record["updated_at"],
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Database error during agent registration: {str(e)}"
        )


@router.post("/{agent_id}/heartbeat")
async def agent_heartbeat(
    agent_id: str,
    db: Database = Depends(get_db),
):
    """
    Update agent heartbeat timestamp.
    
    Updates the heartbeat_at timestamp for the specified agent.
    Should be called every 30-60 seconds by felix-agent.ps1.
    
    Args:
        agent_id: The agent ID (string UUID)
        db: Database connection from dependency injection
    
    Returns:
        {"status": "ok", "agent_id": agent_id}
    
    Raises:
        HTTPException 404: If agent not found
        HTTPException 500: On database error
    """
    try:
        writer = AgentWriter(db)
        
        # Verify agent exists
        agent = await writer.get_agent(agent_id)
        if not agent:
            raise HTTPException(
                status_code=404,
                detail=f"Agent not found: {agent_id}"
            )
        
        # Update heartbeat timestamp
        await writer.update_heartbeat(agent_id)
        
        return {"status": "ok", "agent_id": agent_id}
    except HTTPException:
        # Re-raise HTTP exceptions as-is
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Database error during heartbeat update: {str(e)}"
        )


# Valid status values for agents
VALID_AGENT_STATUSES = {"idle", "running", "stopped", "error"}


@router.post("/{agent_id}/status")
async def update_agent_status(
    agent_id: str,
    request: AgentStatusUpdate,
    db: Database = Depends(get_db),
):
    """
    Update an agent's status.
    
    Updates the status field for the specified agent.
    Called when agent starts, stops, or encounters an error.
    
    Args:
        agent_id: The agent ID (string UUID)
        request: AgentStatusUpdate with new status value
        db: Database connection from dependency injection
    
    Returns:
        {"status": "ok", "agent_id": agent_id, "new_status": status}
    
    Raises:
        HTTPException 400: If status is not valid (idle, running, stopped, error)
        HTTPException 404: If agent not found
        HTTPException 500: On database error
    """
    try:
        # Validate status value
        if request.status not in VALID_AGENT_STATUSES:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid status '{request.status}'. Must be one of: {', '.join(sorted(VALID_AGENT_STATUSES))}"
            )
        
        writer = AgentWriter(db)
        
        # Verify agent exists
        agent = await writer.get_agent(agent_id)
        if not agent:
            raise HTTPException(
                status_code=404,
                detail=f"Agent not found: {agent_id}"
            )
        
        # Update agent status
        await writer.update_status(agent_id, request.status)
        
        return {"status": "ok", "agent_id": agent_id, "new_status": request.status}
    except HTTPException:
        # Re-raise HTTP exceptions as-is
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Database error during status update: {str(e)}"
        )


@router.get("", response_model=AgentListResponse)
async def get_agents(
    db: Database = Depends(get_db),
):
    """
    Get all registered agents for the current project.
    
    Returns a list of agents from the database-backed registry.
    
    Args:
        db: Database connection from dependency injection
    
    Returns:
        AgentListResponse with agents list and count
    
    Raises:
        HTTPException 500: On database error
    """
    try:
        # Get project_id from config (dev mode)
        project_id = config.DEV_PROJECT_ID
        
        # Fetch agents from database
        writer = AgentWriter(db)
        agent_records = await writer.list_agents(project_id)
        
        # Transform database records to AgentResponse objects
        agents = [
            AgentResponse(
                id=record["id"],
                project_id=record["project_id"],
                name=record["name"],
                type=record["type"],
                status=record["status"],
                heartbeat_at=record.get("heartbeat_at"),
                metadata=record.get("metadata") or {},
                created_at=record["created_at"],
                updated_at=record["updated_at"],
            )
            for record in agent_records
        ]
        
        return AgentListResponse(agents=agents, count=len(agents))
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Database error while fetching agents: {str(e)}"
        )


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


# --- Run Control Endpoints (S-0040) ---
# NOTE: These endpoints are declared before /{agent_id} to ensure proper route matching.
# FastAPI matches routes in order, so /runs must be declared before /{agent_id}
# to prevent "runs" from being interpreted as an agent_id parameter.

@router.post("/runs", response_model=RunResponse, status_code=201)
async def create_run(
    request: RunCreateRequest,
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Create a new run and send START command to the agent.
    
    Creates a run record in the database with status='pending', then sends a START
    command to the agent via the control WebSocket. If the command is sent successfully,
    the run status is updated to 'running'.
    
    Args:
        request: RunCreateRequest with agent_id, optional requirement_id, and metadata
        db: Database connection from dependency injection
        user: Current user from authentication dependency
    
    Returns:
        RunResponse with the created run data (status 201)
    
    Raises:
        HTTPException 404: If agent not found
        HTTPException 503: If agent not connected to control WebSocket
        HTTPException 500: On database error
    """
    try:
        # Get project_id from config (dev mode)
        project_id = config.DEV_PROJECT_ID
        
        # Verify agent exists
        agent_writer = AgentWriter(db)
        agent = await agent_writer.get_agent(request.agent_id)
        if not agent:
            raise HTTPException(
                status_code=404,
                detail=f"Agent not found: {request.agent_id}"
            )
        
        # Verify agent is connected
        if not control_manager.is_connected(request.agent_id):
            raise HTTPException(
                status_code=503,
                detail=f"Agent not connected: {request.agent_id}. Agent must connect to the control WebSocket before runs can be created."
            )
        
        # Create run in database with status='pending'
        run_writer = RunWriter(db)
        run_record = await run_writer.create_run(
            project_id=project_id,
            agent_id=request.agent_id,
            requirement_id=request.requirement_id,
            metadata=request.metadata,
        )
        
        run_id = str(run_record["id"])
        
        # Send START command via control WebSocket
        command = {
            "type": "command",
            "command": CommandType.START.value,
            "run_id": run_id,
            "requirement_id": request.requirement_id,
            "metadata": request.metadata,
        }
        await control_manager.send_command(request.agent_id, command)
        
        # Update run status to 'running'
        await run_writer.update_run_status(run_id, "running")
        
        # Fetch updated run to return
        updated_run = await run_writer.get_run(run_id)
        
        return RunResponse(
            id=str(updated_run["id"]),
            project_id=str(updated_run["project_id"]),
            agent_id=str(updated_run["agent_id"]),
            requirement_id=updated_run.get("requirement_id"),
            status=updated_run["status"],
            started_at=updated_run.get("started_at"),
            completed_at=updated_run.get("completed_at"),
            error=updated_run.get("error"),
            metadata=updated_run.get("metadata") or {},
            agent_name=agent.get("name"),  # Include agent name from earlier lookup
        )
    except HTTPException:
        # Re-raise HTTP exceptions as-is
        raise
    except ValueError as e:
        # ValueError from control_manager.send_command when agent disconnects
        raise HTTPException(
            status_code=503,
            detail=f"Failed to send command to agent: {str(e)}"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Database error during run creation: {str(e)}"
        )


@router.post("/runs/{run_id}/stop", status_code=200)
async def stop_run(
    run_id: str,
    db: Database = Depends(get_db),
):
    """
    Stop a running run by sending STOP command to the agent.
    
    Verifies the run exists and the associated agent is connected, then sends a STOP
    command via the control WebSocket. The agent is responsible for updating the run
    status upon receiving the command.
    
    Args:
        run_id: The run ID to stop (UUID string)
        db: Database connection from dependency injection
    
    Returns:
        {"status": "ok", "run_id": run_id, "message": "STOP command sent"}
    
    Raises:
        HTTPException 404: If run not found
        HTTPException 503: If agent not connected to control WebSocket
        HTTPException 500: On database error
    """
    try:
        # Verify run exists
        run_writer = RunWriter(db)
        run = await run_writer.get_run(run_id)
        if not run:
            raise HTTPException(
                status_code=404,
                detail=f"Run not found: {run_id}"
            )
        
        agent_id = str(run["agent_id"])
        
        # Verify agent is connected
        if not control_manager.is_connected(agent_id):
            raise HTTPException(
                status_code=503,
                detail=f"Agent not connected: {agent_id}. Cannot send STOP command."
            )
        
        # Send STOP command via control WebSocket
        command = {
            "type": "command",
            "command": CommandType.STOP.value,
            "run_id": run_id,
        }
        await control_manager.send_command(agent_id, command)
        
        return {"status": "ok", "run_id": run_id, "message": "STOP command sent"}
    except HTTPException:
        # Re-raise HTTP exceptions as-is
        raise
    except ValueError as e:
        # ValueError from control_manager.send_command when agent disconnects
        raise HTTPException(
            status_code=503,
            detail=f"Failed to send command to agent: {str(e)}"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Database error during run stop: {str(e)}"
        )


@router.get("/runs", response_model=RunListResponse)
async def list_runs(
    limit: int = 50,
    db: Database = Depends(get_db),
):
    """
    List recent runs for the current project.
    
    Returns runs ordered by creation time (most recent first), with a configurable
    limit on the number of results.
    
    Args:
        limit: Maximum number of runs to return (default: 50)
        db: Database connection from dependency injection
    
    Returns:
        RunListResponse with runs list and count
    
    Raises:
        HTTPException 500: On database error
    """
    try:
        # Get project_id from config (dev mode)
        project_id = config.DEV_PROJECT_ID
        
        # Fetch runs from database
        run_writer = RunWriter(db)
        run_records = await run_writer.list_runs(project_id, limit=limit)
        
        # Transform database records to RunResponse objects
        runs = [
            RunResponse(
                id=str(record["id"]),
                project_id=str(record["project_id"]),
                agent_id=str(record["agent_id"]),
                requirement_id=record.get("requirement_id"),
                status=record["status"],
                started_at=record.get("started_at"),
                completed_at=record.get("completed_at"),
                error=record.get("error"),
                metadata=record.get("metadata") or {},
                agent_name=record.get("agent_name"),
            )
            for record in run_records
        ]
        
        return RunListResponse(runs=runs, count=len(runs))
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Database error while fetching runs: {str(e)}"
        )


@router.get("/runs/{run_id}", response_model=RunResponse)
async def get_run(
    run_id: str,
    db: Database = Depends(get_db),
):
    """
    Get a single run by ID.
    
    Fetches the run record from the database along with the associated agent name.
    
    Args:
        run_id: The run ID (UUID string)
        db: Database connection from dependency injection
    
    Returns:
        RunResponse with the run data
    
    Raises:
        HTTPException 404: If run not found
        HTTPException 500: On database error
    """
    try:
        run_writer = RunWriter(db)
        
        # Fetch run from database
        run = await run_writer.get_run(run_id)
        if not run:
            raise HTTPException(
                status_code=404,
                detail=f"Run not found: {run_id}"
            )
        
        # Fetch agent name for the response
        agent_writer = AgentWriter(db)
        agent = await agent_writer.get_agent(str(run["agent_id"]))
        agent_name = agent.get("name") if agent else None
        
        # Transform to RunResponse
        return RunResponse(
            id=str(run["id"]),
            project_id=str(run["project_id"]),
            agent_id=str(run["agent_id"]),
            requirement_id=run.get("requirement_id"),
            status=run["status"],
            started_at=run.get("started_at"),
            completed_at=run.get("completed_at"),
            error=run.get("error"),
            metadata=run.get("metadata") or {},
            agent_name=agent_name,
        )
    except HTTPException:
        # Re-raise HTTP exceptions as-is
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Database error while fetching run: {str(e)}"
        )


# --- Agent ID-Parameterized Endpoints ---
# NOTE: These endpoints use /{agent_id} path parameter and must be declared AFTER
# the /runs endpoints above to prevent "runs" from being interpreted as an agent_id.

@router.get("/{agent_id}", response_model=AgentResponse)
async def get_agent(
    agent_id: str,
    db: Database = Depends(get_db),
):
    """
    Get a single agent by ID.
    
    Fetches the agent record from the database.
    
    Args:
        agent_id: The agent ID (string UUID)
        db: Database connection from dependency injection
    
    Returns:
        AgentResponse with the agent data
    
    Raises:
        HTTPException 404: If agent not found
        HTTPException 500: On database error
    """
    try:
        writer = AgentWriter(db)
        
        # Fetch agent from database
        agent = await writer.get_agent(agent_id)
        if not agent:
            raise HTTPException(
                status_code=404,
                detail=f"Agent not found: {agent_id}"
            )
        
        # Transform to AgentResponse
        return AgentResponse(
            id=agent["id"],
            project_id=agent["project_id"],
            name=agent["name"],
            type=agent["type"],
            status=agent["status"],
            heartbeat_at=agent.get("heartbeat_at"),
            metadata=agent.get("metadata") or {},
            created_at=agent["created_at"],
            updated_at=agent["updated_at"],
        )
    except HTTPException:
        # Re-raise HTTP exceptions as-is
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Database error while fetching agent: {str(e)}"
        )


@router.post("/{agent_id}/stop")
async def stop_agent(agent_id: str, mode: str = "graceful"):
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
async def start_agent(agent_id: str, request: AgentStartRequest):
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
    Read new content from a file starting from last_position using async I/O.
    
    Handles file rotation: if the file size shrinks (indicating truncation or rotation),
    resets position to the beginning of the file.
    
    Returns:
        tuple: (new_content, new_position)
    """
    try:
        if not file_path.exists():
            return "", last_position
        
        file_size = file_path.stat().st_size
        
        # If file was truncated/rotated (size shrunk), start from beginning
        if file_size < last_position:
            last_position = 0
        
        # Read new content using async file I/O
        async with aiofiles.open(file_path, 'r', encoding='utf-8', errors='replace') as f:
            await f.seek(last_position)
            new_content = await f.read()
            new_position = await f.tell()
        
        return new_content, new_position
    except (IOError, OSError) as e:
        return f"[Error reading file: {e}]", last_position


@router.websocket("/{agent_id}/console")
async def agent_console_stream(
    websocket: WebSocket,
    agent_id: int,
    run_id: str = None,
    from_start: bool = False,
):
    """
    WebSocket endpoint for streaming agent console output.
    
    Streams console output from runs/{run_id}/output.log in real-time.
    
    Query parameters:
    - run_id: Run ID to stream logs for (required)
    - from_start: If true, stream from beginning of file (default: false, stream from end)
    
    Messages sent to client:
    - {"type": "connected", "agent_id": 0, "message": "...", "run_id": "..."}
    - {"type": "output", "content": "...", "run_id": "..."}
    - {"error": "..."} - Error message
    
    Error responses:
    - {"error": "run_id query parameter is required"} - when run_id is not provided
    - {"error": "Log file not found: runs/{run_id}/output.log"} - when log file doesn't exist
    """
    await websocket.accept()
    
    # Validate run_id is provided (required parameter)
    if not run_id:
        await websocket.send_json({"error": "run_id query parameter is required"})
        await websocket.close()
        return
    
    # Get project path
    project_path = _get_project_path_for_agent()
    if not project_path:
        await websocket.send_json({"error": "No project registered. Cannot stream console output."})
        await websocket.close()
        return
    
    # Construct log path from run_id
    log_path = project_path / "runs" / run_id / "output.log"
    
    # Check if log file exists
    if not log_path.exists():
        await websocket.send_json({"error": f"Log file not found: runs/{run_id}/output.log"})
        await websocket.close()
        return
    
    # Send connected message
    await websocket.send_json({
        "type": "connected",
        "agent_id": agent_id,
        "message": f"Connected to console stream for run {run_id}",
        "run_id": run_id
    })
    
    # State for tailing
    last_file_position: int = 0
    
    # If not starting from beginning, seek to end of file
    if not from_start:
        try:
            last_file_position = log_path.stat().st_size
        except (IOError, OSError):
            last_file_position = 0
    
    try:
        while True:
            # Read new output from the log file
            new_content, last_file_position = await _tail_file(log_path, last_file_position)
            
            if new_content:
                await websocket.send_json({
                    "type": "output",
                    "content": new_content,
                    "run_id": run_id
                })
            
            # Poll interval - 100ms for responsive streaming
            await asyncio.sleep(0.1)
            
    except WebSocketDisconnect:
        # Client disconnected normally
        pass
    except asyncio.CancelledError:
        # Task was cancelled
        pass
    except Exception as e:
        try:
            await websocket.send_json({"error": f"Stream error: {str(e)}"})
        except Exception:
            pass
    finally:
        try:
            await websocket.close()
        except Exception:
            pass


# --- Control WebSocket for Bidirectional Agent Communication ---

# Configure logger for control WebSocket
import logging
_control_logger = logging.getLogger(__name__)


@router.websocket("/{agent_id}/control")
async def agent_control_websocket(
    websocket: WebSocket,
    agent_id: str,
    db: Database = Depends(get_db),
):
    """
    WebSocket endpoint for bidirectional agent control communication.
    
    This endpoint allows:
    - Backend to send commands to agents (START, STOP, PAUSE, RESUME)
    - Agents to send status updates and heartbeats to the backend
    
    Message Protocol:
    
    Commands (backend → agent):
        {"type": "command", "command": "START|STOP|PAUSE|RESUME", "run_id": "...", "requirement_id": "..."}
    
    Status (agent → backend):
        {"type": "status", "status": "running|idle|stopped|error", "run_id": "..."}
    
    Heartbeat (agent → backend):
        {"type": "heartbeat"}
    
    Args:
        websocket: The WebSocket connection
        agent_id: The agent ID (string UUID)
        db: Database connection from dependency injection
    
    Note:
        This is distinct from the console WebSocket endpoint which only streams
        logs unidirectionally (backend → frontend).
    """
    # Accept connection via control manager
    await control_manager.connect(agent_id, websocket)
    
    try:
        # Create writer for database operations
        writer = AgentWriter(db)
        
        # Receive loop for incoming messages from agent
        while True:
            # Receive message from agent
            data = await websocket.receive_json()
            message_type = data.get("type")
            
            if message_type == "heartbeat":
                # Update heartbeat timestamp in database
                try:
                    await writer.update_heartbeat(agent_id)
                    _control_logger.debug(f"Agent {agent_id}: heartbeat received")
                except Exception as e:
                    _control_logger.error(f"Agent {agent_id}: failed to update heartbeat: {e}")
            
            elif message_type == "status":
                # Update agent status in database
                status_value = data.get("status")
                run_id = data.get("run_id")
                
                if status_value:
                    try:
                        await writer.update_status(agent_id, status_value)
                        _control_logger.info(f"Agent {agent_id}: status updated to {status_value}")
                        
                        # Broadcast status for future Supabase Realtime integration
                        await control_manager.broadcast_status(agent_id, {
                            "status": status_value,
                            "run_id": run_id,
                        })
                    except Exception as e:
                        _control_logger.error(f"Agent {agent_id}: failed to update status: {e}")
                else:
                    _control_logger.warning(f"Agent {agent_id}: status message missing 'status' field")
            
            else:
                # Unknown message type
                _control_logger.warning(f"Agent {agent_id}: unknown message type '{message_type}'")
    
    except WebSocketDisconnect:
        # Agent disconnected normally - not an error
        _control_logger.info(f"Agent {agent_id}: disconnected from control WebSocket")
    
    except Exception as e:
        # Log unexpected errors
        _control_logger.error(f"Agent {agent_id}: control WebSocket error: {e}")
    
    finally:
        # Clean up connection
        await control_manager.disconnect(agent_id)
