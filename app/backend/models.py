"""
Felix Backend - Pydantic Models
Data validation and serialization schemas.
"""
from typing import Optional, List, Dict, Any
from datetime import datetime
from pydantic import BaseModel, Field
from pathlib import Path


class ProjectBase(BaseModel):
    """Base project data"""
    path: str = Field(..., description="Absolute path to project directory")
    name: Optional[str] = Field(None, description="Project display name")


class ProjectRegister(ProjectBase):
    """Request body for registering a project"""
    pass


class ProjectUpdate(BaseModel):
    """Request body for updating a project"""
    name: Optional[str] = Field(None, description="New project display name")
    path: Optional[str] = Field(None, description="New project path")


class Project(ProjectBase):
    """Full project model with computed fields"""
    id: str = Field(..., description="Unique project identifier (derived from path)")
    registered_at: datetime = Field(default_factory=datetime.now)
    
    class Config:
        from_attributes = True


class ProjectDetails(Project):
    """Project with additional runtime details"""
    has_specs: bool = False
    has_requirements: bool = False
    spec_count: int = 0
    status: Optional[str] = None


class ProjectsStore(BaseModel):
    """Schema for ~/.felix/projects.json"""
    projects: List[Project] = Field(default_factory=list)
    updated_at: datetime = Field(default_factory=datetime.now)


# --- Agent API Models ---

class AgentRegisterRequest(BaseModel):
    """Request body for registering an agent via database-backed API"""
    agent_id: str = Field(..., description="Unique agent identifier (UUID string)")
    name: str = Field(..., description="Display name for the agent")
    type: str = Field(default="ralph", description="Agent type (e.g., 'ralph', 'builder', 'planner')")
    metadata: Optional[Dict[str, Any]] = Field(None, description="Optional JSON metadata for the agent")


class AgentStatusUpdate(BaseModel):
    """Request body for updating an agent's status"""
    status: str = Field(..., description="New status for the agent (idle, running, stopped, error)")


class AgentResponse(BaseModel):
    """Response model for a single agent from the database"""
    id: str = Field(..., description="Unique agent identifier (UUID string)")
    project_id: str = Field(..., description="Project ID the agent belongs to")
    name: str = Field(..., description="Display name for the agent")
    type: str = Field(..., description="Agent type (e.g., 'ralph', 'builder', 'planner')")
    status: str = Field(..., description="Current status (idle, running, stopped, error)")
    heartbeat_at: Optional[datetime] = Field(None, description="Last heartbeat timestamp")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="Agent metadata as JSON")
    created_at: datetime = Field(..., description="When the agent was created")
    updated_at: datetime = Field(..., description="When the agent was last updated")
    
    class Config:
        from_attributes = True


class AgentListResponse(BaseModel):
    """Response model for listing agents"""
    agents: List[AgentResponse] = Field(default_factory=list, description="List of agents")
    count: int = Field(..., description="Total number of agents returned")
