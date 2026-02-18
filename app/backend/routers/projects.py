"""
Felix Backend - Project Management API
Handles project registration, listing, and details.
"""

from fastapi import APIRouter, HTTPException, Depends
from typing import List, Dict, Any

import sys
from pathlib import Path
from databases import Database

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from models import ProjectRegister, ProjectUpdate, Project, ProjectDetails
from auth import get_current_user
from database import get_db
from repositories import PostgresProjectRepository
from services.projects import (
    validate_git_url,
)

router = APIRouter(prefix="/api/projects", tags=["projects"])


@router.post("/register", response_model=Project)
async def register_project(
    request: ProjectRegister,
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Register a project with Felix using its git repository URL.

    The git URL is used for project identity and authentication.
    """
    try:
        git_url = request.git_url.strip()
        if not git_url:
            raise ValueError("Git URL is required")

        validate_git_url(git_url)

        repo = PostgresProjectRepository(db)
        project_name = (
            request.name.strip()
            if request.name and request.name.strip()
            else "Untitled Project"
        )
        project = await repo.create_project(
            org_id=user["org_id"],
            name=project_name,
            git_url=git_url,
        )
        return Project(
            id=str(project["id"]),
            git_url=project["git_url"],
            name=project.get("name"),
            registered_at=project["created_at"],
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Failed to register project: {str(e)}"
        )


@router.get("", response_model=List[Project])
async def list_projects(
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    List all registered projects.
    """
    repo = PostgresProjectRepository(db)
    projects = await repo.list_by_org(user["org_id"])
    return [
        Project(
            id=str(project["id"]),
            git_url=project["git_url"],
            name=project.get("name"),
            registered_at=project["created_at"],
        )
        for project in projects
    ]


@router.get("/{project_id}", response_model=ProjectDetails)
async def get_project(
    project_id: str,
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Get detailed information about a specific project.
    """
    repo = PostgresProjectRepository(db)
    project = await repo.get_by_id(user["org_id"], project_id)
    if not project:
        raise HTTPException(status_code=404, detail=f"Project not found: {project_id}")

    # Note: Spec count and has_specs would require file system access for remote projects
    # For now, return basic details. In future, this could query run_artifacts for spec files.
    return ProjectDetails(
        id=str(project["id"]),
        git_url=project["git_url"],
        name=project.get("name"),
        registered_at=project["created_at"],
        has_specs=False,
        has_requirements=False,
        spec_count=0,
        status=None,
    )


@router.put("/{project_id}", response_model=Project)
async def update_project(
    project_id: str,
    request: ProjectUpdate,
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Update project metadata (name, git_url).
    """
    try:
        name_value = request.name
        if name_value is not None:
            name_value = name_value.strip()
            if not name_value:
                name_value = ""

        # Validate git URL if provided
        git_url_value = None
        if request.git_url is not None:
            git_url_value = request.git_url.strip() if request.git_url.strip() else None
            if git_url_value:
                validate_git_url(git_url_value)

        repo = PostgresProjectRepository(db)
        project = await repo.update_project(
            user["org_id"],
            project_id,
            name=name_value,
            git_url=git_url_value,
        )
        if project:
            return Project(
                id=str(project["id"]),
                git_url=project["git_url"],
                name=project.get("name"),
                registered_at=project["created_at"],
            )
        raise HTTPException(status_code=404, detail=f"Project not found: {project_id}")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        print(f"Error updating project {project_id}: {str(e)}")
        import traceback

        traceback.print_exc()
        raise HTTPException(
            status_code=500, detail=f"Failed to update project: {str(e)}"
        )


@router.delete("/{project_id}")
async def unregister_project(
    project_id: str,
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Unregister a project (does not delete files).
    """
    repo = PostgresProjectRepository(db)
    deleted = await repo.delete_project(user["org_id"], project_id)
    if deleted:
        return {"message": f"Project {project_id} unregistered"}
    raise HTTPException(status_code=404, detail=f"Project not found: {project_id}")
