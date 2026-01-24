"""
Felix Backend - Project Management API
Handles project registration, listing, and details.
"""
from fastapi import APIRouter, HTTPException
from typing import List

import sys
from pathlib import Path
# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from models import ProjectRegister, Project, ProjectDetails
import storage

router = APIRouter(prefix="/api/projects", tags=["projects"])


@router.post("/register", response_model=Project)
async def register_project(request: ProjectRegister):
    """
    Register a project directory with Felix.
    
    The directory must have a valid Felix structure:
    - felix/ directory
    - specs/ directory
    """
    try:
        project = storage.register_project(request.path, request.name)
        return project
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to register project: {str(e)}")


@router.get("", response_model=List[Project])
async def list_projects():
    """
    List all registered projects.
    """
    return storage.get_all_projects()


@router.get("/{project_id}", response_model=ProjectDetails)
async def get_project(project_id: str):
    """
    Get detailed information about a specific project.
    """
    details = storage.get_project_details(project_id)
    if not details:
        raise HTTPException(status_code=404, detail=f"Project not found: {project_id}")
    return details


@router.delete("/{project_id}")
async def unregister_project(project_id: str):
    """
    Unregister a project (does not delete files).
    """
    if storage.unregister_project(project_id):
        return {"message": f"Project {project_id} unregistered"}
    raise HTTPException(status_code=404, detail=f"Project not found: {project_id}")
