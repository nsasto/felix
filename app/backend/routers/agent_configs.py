"""
Felix Backend - Agent Configuration API
Manages agent configurations stored in felix/agents.json.
These are agent templates/presets, separate from the runtime agent registry.
"""
import json
from pathlib import Path
from typing import List, Dict, Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

import storage


router = APIRouter(prefix="/api/agent-configs", tags=["agent-configs"])


# --- Request/Response Models ---

class AgentConfigEntry(BaseModel):
    """Agent configuration entry"""
    id: int = Field(..., description="Unique agent ID (0 = system default)")
    name: str = Field(..., description="Display name for the agent")
    executable: str = Field(default="droid", description="Agent executable path")
    args: List[str] = Field(default_factory=list, description="Command line arguments")
    working_directory: str = Field(default=".", description="Working directory")
    environment: Dict[str, str] = Field(default_factory=dict, description="Environment variables")


class AgentConfigCreate(BaseModel):
    """Request body for creating a new agent configuration"""
    name: str = Field(..., description="Display name for the agent")
    executable: str = Field(default="droid", description="Agent executable path")
    args: List[str] = Field(default_factory=list, description="Command line arguments")
    working_directory: str = Field(default=".", description="Working directory")
    environment: Dict[str, str] = Field(default_factory=dict, description="Environment variables")


class AgentConfigUpdate(BaseModel):
    """Request body for updating an agent configuration"""
    name: Optional[str] = Field(None, description="Display name for the agent")
    executable: Optional[str] = Field(None, description="Agent executable path")
    args: Optional[List[str]] = Field(None, description="Command line arguments")
    working_directory: Optional[str] = Field(None, description="Working directory")
    environment: Optional[Dict[str, str]] = Field(None, description="Environment variables")


class AgentConfigsResponse(BaseModel):
    """Response containing all agent configurations"""
    agents: List[AgentConfigEntry]
    active_agent_id: int = Field(..., description="Currently active agent ID from config")


class AgentConfigResponse(BaseModel):
    """Response for a single agent configuration operation"""
    agent: AgentConfigEntry
    message: str


class SetActiveAgentRequest(BaseModel):
    """Request body for setting the active agent"""
    agent_id: int = Field(..., description="Agent ID to set as active")


class SetActiveAgentResponse(BaseModel):
    """Response for setting active agent"""
    agent_id: int
    message: str


# --- Helper Functions ---

def get_agents_json_path() -> Path:
    """Get the path to the felix/agents.json file in the global Felix home"""
    return storage.get_felix_home() / "agents.json"


def get_config_json_path() -> Path:
    """Get the path to the felix/config.json file in the global Felix home"""
    return storage.get_felix_home() / "config.json"


def load_agents_config() -> Dict:
    """Load agents configuration from felix/agents.json"""
    agents_path = get_agents_json_path()
    
    if not agents_path.exists():
        # Create default agents.json with system default agent
        default_data = {
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
        agents_path.parent.mkdir(parents=True, exist_ok=True)
        agents_path.write_text(json.dumps(default_data, indent=2), encoding='utf-8')
        return default_data
    
    try:
        return json.loads(agents_path.read_text(encoding='utf-8'))
    except json.JSONDecodeError as e:
        raise HTTPException(status_code=500, detail=f"Failed to parse agents.json: {str(e)}")


def save_agents_config(data: Dict) -> None:
    """Save agents configuration to felix/agents.json"""
    agents_path = get_agents_json_path()
    agents_path.parent.mkdir(parents=True, exist_ok=True)
    agents_path.write_text(json.dumps(data, indent=2), encoding='utf-8')


def get_active_agent_id() -> int:
    """Get the active agent ID from config.json"""
    config_path = get_config_json_path()
    
    if not config_path.exists():
        return 0  # Default to system default agent
    
    try:
        config_data = json.loads(config_path.read_text(encoding='utf-8-sig'))
        agent_config = config_data.get("agent", {})
        
        # Check for new agent_id field
        if "agent_id" in agent_config:
            return agent_config["agent_id"]
        
        # Legacy inline config - default to 0
        return 0
    except json.JSONDecodeError:
        return 0


def set_active_agent_id(agent_id: int) -> None:
    """Set the active agent ID in config.json"""
    config_path = get_config_json_path()
    
    # Load existing config or create default
    if config_path.exists():
        try:
            config_data = json.loads(config_path.read_text(encoding='utf-8-sig'))
        except json.JSONDecodeError:
            config_data = {}
    else:
        config_data = {}
    
    # Ensure agent section exists
    if "agent" not in config_data:
        config_data["agent"] = {}
    
    # Set agent_id, remove legacy fields if present
    config_data["agent"]["agent_id"] = agent_id
    
    # Keep legacy fields for backward compatibility during transition
    # These will be ignored when agent_id is present
    
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(config_data, indent=2), encoding='utf-8')


