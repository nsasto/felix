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
    normalize_project_path,
    validate_project_structure,
    ensure_project_path_exists,
    validate_git_repo,
)

router = APIRouter(prefix="/api/projects", tags=["projects"])


@router.post("/register", response_model=Project)
async def register_project(
    request: ProjectRegister,
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Register a project directory with Felix.

    The directory must have a valid Felix structure:
    - .felix/ directory
    - specs/ directory
    """
    try:
        project_path = normalize_project_path(request.path)
        validate_project_structure(project_path)

        repo = PostgresProjectRepository(db)
        project_name = (
            request.name.strip()
            if request.name and request.name.strip()
            else project_path.name
        )
        project = await repo.create_project(
            org_id=user["org_id"],
            name=project_name,
            path=str(project_path),
        )
        return Project(
            id=str(project["id"]),
            path=project["path"],
            name=project.get("name"),
            git_repo=project.get("git_repo"),
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
            path=project["path"],
            name=project.get("name"),
            git_repo=project.get("git_repo"),
            registered_at=project["created_at"],
        )
        for project in projects
        if project.get("path")
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

    project_path = project.get("path")
    if not project_path:
        raise HTTPException(
            status_code=404, detail=f"Project path not set: {project_id}"
        )

    try:
        project_dir = ensure_project_path_exists(project_path)
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))

    specs_dir = project_dir / "specs"
    spec_count = len(list(specs_dir.glob("*.md"))) if specs_dir.exists() else 0

    return ProjectDetails(
        id=str(project["id"]),
        path=project["path"],
        name=project.get("name"),
        registered_at=project["created_at"],
        has_specs=specs_dir.exists(),
        has_requirements=False,
        spec_count=spec_count,
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
    Update project metadata (name, path, git_repo).
    """
    try:
        new_path = None
        if request.path is not None and request.path.strip():
            project_path = normalize_project_path(request.path)
            validate_project_structure(project_path)
            new_path = str(project_path)

        name_value = request.name
        if name_value is not None:
            name_value = name_value.strip()
            if not name_value:
                name_value = ""

        # Validate git repo if provided
        git_repo_value = None
        if request.git_repo is not None:
            git_repo_value = (
                request.git_repo.strip() if request.git_repo.strip() else None
            )
            if git_repo_value:
                validate_git_repo(git_repo_value)

        repo = PostgresProjectRepository(db)
        project = await repo.update_project(
            user["org_id"],
            project_id,
            name=name_value,
            path=new_path,
            git_repo=git_repo_value,
        )
        if project:
            return Project(
                id=str(project["id"]),
                path=project["path"],
                name=project.get("name"),
                git_repo=project.get("git_repo"),
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
