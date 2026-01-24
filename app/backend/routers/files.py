"""
Felix Backend - File Operations API
Handles reading and writing project files (specs, plan, requirements).
"""
from fastapi import APIRouter, HTTPException, Path as PathParam
from typing import List, Optional
from pydantic import BaseModel, Field
import re
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

import storage

router = APIRouter(prefix="/api/projects", tags=["files"])


# --- Request/Response Models ---

class SpecFile(BaseModel):
    """Spec file metadata"""
    filename: str
    path: str
    size: int
    modified_at: str


class SpecContent(BaseModel):
    """Spec file content response"""
    filename: str
    content: str


class SpecUpdate(BaseModel):
    """Request body for updating a spec"""
    content: str = Field(..., description="Markdown content for the spec file")


class PlanContent(BaseModel):
    """Implementation plan content response"""
    content: str
    path: str


class PlanUpdate(BaseModel):
    """Request body for updating the plan"""
    content: str = Field(..., description="Markdown content for IMPLEMENTATION_PLAN.md")


class Requirement(BaseModel):
    """Single requirement from requirements.json"""
    id: str
    title: str
    spec_path: Optional[str] = None
    status: str
    priority: Optional[str] = None
    labels: List[str] = Field(default_factory=list)
    depends_on: List[str] = Field(default_factory=list)
    updated_at: Optional[str] = None


class RequirementsContent(BaseModel):
    """Requirements.json content response"""
    requirements: List[Requirement]
    path: str


# --- Security Helpers ---

# Allowed filename pattern: alphanumeric, hyphens, underscores, dots
SAFE_FILENAME_PATTERN = re.compile(r'^[a-zA-Z0-9_\-]+\.md$')

# Files that can be read/written
ALLOWED_SPEC_EXTENSIONS = {'.md'}


def validate_filename(filename: str) -> bool:
    """Validate that a filename is safe (no path traversal, valid chars)"""
    if not filename:
        return False
    # Block path traversal
    if '..' in filename or '/' in filename or '\\' in filename:
        return False
    # Must match safe pattern
    return bool(SAFE_FILENAME_PATTERN.match(filename))


def get_project_path(project_id: str) -> Path:
    """Get validated project path by ID"""
    project = storage.get_project_by_id(project_id)
    if not project:
        raise HTTPException(status_code=404, detail=f"Project not found: {project_id}")
    
    project_path = Path(project.path)
    if not project_path.exists():
        raise HTTPException(status_code=404, detail=f"Project directory no longer exists: {project.path}")
    
    return project_path


# --- Specs Endpoints ---

@router.get("/{project_id}/specs", response_model=List[SpecFile])
async def list_specs(project_id: str = PathParam(..., description="Project ID")):
    """
    List all spec files in the project's specs/ directory.
    """
    project_path = get_project_path(project_id)
    specs_dir = project_path / "specs"
    
    if not specs_dir.exists():
        return []
    
    specs = []
    for file_path in sorted(specs_dir.glob("*.md")):
        if file_path.is_file():
            stat = file_path.stat()
            specs.append(SpecFile(
                filename=file_path.name,
                path=str(file_path.relative_to(project_path)),
                size=stat.st_size,
                modified_at=stat.st_mtime.__str__()
            ))
    
    return specs


@router.get("/{project_id}/specs/{filename}", response_model=SpecContent)
async def read_spec(
    project_id: str = PathParam(..., description="Project ID"),
    filename: str = PathParam(..., description="Spec filename (e.g., 'initial-setup.md')")
):
    """
    Read content of a specific spec file.
    """
    if not validate_filename(filename):
        raise HTTPException(status_code=400, detail=f"Invalid filename: {filename}")
    
    project_path = get_project_path(project_id)
    spec_path = project_path / "specs" / filename
    
    if not spec_path.exists():
        raise HTTPException(status_code=404, detail=f"Spec file not found: {filename}")
    
    if not spec_path.is_file():
        raise HTTPException(status_code=400, detail=f"Not a file: {filename}")
    
    try:
        content = spec_path.read_text(encoding='utf-8')
        return SpecContent(filename=filename, content=content)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to read spec: {str(e)}")


@router.put("/{project_id}/specs/{filename}", response_model=SpecContent)
async def update_spec(
    request: SpecUpdate,
    project_id: str = PathParam(..., description="Project ID"),
    filename: str = PathParam(..., description="Spec filename (e.g., 'initial-setup.md')")
):
    """
    Update or create a spec file.
    
    If the file doesn't exist, it will be created.
    """
    if not validate_filename(filename):
        raise HTTPException(status_code=400, detail=f"Invalid filename: {filename}")
    
    project_path = get_project_path(project_id)
    specs_dir = project_path / "specs"
    
    # Ensure specs directory exists
    if not specs_dir.exists():
        raise HTTPException(status_code=400, detail="Project has no specs/ directory")
    
    spec_path = specs_dir / filename
    
    try:
        spec_path.write_text(request.content, encoding='utf-8')
        return SpecContent(filename=filename, content=request.content)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to write spec: {str(e)}")


# --- Plan Endpoints ---

@router.get("/{project_id}/plan", response_model=PlanContent)
async def read_plan(project_id: str = PathParam(..., description="Project ID")):
    """
    Read the project's IMPLEMENTATION_PLAN.md.
    """
    project_path = get_project_path(project_id)
    plan_path = project_path / "IMPLEMENTATION_PLAN.md"
    
    if not plan_path.exists():
        raise HTTPException(status_code=404, detail="IMPLEMENTATION_PLAN.md not found")
    
    try:
        content = plan_path.read_text(encoding='utf-8')
        return PlanContent(
            content=content,
            path=str(plan_path.relative_to(project_path))
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to read plan: {str(e)}")


@router.put("/{project_id}/plan", response_model=PlanContent)
async def update_plan(
    request: PlanUpdate,
    project_id: str = PathParam(..., description="Project ID")
):
    """
    Update the project's IMPLEMENTATION_PLAN.md.
    """
    project_path = get_project_path(project_id)
    plan_path = project_path / "IMPLEMENTATION_PLAN.md"
    
    try:
        plan_path.write_text(request.content, encoding='utf-8')
        return PlanContent(
            content=request.content,
            path=str(plan_path.relative_to(project_path))
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to write plan: {str(e)}")


# --- Requirements Endpoints ---

@router.get("/{project_id}/requirements", response_model=RequirementsContent)
async def read_requirements(project_id: str = PathParam(..., description="Project ID")):
    """
    Read the project's felix/requirements.json.
    """
    project_path = get_project_path(project_id)
    req_path = project_path / "felix" / "requirements.json"
    
    if not req_path.exists():
        raise HTTPException(status_code=404, detail="felix/requirements.json not found")
    
    try:
        import json
        data = json.loads(req_path.read_text(encoding='utf-8'))
        
        requirements = [
            Requirement(**r) for r in data.get("requirements", [])
        ]
        
        return RequirementsContent(
            requirements=requirements,
            path=str(req_path.relative_to(project_path))
        )
    except json.JSONDecodeError as e:
        raise HTTPException(status_code=500, detail=f"Invalid JSON in requirements.json: {str(e)}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to read requirements: {str(e)}")