def get_next_agent_id(agents_data: Dict) -> int:
    """Get the next available agent ID"""
    agents = agents_data.get("agents", [])
    if not agents:
        return 1  # Start from 1 since 0 is reserved for system default
    
    max_id = max(agent.get("id", 0) for agent in agents)
    return max_id + 1


def validate_agent_exists(agents_data: Dict, agent_id: int) -> Optional[Dict]:
    """Check if an agent with the given ID exists, return the agent or None"""
    agents = agents_data.get("agents", [])
    for agent in agents:
        if agent.get("id") == agent_id:
            return agent
    return None


# --- API Endpoints ---

@router.get("", response_model=AgentConfigsResponse)
async def get_agent_configs():
    """
    Get all agent configurations from felix/agents.json.
    
    Returns the list of agent configurations along with the currently active agent ID.
    """
    agents_data = load_agents_config()
    active_id = get_active_agent_id()
    
    # Validate active_id exists, fallback to 0 if not
    if not validate_agent_exists(agents_data, active_id):
        active_id = 0
    
    agents = [AgentConfigEntry(**agent) for agent in agents_data.get("agents", [])]
    
    return AgentConfigsResponse(
        agents=agents,
        active_agent_id=active_id
    )


@router.get("/{agent_id}", response_model=AgentConfigResponse)
async def get_agent_config(agent_id: int):
    """
    Get a specific agent configuration by ID.
    """
    agents_data = load_agents_config()
    agent = validate_agent_exists(agents_data, agent_id)
    
    if not agent:
        raise HTTPException(status_code=404, detail=f"Agent with ID {agent_id} not found")
    
    return AgentConfigResponse(
        agent=AgentConfigEntry(**agent),
        message=f"Agent configuration retrieved: {agent.get('name', 'Unknown')}"
    )


@router.post("", response_model=AgentConfigResponse, status_code=201)
async def create_agent_config(request: AgentConfigCreate):
    """
    Create a new agent configuration.
    
    Automatically assigns the next available ID.
    """
    agents_data = load_agents_config()
    
    # Validate name is not empty
    if not request.name or not request.name.strip():
        raise HTTPException(status_code=400, detail="Agent name cannot be empty")
    
    # Get next available ID
    new_id = get_next_agent_id(agents_data)
    
    # Create new agent entry
    new_agent = {
        "id": new_id,
        "name": request.name.strip(),
        "executable": request.executable,
        "args": request.args,
        "working_directory": request.working_directory,
        "environment": request.environment
    }
    
    agents_data["agents"].append(new_agent)
    save_agents_config(agents_data)
    
    return AgentConfigResponse(
        agent=AgentConfigEntry(**new_agent),
        message=f"Agent configuration created with ID {new_id}"
    )


