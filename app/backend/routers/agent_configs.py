"""
Felix Backend - Agent Configuration API
Manages agent configuration profiles stored in the database.
These are agent templates/presets, separate from the runtime agent registry.
"""
import json
from typing import List, Dict, Optional, Any

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, Field
from databases import Database

import config
from auth import get_current_user
from database.db import get_db
from repositories import PostgresAgentProfileRepository


router = APIRouter(prefix="/api/agent-configs", tags=["agent-configs"])


# --- Request/Response Models ---

class AgentConfigEntry(BaseModel):
    """Agent configuration entry"""
    id: str = Field(..., description="Unique agent profile ID (UUID)")
    name: str = Field(..., description="Display name for the agent")
    adapter: str = Field(default="droid", description="Agent adapter type")
    executable: str = Field(default="droid", description="Agent executable path")
    args: List[str] = Field(default_factory=list, description="Command line arguments")
    model: Optional[str] = Field(None, description="Optional model override")
    working_directory: str = Field(default=".", description="Working directory")
    environment: Dict[str, str] = Field(default_factory=dict, description="Environment variables")
    description: Optional[str] = Field(None, description="Optional description")


class AgentConfigCreate(BaseModel):
    """Request body for creating a new agent configuration"""
    name: str = Field(..., description="Display name for the agent")
    adapter: str = Field(default="droid", description="Agent adapter type")
    executable: str = Field(default="droid", description="Agent executable path")
    args: List[str] = Field(default_factory=list, description="Command line arguments")
    model: Optional[str] = Field(None, description="Optional model override")
    working_directory: str = Field(default=".", description="Working directory")
    environment: Dict[str, str] = Field(default_factory=dict, description="Environment variables")
    description: Optional[str] = Field(None, description="Optional description")


class AgentConfigUpdate(BaseModel):
    """Request body for updating an agent configuration"""
    name: Optional[str] = Field(None, description="Display name for the agent")
    adapter: Optional[str] = Field(None, description="Agent adapter type")
    executable: Optional[str] = Field(None, description="Agent executable path")
    args: Optional[List[str]] = Field(None, description="Command line arguments")
    model: Optional[str] = Field(None, description="Optional model override")
    working_directory: Optional[str] = Field(None, description="Working directory")
    environment: Optional[Dict[str, str]] = Field(None, description="Environment variables")
    description: Optional[str] = Field(None, description="Optional description")


class AgentConfigsResponse(BaseModel):
    """Response containing all agent configurations"""
    agents: List[AgentConfigEntry]
    active_agent_id: Optional[str] = Field(None, description="Currently active agent profile ID")


class AgentConfigResponse(BaseModel):
    """Response for a single agent configuration operation"""
    agent: AgentConfigEntry
    message: str


class SetActiveAgentRequest(BaseModel):
    """Request body for setting the active agent"""
    agent_id: str = Field(..., description="Agent profile ID to set as active")


class SetActiveAgentResponse(BaseModel):
    """Response for setting active agent"""
    agent_id: str
    message: str


def _extract_active_agent_id(org_metadata: Optional[Dict[str, Any]]) -> Optional[str]:
    if not org_metadata:
        return None
    value = org_metadata.get("active_agent_profile_id")
    return str(value) if value else None


async def get_active_agent_id(db: Database, org_id: str) -> Optional[str]:
    row = await db.fetch_one(
        "SELECT metadata FROM organizations WHERE id = :id",
        values={"id": org_id},
    )
    if not row:
        return None
    return _extract_active_agent_id(row["metadata"])


async def set_active_agent_id(db: Database, org_id: str, agent_id: Optional[str]) -> None:
    payload = json.dumps(agent_id) if agent_id else "null"
    await db.execute(
        """
        UPDATE organizations
        SET metadata = jsonb_set(
            COALESCE(metadata, '{}'::jsonb),
            '{active_agent_profile_id}',
            :payload::jsonb,
            true
        )
        WHERE id = :id
        """,
        values={"id": org_id, "payload": payload},
    )


def _to_entry(row: Dict[str, Any]) -> AgentConfigEntry:
    return AgentConfigEntry(
        id=str(row["id"]),
        name=row["name"],
        adapter=row["adapter"],
        executable=row["executable"],
        args=row.get("args") or [],
        model=row.get("model"),
        working_directory=row.get("working_directory") or ".",
        environment=row.get("environment") or {},
        description=row.get("description"),
    )


# --- API Endpoints ---

