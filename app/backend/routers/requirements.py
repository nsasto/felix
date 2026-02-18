"""
Felix Backend - Requirements API
Handles requirement metadata and content (specs).
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from typing import Any, List, Optional

from databases import Database

from database import get_db
from services.requirements import RequirementService

router = APIRouter(prefix="/api/projects", tags=["requirements"])


class RequirementMetadataUpdate(BaseModel):
    field: str
    value: Any


class Requirement(BaseModel):
    id: str
    code: str | None = None
    uuid: str | None = None
    title: str
    spec_path: str | None = None
    status: str
    priority: str | None = None
    tags: List[str] = Field(default_factory=list)
    depends_on: List[str] = Field(default_factory=list)
    updated_at: str | None = None
    commit_on_complete: bool = True
    has_plan: bool = False


class RequirementsList(BaseModel):
    """List of requirements with metadata"""

    requirements: List[Requirement]


class RequirementContentResponse(BaseModel):
    content: str


class RequirementContentUpdate(BaseModel):
    """Request body for updating requirement content (spec)"""

    content: str = Field(..., description="Markdown content for the spec")


@router.patch("/{project_id}/requirements/{requirement_id}", response_model=Requirement)
async def update_requirement_metadata(
    project_id: str,
    requirement_id: str,
    update: RequirementMetadataUpdate,
    db: Database = Depends(get_db),
):
    """
    Update a single metadata field for a requirement.
    Allowed fields: status, priority, tags, depends_on, title
    """
    # Validate field
    allowed_fields = {"status", "priority", "tags", "depends_on", "title"}
    if update.field not in allowed_fields:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid field '{update.field}'. Allowed fields: {', '.join(allowed_fields)}",
        )

    # Validate values
    if update.field == "status":
        valid_statuses = {
            "draft",
            "planned",
            "in_progress",
            "blocked",
            "complete",
            "done",
        }
        if update.value not in valid_statuses:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid status '{update.value}'. Must be one of: {', '.join(valid_statuses)}",
            )

    if update.field == "priority":
        valid_priorities = {"low", "medium", "high", "critical"}
        if update.value not in valid_priorities:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid priority '{update.value}'. Must be one of: {', '.join(valid_priorities)}",
            )

    if update.field == "tags":
        if not isinstance(update.value, list):
            raise HTTPException(status_code=400, detail="tags must be an array")

    if update.field == "depends_on":
        if not isinstance(update.value, list):
            raise HTTPException(status_code=400, detail="depends_on must be an array")

    if update.field == "title":
        if not isinstance(update.value, str) or not update.value.strip():
            raise HTTPException(
                status_code=400, detail="title must be a non-empty string"
            )

    service = RequirementService(db)

    try:
        updated = await service.update_metadata(
            project_id, requirement_id, update.field, update.value
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Failed to update requirement metadata: {str(e)}"
        )

    if not updated:
        raise HTTPException(
            status_code=404,
            detail=f"Requirement {requirement_id} not found in project {project_id}",
        )

    return Requirement(**updated)


@router.get("/{project_id}/requirements", response_model=RequirementsList)
async def list_requirements(
    project_id: str,
    db: Database = Depends(get_db),
):
    """
    List all requirements for a project (database-backed).
    """
    service = RequirementService(db)
    requirements = await service.list_requirements(project_id)
    return RequirementsList(requirements=requirements)


@router.get(
    "/{project_id}/requirements/{requirement_id}/content",
    response_model=RequirementContentResponse,
)
async def get_requirement_content(
    project_id: str,
    requirement_id: str,
    db: Database = Depends(get_db),
):
    """
    Get spec content for a requirement from the database.
    """
    service = RequirementService(db)
    content = await service.get_content(project_id, requirement_id)
    if content is None:
        raise HTTPException(
            status_code=404,
            detail=f"Requirement {requirement_id} not found in project {project_id}",
        )
    return RequirementContentResponse(content=content)


@router.put(
    "/{project_id}/requirements/{requirement_id}/content",
    response_model=RequirementContentResponse,
)
async def update_requirement_content(
    project_id: str,
    requirement_id: str,
    update: RequirementContentUpdate,
    db: Database = Depends(get_db),
):
    """
    Update spec content for a requirement in the database.
    Creates a new version in requirement_versions history.
    """
    service = RequirementService(db)

    # Update content (will return False if requirement doesn't exist)
    success = await service.update_content(
        project_id=project_id,
        requirement_id_or_code=requirement_id,
        content=update.content,
        source="api",
    )

    if not success:
        raise HTTPException(
            status_code=404,
            detail=f"Requirement {requirement_id} not found in project {project_id}",
        )

    return RequirementContentResponse(content=update.content)
