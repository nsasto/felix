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
    agent_name: str = Field(..., description="Unique agent name identifier")
    pid: int = Field(..., description="Process ID of the agent")
    hostname: str = Field(..., description="Hostname where agent is running")
    started_at: Optional[str] = Field(None, description="ISO timestamp when agent started")


class AgentHeartbeat(BaseModel):
    """Request body for heartbeat update"""
    current_run_id: Optional[str] = Field(None, description="Current requirement ID being worked on")


class AgentEntry(BaseModel):
    """Agent entry in the registry"""
    pid: int
    hostname: str
    status: str = Field(default="active", description="Agent status: active, inactive, stopped")
    current_run_id: Optional[str] = None
    started_at: Optional[str] = None
    last_heartbeat: Optional[str] = None
    stopped_at: Optional[str] = None


class AgentRegistryResponse(BaseModel):
    """Response containing all registered agents"""
    agents: Dict[str, AgentEntry]


class AgentStatusResponse(BaseModel):
    """Response for a single agent status"""
    agent_name: str
    status: str
    pid: int
    hostname: str
    current_run_id: Optional[str] = None
    started_at: Optional[str] = None
    last_heartbeat: Optional[str] = None
    stopped_at: Optional[str] = None


class AgentStopResponse(BaseModel):
    """Response for stopping an agent"""
    message: str
    agent_name: str
    status: str


class AgentStartRequest(BaseModel):
    """Request body for starting an agent with a specific requirement"""
    requirement_id: str = Field(..., description="Requirement ID to work on (e.g., 'S-0012')")


class AgentStartResponse(BaseModel):
    """Response for starting an agent"""
    message: str
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


def load_agents_registry() -> Dict[str, AgentEntry]:
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
        
        # Convert to AgentEntry objects
        result = {}
        for name, entry_data in agents_dict.items():
            result[name] = AgentEntry(**entry_data)
        return result
    except (json.JSONDecodeError, ValueError) as e:
        # Return empty on parse error
        print(f"Warning: Failed to parse agents.json: {e}")
        return {}


def save_agents_registry(agents: Dict[str, AgentEntry]):
    """Save agents to felix/agents.json"""
    agents_file = get_agents_file_path()
    
    # Ensure felix directory exists
    if not agents_file.parent.exists():
        raise HTTPException(
            status_code=500, 
            detail="Felix directory not found. Cannot save agents registry."
        )
    
    # Convert AgentEntry objects to dicts
    agents_dict = {name: entry.model_dump() for name, entry in agents.items()}
    
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


def update_agent_statuses(agents: Dict[str, AgentEntry]) -> Dict[str, AgentEntry]:
    """
    Update status of all agents based on liveness checks.
    Returns the updated agents dict.
    """
    for name, agent in agents.items():
        new_status = check_agent_liveness(agent)
        agent.status = new_status
    return agents


# --- API Endpoints ---

