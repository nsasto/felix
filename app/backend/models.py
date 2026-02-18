"""
Felix Backend - Pydantic Models
Data validation and serialization schemas.
"""

from typing import Optional, List, Dict, Any
from datetime import datetime
from pydantic import BaseModel, Field
from pathlib import Path


class OrganizationMember(BaseModel):
    """Organization member record with profile details."""

    id: str
    org_id: str
    user_id: str
    role: str
    email: Optional[str] = None
    display_name: Optional[str] = None
    full_name: Optional[str] = None
    created_at: datetime
    updated_at: Optional[datetime] = None


class OrganizationInvite(BaseModel):
    """Organization invite record."""

    id: str
    org_id: str
    email: str
    role: str
    status: str
    invited_by_user_id: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class OrganizationMembersResponse(BaseModel):
    members: List[OrganizationMember] = Field(default_factory=list)
    invites: List[OrganizationInvite] = Field(default_factory=list)


class OrganizationInviteRequest(BaseModel):
    email: str = Field(..., description="Invitee email")
    role: str = Field(default="member", description="Role for the invitee")


class OrganizationInviteUpdate(BaseModel):
    role: str = Field(..., description="Updated role for invite")


class OrganizationMemberRoleUpdate(BaseModel):
    role: str = Field(..., description="Updated role for member")


class ProjectBase(BaseModel):
    """Base project data"""

    git_url: str = Field(..., description="Git repository URL for project identity")
    name: Optional[str] = Field(None, description="Project display name")


class ProjectRegister(ProjectBase):
    """Request body for registering a project"""

    pass


class ProjectUpdate(BaseModel):
    """Request body for updating a project"""

    name: Optional[str] = Field(None, description="New project display name")
    git_url: Optional[str] = Field(None, description="New git repository URL")


class Project(ProjectBase):
    """Full project model with computed fields"""

    id: str = Field(..., description="Unique project identifier (UUID)")
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
    type: str = Field(
        default="ralph", description="Agent type (e.g., 'ralph', 'builder', 'planner')"
    )
    profile_id: Optional[str] = Field(
        None, description="Agent profile ID (UUID string)"
    )
    git_url: Optional[str] = Field(
        None,
        description="Git repository URL for project authentication (alternative to explicit project_id)",
    )
    metadata: Optional[Dict[str, Any]] = Field(
        None, description="Optional JSON metadata for the agent"
    )


class AgentStatusUpdate(BaseModel):
    """Request body for updating an agent's status"""

    status: str = Field(
        ..., description="New status for the agent (idle, running, stopped, error)"
    )


class AgentResponse(BaseModel):
    """Response model for a single agent from the database"""

    id: str = Field(..., description="Unique agent identifier (UUID string)")
    project_id: str = Field(..., description="Project ID the agent belongs to")
    name: str = Field(..., description="Display name for the agent")
    type: str = Field(
        ..., description="Agent type (e.g., 'ralph', 'builder', 'planner')"
    )
    status: str = Field(
        ..., description="Current status (idle, running, stopped, error)"
    )
    heartbeat_at: Optional[datetime] = Field(
        None, description="Last heartbeat timestamp"
    )
    metadata: Dict[str, Any] = Field(
        default_factory=dict, description="Agent metadata as JSON"
    )
    profile_id: Optional[str] = Field(
        None, description="Agent profile ID (UUID string)"
    )
    created_at: datetime = Field(..., description="When the agent was created")
    updated_at: datetime = Field(..., description="When the agent was last updated")

    class Config:
        from_attributes = True


class AgentListResponse(BaseModel):
    """Response model for listing agents"""

    agents: List[AgentResponse] = Field(
        default_factory=list, description="List of agents"
    )
    count: int = Field(..., description="Total number of agents returned")


# --- Run API Models ---


class RunCreateRequest(BaseModel):
    """Request body for creating a new run"""

    agent_id: str = Field(..., description="Agent ID to execute the run (UUID string)")
    requirement_id: Optional[str] = Field(
        None, description="Requirement being worked on (optional)"
    )
    metadata: Optional[Dict[str, Any]] = Field(
        default_factory=dict, description="Optional JSON metadata for the run"
    )


class RunResponse(BaseModel):
    """Response model for a single run from the database"""

    id: str = Field(..., description="Unique run identifier (UUID string)")
    project_id: str = Field(..., description="Project ID the run belongs to")
    agent_id: str = Field(..., description="Agent ID executing the run")
    requirement_id: Optional[str] = Field(
        None, description="Requirement being worked on"
    )
    status: str = Field(
        ...,
        description="Current status (pending, running, completed, failed, cancelled)",
    )
    started_at: Optional[datetime] = Field(None, description="When the run started")
    completed_at: Optional[datetime] = Field(None, description="When the run completed")
    error: Optional[str] = Field(None, description="Error message if run failed")
    metadata: Dict[str, Any] = Field(
        default_factory=dict, description="Run metadata as JSON"
    )
    agent_name: Optional[str] = Field(
        None, description="Agent display name (joined from agents table)"
    )

    class Config:
        from_attributes = True


class RunListResponse(BaseModel):
    """Response model for listing runs"""

    runs: List[RunResponse] = Field(default_factory=list, description="List of runs")
    count: int = Field(..., description="Total number of runs returned")