@router.put("/{agent_id}", response_model=AgentConfigResponse)
async def update_agent_config(agent_id: int, request: AgentConfigUpdate):
    """
    Update an existing agent configuration.
    
    All fields are optional - only provided fields are updated.
    """
    agents_data = load_agents_config()
    
    # Find the agent
    agents = agents_data.get("agents", [])
    agent_index = None
    for i, agent in enumerate(agents):
        if agent.get("id") == agent_id:
            agent_index = i
            break
    
    if agent_index is None:
        raise HTTPException(status_code=404, detail=f"Agent with ID {agent_id} not found")
    
    # Update fields if provided
    agent = agents[agent_index]
    
    if request.name is not None:
        if not request.name.strip():
            raise HTTPException(status_code=400, detail="Agent name cannot be empty")
        agent["name"] = request.name.strip()
    
    if request.executable is not None:
        agent["executable"] = request.executable
    
    if request.args is not None:
        agent["args"] = request.args
    
    if request.working_directory is not None:
        agent["working_directory"] = request.working_directory
    
    if request.environment is not None:
        agent["environment"] = request.environment
    
    agents_data["agents"][agent_index] = agent
    save_agents_config(agents_data)
    
    return AgentConfigResponse(
        agent=AgentConfigEntry(**agent),
        message=f"Agent configuration updated: {agent.get('name', 'Unknown')}"
    )


@router.delete("/{agent_id}")
async def delete_agent_config(agent_id: int):
    """
    Delete an agent configuration.
    
    Agent ID 0 (system default) cannot be deleted.
    If deleting the currently active agent, switches to agent ID 0.
    """
    # Protect system default agent
    if agent_id == 0:
        raise HTTPException(
            status_code=403,
            detail="Cannot delete system default agent (ID 0)"
        )
    
    agents_data = load_agents_config()
    
    # Find the agent
    agents = agents_data.get("agents", [])
    agent_to_delete = None
    new_agents = []
    
    for agent in agents:
        if agent.get("id") == agent_id:
            agent_to_delete = agent
        else:
            new_agents.append(agent)
    
    if not agent_to_delete:
        raise HTTPException(status_code=404, detail=f"Agent with ID {agent_id} not found")
    
    agents_data["agents"] = new_agents
    save_agents_config(agents_data)
    
    # If deleting the active agent, switch to system default
    active_id = get_active_agent_id()
    if active_id == agent_id:
        set_active_agent_id(0)
        return {
            "status": "deleted",
            "agent_id": agent_id,
            "message": f"Agent '{agent_to_delete.get('name', 'Unknown')}' deleted. Active agent switched to system default (ID 0)."
        }
    
    return {
        "status": "deleted",
        "agent_id": agent_id,
        "message": f"Agent '{agent_to_delete.get('name', 'Unknown')}' deleted."
    }


@router.post("/active", response_model=SetActiveAgentResponse)
async def set_active_agent(request: SetActiveAgentRequest):
    """
    Set the active agent by ID.
    
    Updates config.json to use the specified agent_id.
    """
    agents_data = load_agents_config()
    
    # Validate agent exists
    agent = validate_agent_exists(agents_data, request.agent_id)
    if not agent:
        raise HTTPException(
            status_code=404,
            detail=f"Agent with ID {request.agent_id} not found"
        )
    
    set_active_agent_id(request.agent_id)
    
    return SetActiveAgentResponse(
        agent_id=request.agent_id,
        message=f"Active agent set to '{agent.get('name', 'Unknown')}' (ID {request.agent_id})"
    )


@router.get("/active/current", response_model=AgentConfigResponse)
async def get_active_agent():
    """
    Get the currently active agent configuration.
    
    Returns the full agent config for the active agent ID.
    Falls back to ID 0 if the active ID is invalid.
    """
    agents_data = load_agents_config()
    active_id = get_active_agent_id()
    
    # Find active agent
    agent = validate_agent_exists(agents_data, active_id)
    
    # Fallback to system default if active agent doesn't exist
    if not agent:
        agent = validate_agent_exists(agents_data, 0)
        if agent:
            # Auto-correct config
            set_active_agent_id(0)
            return AgentConfigResponse(
                agent=AgentConfigEntry(**agent),
                message=f"⚠️ Configured agent (ID {active_id}) not found. Using system default."
            )
        else:
            raise HTTPException(
                status_code=500,
                detail="No agent configurations found, including system default"
            )
    
    return AgentConfigResponse(
        agent=AgentConfigEntry(**agent),
        message=f"Active agent: {agent.get('name', 'Unknown')}"
    )
