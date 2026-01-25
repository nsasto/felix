"""
Felix Backend - Pydantic Models
Data validation and serialization schemas.
"""
from typing import Optional, List
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
