"""
Felix Backend - File Operations API
Handles reading and writing project files (specs, plan, requirements).
"""
from fastapi import APIRouter, HTTPException, Path as PathParam
from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field
import re
import json
import fnmatch
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


class RequirementsUpdate(BaseModel):
    """Request body for updating requirements.json"""
    requirements: List[Requirement] = Field(..., description="List of requirements")


class SpecCreate(BaseModel):
    """Request body for creating a new spec"""
    filename: str = Field(..., description="Filename for the spec (e.g., 'my-feature.md')")
    content: str = Field(..., description="Markdown content for the spec file")


class AgentsMdContent(BaseModel):
    """AGENTS.md content response"""
    content: str
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


def load_policies(project_path: Path) -> tuple[Dict[str, Any], Dict[str, Any]]:
    """
    Load allowlist and denylist policies from the project's felix/policies/ directory.
    
    Returns (allowlist, denylist) dictionaries. Returns empty dicts if files don't exist.
    """
    policies_dir = project_path / "felix" / "policies"
    
    allowlist = {}
    denylist = {}
    
    allowlist_path = policies_dir / "allowlist.json"
    if allowlist_path.exists():
        try:
            allowlist = json.loads(allowlist_path.read_text(encoding='utf-8'))
        except (json.JSONDecodeError, IOError):
            pass
    
    denylist_path = policies_dir / "denylist.json"
    if denylist_path.exists():
        try:
            denylist = json.loads(denylist_path.read_text(encoding='utf-8'))
        except (json.JSONDecodeError, IOError):
            pass
    
    return allowlist, denylist


def path_matches_pattern(file_path: str, pattern: str) -> bool:
    """
    Check if a file path matches a glob-like pattern.
    
    Supports patterns like:
    - "specs/**" - matches any file under specs/
    - "felix/requirements.json" - exact match
    - "*.md" - matches any .md file
    """
    # Normalize path separators to forward slashes
    file_path = file_path.replace('\\', '/')
    pattern = pattern.replace('\\', '/')
    
    # Handle ** for recursive matching
    if '**' in pattern:
        # Convert ** pattern to regex
        regex_pattern = pattern.replace('.', r'\.')
        regex_pattern = regex_pattern.replace('**', '.*')
        regex_pattern = regex_pattern.replace('*', '[^/]*')
        regex_pattern = f'^{regex_pattern}$'
        return bool(re.match(regex_pattern, file_path))
    else:
        # Use fnmatch for simple patterns
        return fnmatch.fnmatch(file_path, pattern)


def validate_path_against_policies(
    file_path: str, 
    project_path: Path,
    operation: str = "write"
) -> tuple[bool, Optional[str]]:
    """
    Validate a file path against the project's allowlist and denylist policies.
    
    Args:
        file_path: Relative path from project root (e.g., "specs/my-spec.md")
        project_path: Absolute path to the project root
        operation: "read" or "write" - write operations are more strictly validated
    
    Returns:
        (is_allowed, error_message) - (True, None) if allowed, (False, reason) if denied
    """
    allowlist, denylist = load_policies(project_path)
    
    # Normalize path
    file_path = file_path.replace('\\', '/')
    
    # Check restricted paths (from allowlist.json) - these are read-only or protected
    restricted_paths = allowlist.get("restricted_paths", [])
    for pattern in restricted_paths:
        if path_matches_pattern(file_path, pattern):
            return False, f"Path is restricted by policy: {pattern}"
    
    # For write operations, check that path is in allowed_file_patterns
    if operation == "write":
        allowed_patterns = allowlist.get("allowed_file_patterns", [])
        
        # If no allowlist patterns defined, allow by default (backwards compatibility)
        if not allowed_patterns:
            return True, None
        
        # Check if path matches any allowed pattern
        for pattern in allowed_patterns:
            if path_matches_pattern(file_path, pattern):
                return True, None
        
        return False, f"Path not in allowed file patterns. Allowed: {allowed_patterns}"
    
    # Read operations are generally allowed if not restricted
    return True, None


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


@router.put("/{project_id}/requirements", response_model=RequirementsContent)
async def update_requirements(
    request: RequirementsUpdate,
    project_id: str = PathParam(..., description="Project ID")
):
    """
    Update the project's felix/requirements.json.
    """
    import json
    
    project_path = get_project_path(project_id)
    req_path = project_path / "felix" / "requirements.json"
    
    # Ensure felix directory exists
    felix_dir = project_path / "felix"
    if not felix_dir.exists():
        raise HTTPException(status_code=400, detail="Project has no felix/ directory")
    
    try:
        # Convert requirements to dict format for JSON
        requirements_data = {
            "requirements": [r.model_dump() for r in request.requirements]
        }
        
        req_path.write_text(json.dumps(requirements_data, indent=2), encoding='utf-8')
        
        return RequirementsContent(
            requirements=request.requirements,
            path=str(req_path.relative_to(project_path))
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to write requirements: {str(e)}")


# --- Create New Spec Endpoint ---

@router.post("/{project_id}/specs", response_model=SpecContent, status_code=201)
async def create_spec(
    request: SpecCreate,
    project_id: str = PathParam(..., description="Project ID")
):
    """
    Create a new spec file.
    
    Returns 409 Conflict if the file already exists.
    """
    if not validate_filename(request.filename):
        raise HTTPException(status_code=400, detail=f"Invalid filename: {request.filename}")
    
    project_path = get_project_path(project_id)
    specs_dir = project_path / "specs"
    
    # Ensure specs directory exists
    if not specs_dir.exists():
        raise HTTPException(status_code=400, detail="Project has no specs/ directory")
    
    spec_path = specs_dir / request.filename
    
    # Check if file already exists
    if spec_path.exists():
        raise HTTPException(status_code=409, detail=f"Spec file already exists: {request.filename}")
    
    try:
        spec_path.write_text(request.content, encoding='utf-8')
        return SpecContent(filename=request.filename, content=request.content)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to create spec: {str(e)}")


# --- AGENTS.md Endpoint ---

@router.get("/{project_id}/agents-md", response_model=AgentsMdContent)
async def read_agents_md(project_id: str = PathParam(..., description="Project ID")):
    """
    Read the project's AGENTS.md operations guide.
    """
    project_path = get_project_path(project_id)
    agents_path = project_path / "AGENTS.md"
    
    if not agents_path.exists():
        raise HTTPException(status_code=404, detail="AGENTS.md not found")
    
    try:
        content = agents_path.read_text(encoding='utf-8')
        return AgentsMdContent(
            content=content,
            path="AGENTS.md"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to read AGENTS.md: {str(e)}")