@router.post("/register", response_model=AgentStatusResponse)
async def register_agent(request: AgentRegistration):
    """
    Register an agent with the registry.
    
    If an agent with the same name exists:
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
    if request.agent_name in agents:
        existing = agents[request.agent_name]
        if existing.status == "active":
            raise HTTPException(
                status_code=409, 
                detail=f"Agent '{request.agent_name}' is already active (PID: {existing.pid}, Host: {existing.hostname})"
            )
    
    # Get current UTC timestamp
    now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    
    # Create or update agent entry
    agent_entry = AgentEntry(
        pid=request.pid,
        hostname=request.hostname,
        status="active",
        current_run_id=None,
        started_at=request.started_at or now,
        last_heartbeat=now,
        stopped_at=None
    )
    
    agents[request.agent_name] = agent_entry
    save_agents_registry(agents)
    
    return AgentStatusResponse(
        agent_name=request.agent_name,
        status=agent_entry.status,
        pid=agent_entry.pid,
        hostname=agent_entry.hostname,
        current_run_id=agent_entry.current_run_id,
        started_at=agent_entry.started_at,
        last_heartbeat=agent_entry.last_heartbeat,
        stopped_at=agent_entry.stopped_at
    )


@router.post("/{agent_name}/heartbeat", response_model=AgentStatusResponse)
async def agent_heartbeat(agent_name: str, request: AgentHeartbeat):
    """
    Update agent heartbeat and optionally the current run ID.
    
    Should be called every 5 seconds by running agents.
    Updates last_heartbeat timestamp and status to 'active'.
    """
    agents = load_agents_registry()
    
    if agent_name not in agents:
        raise HTTPException(status_code=404, detail=f"Agent not found: {agent_name}")
    
    agent = agents[agent_name]
    
    # Update heartbeat
    now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    agent.last_heartbeat = now
    agent.status = "active"
    
    # Update current run ID if provided
    if request.current_run_id is not None:
        agent.current_run_id = request.current_run_id
    
    # Clear stopped_at since agent is active again
    agent.stopped_at = None
    
    agents[agent_name] = agent
    save_agents_registry(agents)
    
    return AgentStatusResponse(
        agent_name=agent_name,
        status=agent.status,
        pid=agent.pid,
        hostname=agent.hostname,
        current_run_id=agent.current_run_id,
        started_at=agent.started_at,
        last_heartbeat=agent.last_heartbeat,
        stopped_at=agent.stopped_at
    )


@router.get("", response_model=AgentRegistryResponse)
async def get_agents():
    """
    Get all registered agents with their current status.
    
    Automatically updates status based on heartbeat staleness:
    - Agents with heartbeat > 10s old are marked 'inactive'
    - Stopped agents remain 'stopped'
    """
    agents = load_agents_registry()
    
    # Update statuses based on liveness
    agents = update_agent_statuses(agents)
    
    # Save updated statuses
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


@router.post("/{agent_name}/stop", response_model=AgentStopResponse)
async def stop_agent(agent_name: str, mode: str = "graceful"):
    """
    Stop an agent and mark it as stopped in the registry.
    
    Args:
        agent_name: The name of the agent to stop
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
    
    if agent_name not in agents:
        raise HTTPException(status_code=404, detail=f"Agent not found: {agent_name}")
    
    agent = agents[agent_name]
    
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
    
    agents[agent_name] = agent
    save_agents_registry(agents)
    
    stop_message = f"Agent '{agent_name}' stopped ({mode} mode)"
    
    return AgentStopResponse(
        message=stop_message,
        agent_name=agent_name,
        status="stopped"
    )


@router.post("/{agent_name}/start", response_model=AgentStartResponse)
async def start_agent(agent_name: str, request: AgentStartRequest):
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
        agent_name: The name of the agent to assign work to
        request: Contains requirement_id to work on
    
    Returns:
        AgentStartResponse with status information
    
    Raises:
        404: Agent not found in registry
        400: Requirement ID validation failed
        409: Agent is already working on a task
    """
    agents = load_agents_registry()
    
    if agent_name not in agents:
        raise HTTPException(status_code=404, detail=f"Agent not found: {agent_name}")
    
    agent = agents[agent_name]
    
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
            detail=f"Agent '{agent_name}' is already working on requirement '{agent.current_run_id}'"
        )
    
    # Update agent's current_run_id (this signals what the agent should work on)
    now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    agent.current_run_id = request.requirement_id
    agent.last_heartbeat = now
    
    # If agent was stopped or inactive, note that it needs to be started externally
    was_active = agent.status == "active"
    
    agents[agent_name] = agent
    save_agents_registry(agents)
    
    if was_active:
        message = f"Agent '{agent_name}' assigned to work on requirement '{request.requirement_id}'"
    else:
        message = f"Agent '{agent_name}' assigned requirement '{request.requirement_id}'. Note: Agent is {agent.status}, start the agent process separately."
    
    return AgentStartResponse(
        message=message,
        agent_name=agent_name,
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


@router.websocket("/{agent_name}/console")
async def agent_console_stream(websocket: WebSocket, agent_name: str):
    """
    WebSocket endpoint for streaming agent console output.
    
    Tails the current run's output.log and streams new lines in real-time.
    
    Messages sent to client:
    - {"type": "connected", "agent_name": "...", "message": "..."}
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
    
    if agent_name not in agents:
        await websocket.send_json({
            "type": "error",
            "message": f"Agent not found: {agent_name}"
        })
        await websocket.close(code=4004, reason="Agent not found")
        return
    
    agent = agents[agent_name]
    
    # Send connected message
    await websocket.send_json({
        "type": "connected",
        "agent_name": agent_name,
        "status": agent.status,
        "message": f"Connected to console stream for agent: {agent_name}"
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
