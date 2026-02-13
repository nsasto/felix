"""
Felix Backend - Requirements API
Handles requirement metadata updates.
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Any, List

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
    spec_path: str
    status: str
    priority: str
    tags: List[str]
    depends_on: List[str]
    updated_at: str
    commit_on_complete: bool = True
    has_plan: bool = False


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
