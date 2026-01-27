"""
Felix Backend - Agent Registry API
Handles agent registration, heartbeat, and status tracking.
"""
import json
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field


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


@router.post("/{agent_name}/stop", response_model=AgentStopResponse)
async def stop_agent(agent_name: str):
    """
    Mark an agent as stopped in the registry.
    
    This doesn't actually terminate the process - it just updates the registry.
    The agent should call this on graceful shutdown.
    """
    agents = load_agents_registry()
    
    if agent_name not in agents:
        raise HTTPException(status_code=404, detail=f"Agent not found: {agent_name}")
    
    agent = agents[agent_name]
    
    # Update status
    now = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')
    agent.status = "stopped"
    agent.stopped_at = now
    agent.current_run_id = None
    
    agents[agent_name] = agent
    save_agents_registry(agents)
    
    return AgentStopResponse(
        message=f"Agent '{agent_name}' marked as stopped",
        agent_name=agent_name,
        status="stopped"
    )
