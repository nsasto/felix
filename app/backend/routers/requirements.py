"""
Felix Backend - Requirements API
Handles requirement metadata updates.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Any, List
import json
from pathlib import Path

router = APIRouter(prefix="/api/projects", tags=["requirements"])


class RequirementMetadataUpdate(BaseModel):
    field: str
    value: Any


class Requirement(BaseModel):
    id: str
    title: str
    spec_path: str
    status: str
    priority: str
    labels: List[str]
    depends_on: List[str]
    updated_at: str
    commit_on_complete: bool = True
    has_plan: bool = False


@router.patch("/{project_id}/requirements/{requirement_id}", response_model=Requirement)
async def update_requirement_metadata(
    project_id: str, requirement_id: str, update: RequirementMetadataUpdate
):
    """
    Update a single metadata field for a requirement.
    Allowed fields: status, priority, labels, depends_on
    """
    # Validate field
    allowed_fields = {"status", "priority", "labels", "depends_on"}
    if update.field not in allowed_fields:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid field '{update.field}'. Allowed fields: {', '.join(allowed_fields)}",
        )

    # Validate values
    if update.field == "status":
        valid_statuses = {"planned", "in_progress", "blocked", "complete", "done"}
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

    if update.field == "labels":
        if not isinstance(update.value, list):
            raise HTTPException(status_code=400, detail="labels must be an array")

    if update.field == "depends_on":
        if not isinstance(update.value, list):
            raise HTTPException(status_code=400, detail="depends_on must be an array")

    # TODO: When moving to database, this will use Supabase
    # For now, update the requirements.json file
    try:
        # Find project directory (this is a simplified approach for now)
        # In production, use proper project storage lookup
        from datetime import date
        import storage

        # Get project details to find the path
        project_details = storage.get_project_details(project_id)
        if not project_details:
            raise HTTPException(
                status_code=404, detail=f"Project not found: {project_id}"
            )

        project_path = Path(project_details["path"])
        requirements_file = project_path / ".felix" / "requirements.json"

        if not requirements_file.exists():
            raise HTTPException(status_code=404, detail="requirements.json not found")

        # Read current requirements
        with open(requirements_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        # Find and update the requirement
        requirement_found = False
        for req in data.get("requirements", []):
            if req["id"] == requirement_id:
                requirement_found = True
                req[update.field] = update.value
                req["updated_at"] = date.today().isoformat()

                # Return updated requirement
                updated_requirement = Requirement(**req)
                break

        if not requirement_found:
            raise HTTPException(
                status_code=404,
                detail=f"Requirement {requirement_id} not found in project {project_id}",
            )

        # Write back to file
        with open(requirements_file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=4, ensure_ascii=False)

        return updated_requirement

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Failed to update requirement metadata: {str(e)}"
        )