@router.get("", response_model=AgentConfigsResponse)
async def get_agent_configs(
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Get all agent configurations from the database.

    Returns the list of agent configurations along with the currently active agent ID.
    """
    repo = PostgresAgentProfileRepository(db)
    agents = await repo.list_by_org(user["org_id"])
    active_id = await get_active_agent_id(db, user["org_id"])
    return AgentConfigsResponse(
        agents=[_to_entry(agent) for agent in agents],
        active_agent_id=active_id,
    )


@router.get("/{agent_id}", response_model=AgentConfigResponse)
async def get_agent_config(
    agent_id: str,
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Get a specific agent configuration by ID.
    """
    repo = PostgresAgentProfileRepository(db)
    agent = await repo.get_by_id(user["org_id"], agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail=f"Agent with ID {agent_id} not found")
    return AgentConfigResponse(
        agent=_to_entry(agent),
        message=f"Agent configuration retrieved: {agent.get('name', 'Unknown')}",
    )


@router.post("", response_model=AgentConfigResponse, status_code=201)
async def create_agent_config(
    request: AgentConfigCreate,
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Create a new agent configuration.
    """
    if not request.name or not request.name.strip():
        raise HTTPException(status_code=400, detail="Agent name cannot be empty")

    repo = PostgresAgentProfileRepository(db)
    agent = await repo.create_profile(
        org_id=user["org_id"],
        name=request.name.strip(),
        adapter=request.adapter or "droid",
        executable=request.executable,
        args=request.args,
        model=request.model,
        working_directory=request.working_directory,
        environment=request.environment,
        description=request.description,
        source="user",
        created_by_user_id=user.get("user_id", config.DEV_USER_ID),
    )

    active_id = await get_active_agent_id(db, user["org_id"])
    if not active_id:
        await set_active_agent_id(db, user["org_id"], str(agent["id"]))

    return AgentConfigResponse(
        agent=_to_entry(agent),
        message=f"Agent configuration created with ID {agent['id']}",
    )


@router.put("/{agent_id}", response_model=AgentConfigResponse)
async def update_agent_config(
    agent_id: str,
    request: AgentConfigUpdate,
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Update an existing agent configuration.

    All fields are optional - only provided fields are updated.
    """
    repo = PostgresAgentProfileRepository(db)
    existing = await repo.get_by_id(user["org_id"], agent_id)
    if not existing:
        raise HTTPException(status_code=404, detail=f"Agent with ID {agent_id} not found")

    updates: Dict[str, Any] = {}
    for field in ("name", "adapter", "executable", "args", "model", "working_directory", "environment", "description"):
        value = getattr(request, field)
        if value is not None:
            updates[field] = value

    if "name" in updates and not str(updates["name"]).strip():
        raise HTTPException(status_code=400, detail="Agent name cannot be empty")

    await repo.update_profile(agent_id, updates)
    refreshed = await repo.get_by_id(user["org_id"], agent_id)
    return AgentConfigResponse(
        agent=_to_entry(refreshed),
        message=f"Agent configuration updated: {refreshed.get('name', 'Unknown')}",
    )


@router.delete("/{agent_id}")
async def delete_agent_config(
    agent_id: str,
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Delete an agent configuration.
    If deleting the currently active agent, clears the active selection.
    """
    repo = PostgresAgentProfileRepository(db)
    agent = await repo.get_by_id(user["org_id"], agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail=f"Agent with ID {agent_id} not found")

    await repo.delete_profile(agent_id)

    active_id = await get_active_agent_id(db, user["org_id"])
    if active_id == agent_id:
        remaining = await repo.list_by_org(user["org_id"])
        next_active = str(remaining[0]["id"]) if remaining else None
        await set_active_agent_id(db, user["org_id"], next_active)
        message = (
            f"Agent '{agent.get('name', 'Unknown')}' deleted. "
            f"Active agent switched to {next_active or 'none'}."
        )
        return {"status": "deleted", "agent_id": agent_id, "message": message}

    return {"status": "deleted", "agent_id": agent_id, "message": f"Agent '{agent.get('name', 'Unknown')}' deleted."}


@router.post("/active", response_model=SetActiveAgentResponse)
async def set_active_agent(
    request: SetActiveAgentRequest,
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Set the active agent by ID.
    """
    repo = PostgresAgentProfileRepository(db)
    agent = await repo.get_by_id(user["org_id"], request.agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail=f"Agent with ID {request.agent_id} not found")

    await set_active_agent_id(db, user["org_id"], request.agent_id)
    return SetActiveAgentResponse(
        agent_id=request.agent_id,
        message=f"Active agent set to '{agent.get('name', 'Unknown')}' (ID {request.agent_id})",
    )


@router.get("/active/current", response_model=AgentConfigResponse)
async def get_active_agent(
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Get the currently active agent configuration.
    Returns the full agent config for the active agent ID.
    """
    repo = PostgresAgentProfileRepository(db)
    active_id = await get_active_agent_id(db, user["org_id"])
    if not active_id:
        raise HTTPException(status_code=404, detail="No active agent configured")

    agent = await repo.get_by_id(user["org_id"], active_id)
    if not agent:
        raise HTTPException(status_code=404, detail=f"Agent with ID {active_id} not found")

    return AgentConfigResponse(
        agent=_to_entry(agent),
        message=f"Active agent: {agent.get('name', 'Unknown')}",
    )
