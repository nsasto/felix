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

    filename: str = Field(
        ..., description="Filename for the spec (e.g., 'my-feature.md')"
    )
    content: str = Field(..., description="Markdown content for the spec file")


class AgentsMdContent(BaseModel):
    """AGENTS.md content response"""

    content: str
    path: str


# --- Config Models ---


class ExecutorConfig(BaseModel):
    """Executor configuration from felix/config.json"""

    mode: str = Field(default="local", description="Executor mode")
    max_iterations: int = Field(default=100, description="Maximum iterations per run")
    default_mode: str = Field(
        default="building", description="Default agent mode (planning or building)"
    )
    auto_transition: bool = Field(
        default=True, description="Auto-transition from planning to building"
    )


class AgentConfig(BaseModel):
    """Agent configuration from felix/config.json"""

    name: str = Field(
        default="felix-primary", description="Unique agent name identifier"
    )
    executable: str = Field(default="droid", description="Agent executable name")
    args: List[str] = Field(
        default_factory=lambda: ["exec", "--skip-permissions-unsafe"],
        description="Agent arguments",
    )
    working_directory: str = Field(
        default=".", description="Working directory for agent"
    )
    environment: Dict[str, str] = Field(
        default_factory=dict, description="Environment variables"
    )


class PathsConfig(BaseModel):
    """Paths configuration from felix/config.json"""

    specs: str = Field(default="specs", description="Specs directory path")
    agents: str = Field(default="AGENTS.md", description="AGENTS.md file path")
    runs: str = Field(default="runs", description="Runs directory path")


class BackpressureConfig(BaseModel):
    """Backpressure configuration from felix/config.json"""

    enabled: bool = Field(default=True, description="Whether backpressure is enabled")
    commands: List[str] = Field(
        default_factory=list, description="Backpressure commands to run"
    )


class UIConfig(BaseModel):
    """UI configuration from felix/config.json"""

    pass


class CopilotContextSourcesConfig(BaseModel):
    """Context sources configuration for copilot"""

    agents_md: bool = Field(default=True, description="Include AGENTS.md in context")
    learnings_md: bool = Field(
        default=True, description="Include LEARNINGS.md in context"
    )
    prompt_md: bool = Field(default=True, description="Include prompt.md in context")
    requirements: bool = Field(
        default=True, description="Include requirements.json in context"
    )
    other_specs: bool = Field(
        default=True, description="Include other spec files in context"
    )


class CopilotFeaturesConfig(BaseModel):
    """Feature toggles for copilot"""

    streaming: bool = Field(default=True, description="Enable streaming responses")
    auto_suggest: bool = Field(default=True, description="Auto-suggest spec titles")
    context_aware: bool = Field(
        default=True, description="Use project context in responses"
    )


class CopilotConfig(BaseModel):
    """Copilot configuration from felix/config.json"""

    enabled: bool = Field(default=False, description="Whether copilot is enabled")
    provider: str = Field(
        default="openai", description="LLM provider: 'openai', 'anthropic', or 'custom'"
    )
    model: str = Field(default="gpt-4o", description="Model name to use")
    context_sources: CopilotContextSourcesConfig = Field(
        default_factory=CopilotContextSourcesConfig
    )
    features: CopilotFeaturesConfig = Field(default_factory=CopilotFeaturesConfig)


class AgentEntry(BaseModel):
    """Agent entry for felix/agents.json registry"""

    pid: int = Field(..., description="Process ID of the agent")
    hostname: str = Field(..., description="Hostname where agent is running")
    status: str = Field(
        default="active", description="Agent status: active, inactive, stopped"
    )
    current_run_id: Optional[str] = Field(
        None, description="Current requirement ID being worked on"
    )
    started_at: Optional[str] = Field(
        None, description="ISO timestamp when agent started"
    )
    last_heartbeat: Optional[str] = Field(
        None, description="ISO timestamp of last heartbeat"
    )
    stopped_at: Optional[str] = Field(
        None, description="ISO timestamp when agent was stopped"
    )


class FelixConfig(BaseModel):
    """Full felix/config.json configuration"""

    version: str = Field(default="0.1.0", description="Config version")
    executor: ExecutorConfig = Field(default_factory=ExecutorConfig)
    agent: AgentConfig = Field(default_factory=AgentConfig)
    paths: PathsConfig = Field(default_factory=PathsConfig)
    backpressure: BackpressureConfig = Field(default_factory=BackpressureConfig)
    ui: UIConfig = Field(default_factory=UIConfig)
    copilot: Optional[CopilotConfig] = Field(
        default=None, description="Copilot configuration"
    )


class ConfigContent(BaseModel):
    """Config file content response"""

    config: FelixConfig
    path: str


class ConfigUpdate(BaseModel):
    """Request body for updating config"""

    config: FelixConfig = Field(..., description="Configuration object")


# --- Security Helpers ---

# Allowed filename pattern: alphanumeric, hyphens, underscores, dots
SAFE_FILENAME_PATTERN = re.compile(r"^[a-zA-Z0-9_\-]+\.md$")

# Files that can be read/written
ALLOWED_SPEC_EXTENSIONS = {".md"}


def validate_filename(filename: str) -> bool:
    """Validate that a filename is safe (no path traversal, valid chars)"""
    if not filename:
        return False
    # Block path traversal
    if ".." in filename or "/" in filename or "\\" in filename:
        return False
    # Must match safe pattern
    return bool(SAFE_FILENAME_PATTERN.match(filename))


def load_policies(project_path: Path) -> tuple[Dict[str, Any], Dict[str, Any]]:
    """
    Load allowlist and denylist policies from the project's .felix/policies/ directory.

    Returns (allowlist, denylist) dictionaries. Returns empty dicts if files don't exist.
    """
    policies_dir = project_path / ".felix" / "policies"

    allowlist = {}
    denylist = {}

    allowlist_path = policies_dir / "allowlist.json"
    if allowlist_path.exists():
        try:
            allowlist = json.loads(allowlist_path.read_text(encoding="utf-8-sig"))
        except (json.JSONDecodeError, IOError):
            pass

    denylist_path = policies_dir / "denylist.json"
    if denylist_path.exists():
        try:
            denylist = json.loads(denylist_path.read_text(encoding="utf-8-sig"))
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
    file_path = file_path.replace("\\", "/")
    pattern = pattern.replace("\\", "/")

    # Handle ** for recursive matching
    if "**" in pattern:
        # Convert ** pattern to regex
        regex_pattern = pattern.replace(".", r"\.")
        regex_pattern = regex_pattern.replace("**", ".*")
        regex_pattern = regex_pattern.replace("*", "[^/]*")
        regex_pattern = f"^{regex_pattern}$"
        return bool(re.match(regex_pattern, file_path))
    else:
        # Use fnmatch for simple patterns
        return fnmatch.fnmatch(file_path, pattern)


def validate_path_against_policies(
    file_path: str, project_path: Path, operation: str = "write"
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
    file_path = file_path.replace("\\", "/")

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
        raise HTTPException(
            status_code=404,
            detail=f"Project directory no longer exists: {project.path}",
        )

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
            specs.append(
                SpecFile(
                    filename=file_path.name,
                    path=str(file_path.relative_to(project_path)),
                    size=stat.st_size,
                    modified_at=stat.st_mtime.__str__(),
                )
            )

    return specs


@router.get("/{project_id}/specs/{filename}", response_model=SpecContent)
async def read_spec(
    project_id: str = PathParam(..., description="Project ID"),
    filename: str = PathParam(
        ..., description="Spec filename (e.g., 'S-0001-felix-agent-executor.md')"
    ),
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
        content = spec_path.read_text(encoding="utf-8")
        return SpecContent(filename=filename, content=content)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to read spec: {str(e)}")


@router.put("/{project_id}/specs/{filename}", response_model=SpecContent)
async def update_spec(
    request: SpecUpdate,
    project_id: str = PathParam(..., description="Project ID"),
    filename: str = PathParam(
        ..., description="Spec filename (e.g., 'S-0001-felix-agent-executor.md')"
    ),
):
    """
    Update or create a spec file.

    If the file doesn't exist, it will be created.
    Validates path against project policies (allowlist/denylist).
    """
    if not validate_filename(filename):
        raise HTTPException(status_code=400, detail=f"Invalid filename: {filename}")

    project_path = get_project_path(project_id)
    specs_dir = project_path / "specs"

    # Ensure specs directory exists
    if not specs_dir.exists():
        raise HTTPException(status_code=400, detail="Project has no specs/ directory")

    # Validate path against policies
    relative_path = f"specs/{filename}"
    is_allowed, error_msg = validate_path_against_policies(
        relative_path, project_path, operation="write"
    )
    if not is_allowed:
        raise HTTPException(status_code=400, detail=f"Policy violation: {error_msg}")

    spec_path = specs_dir / filename

    try:
        spec_path.write_text(request.content, encoding="utf-8")
        return SpecContent(filename=filename, content=request.content)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to write spec: {str(e)}")


# --- Requirements Endpoints ---


@router.get("/{project_id}/requirements", response_model=RequirementsContent)
async def read_requirements(project_id: str = PathParam(..., description="Project ID")):
    """
    Read the project's requirements.

    NOTE: Stubbed for Phase 0 database migration (S-0032).
    Returns empty requirements list until database-driven state management is implemented.
    """
    # Validate project exists (preserves existing behavior for 404 on invalid project)
    get_project_path(project_id)

    return RequirementsContent(requirements=[], path=".felix/requirements.json")


# --- README Endpoint ---


@router.get("/{project_id}/files/README.md")
async def read_readme(project_id: str = PathParam(..., description="Project ID")):
    """
    Read the project's README.md file from the root directory.
    """
    project_path = get_project_path(project_id)
    readme_path = project_path / "README.md"

    if not readme_path.exists():
        raise HTTPException(
            status_code=404, detail="README.md not found in project root"
        )

    try:
        content = readme_path.read_text(encoding="utf-8")
        return {"content": content, "path": "README.md"}
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Failed to read README.md: {str(e)}"
        )


# --- Requirements Endpoints ---


@router.put("/{project_id}/requirements", response_model=RequirementsContent)
async def update_requirements(
    request: RequirementsUpdate,
    project_id: str = PathParam(..., description="Project ID"),
):
    """
    Update the project's requirements.

    NOTE: Stubbed for Phase 0 database migration (S-0032).
    Returns 501 Not Implemented until database-driven state management is implemented.
    """
    # Validate project exists (preserves existing behavior for 404 on invalid project)
    get_project_path(project_id)

    raise HTTPException(
        status_code=501,
        detail="Requirements update not implemented. Database migration pending (S-0032).",
    )


# --- Create New Spec Endpoint ---


@router.post("/{project_id}/specs", response_model=SpecContent, status_code=201)
async def create_spec(
    request: SpecCreate, project_id: str = PathParam(..., description="Project ID")
):
    """
    Create a new spec file.

    NOTE: Updated for Phase 0 database migration (S-0032).
    requirements.json update logic removed - spec file creation preserved.

    Returns 409 Conflict if the file already exists.
    Validates path against project policies (allowlist/denylist).
    """
    if not validate_filename(request.filename):
        raise HTTPException(
            status_code=400, detail=f"Invalid filename: {request.filename}"
        )

    project_path = get_project_path(project_id)
    specs_dir = project_path / "specs"

    # Ensure specs directory exists
    if not specs_dir.exists():
        raise HTTPException(status_code=400, detail="Project has no specs/ directory")

    # Validate path against policies
    relative_path = f"specs/{request.filename}"
    is_allowed, error_msg = validate_path_against_policies(
        relative_path, project_path, operation="write"
    )
    if not is_allowed:
        raise HTTPException(status_code=400, detail=f"Policy violation: {error_msg}")

    spec_path = specs_dir / request.filename

    # Check if file already exists
    if spec_path.exists():
        raise HTTPException(
            status_code=409, detail=f"Spec file already exists: {request.filename}"
        )

    try:
        # Write the spec file
        spec_path.write_text(request.content, encoding="utf-8")

        # NOTE: requirements.json update removed for Phase 0 database migration (S-0032)
        # Requirement registration will be handled by database in future phases

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
        content = agents_path.read_text(encoding="utf-8")
        return AgentsMdContent(content=content, path="AGENTS.md")
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Failed to read AGENTS.md: {str(e)}"
        )


# --- Config Endpoints ---


@router.get("/{project_id}/config", response_model=ConfigContent)
async def read_config(project_id: str = PathParam(..., description="Project ID")):
    """
    Read the project's felix/config.json configuration.

    Returns the configuration with all sections (executor, agent, paths, backpressure).
    If the config file doesn't exist, returns default values.
    """
    project_path = get_project_path(project_id)
    config_path = project_path / ".felix" / "config.json"

    if not config_path.exists():
        # Return default config if file doesn't exist
        return ConfigContent(config=FelixConfig(), path=".felix/config.json")

    try:
        data = json.loads(config_path.read_text(encoding="utf-8-sig"))

        # Parse nested configuration objects
        executor_data = data.get("executor", {})
        agent_data = data.get("agent", {})
        paths_data = data.get("paths", {})
        backpressure_data = data.get("backpressure", {})
        ui_data = data.get("ui", {})
        copilot_data = data.get("copilot", None)

        # Parse copilot config if present
        copilot_config = None
        if copilot_data:
            context_sources_data = copilot_data.get("context_sources", {})
            features_data = copilot_data.get("features", {})
            copilot_config = CopilotConfig(
                enabled=copilot_data.get("enabled", False),
                provider=copilot_data.get("provider", "openai"),
                model=copilot_data.get("model", "gpt-4o"),
                context_sources=(
                    CopilotContextSourcesConfig(**context_sources_data)
                    if context_sources_data
                    else CopilotContextSourcesConfig()
                ),
                features=(
                    CopilotFeaturesConfig(**features_data)
                    if features_data
                    else CopilotFeaturesConfig()
                ),
            )

        config = FelixConfig(
            version=data.get("version", "0.1.0"),
            executor=(
                ExecutorConfig(**executor_data) if executor_data else ExecutorConfig()
            ),
            agent=AgentConfig(**agent_data) if agent_data else AgentConfig(),
            paths=PathsConfig(**paths_data) if paths_data else PathsConfig(),
            backpressure=(
                BackpressureConfig(**backpressure_data)
                if backpressure_data
                else BackpressureConfig()
            ),
            ui=UIConfig(**ui_data) if ui_data else UIConfig(),
            copilot=copilot_config,
        )

        return ConfigContent(config=config, path=".felix/config.json")
    except json.JSONDecodeError as e:
        raise HTTPException(
            status_code=500, detail=f"Invalid JSON in config.json: {str(e)}"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to read config: {str(e)}")


@router.put("/{project_id}/config", response_model=ConfigContent)
async def update_config(
    request: ConfigUpdate, project_id: str = PathParam(..., description="Project ID")
):
    """
    Update the project's felix/config.json configuration.

    Note: This endpoint bypasses the normal policy validation since config.json
    is typically marked as restricted in allowlist.json. The UI needs to be able
    to update configuration settings.

    Validates:
    - max_iterations must be a positive integer
    - default_mode must be 'planning' or 'building'
    """
    project_path = get_project_path(project_id)
    config_path = project_path / ".felix" / "config.json"

    # Ensure .felix directory exists
    felix_dir = project_path / ".felix"
    if not felix_dir.exists():
        raise HTTPException(status_code=400, detail="Project has no .felix/ directory")

    # Validate config values
    config = request.config

    # Validate max_iterations is positive
    if config.executor.max_iterations <= 0:
        raise HTTPException(
            status_code=400, detail="max_iterations must be a positive integer"
        )

    # Validate default_mode
    if config.executor.default_mode not in ("planning", "building"):
        raise HTTPException(
            status_code=400, detail="default_mode must be 'planning' or 'building'"
        )

    try:
        # Convert to dict for JSON serialization
        config_data = config.model_dump()

        config_path.write_text(json.dumps(config_data, indent=2), encoding="utf-8")

        return ConfigContent(config=config, path=".felix/config.json")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to write config: {str(e)}")


# --- Requirement Status Endpoints (for S-0006: Spec Edit Safety) ---


class RequirementStatusResponse(BaseModel):
    """Response for requirement status check"""

    id: str
    status: str
    title: str
    has_plan: bool
    plan_path: Optional[str] = None
    plan_modified_at: Optional[str] = None
    spec_modified_at: Optional[str] = None


class RequirementStatusUpdate(BaseModel):
    """Request body for updating requirement status"""

    status: str = Field(
        ...,
        description="New status: draft, planned, in_progress, complete, blocked, done",
    )


class PlanInfo(BaseModel):
    """Information about a requirement's plan"""

    requirement_id: str
    exists: bool
    plan_path: Optional[str] = None
    run_id: Optional[str] = None
    modified_at: Optional[str] = None
    content_preview: Optional[str] = None


class PlanDeleteResponse(BaseModel):
    """Response for plan deletion"""

    message: str
    requirement_id: str
    deleted_path: Optional[str] = None


def find_plan_for_requirement(
    project_path: Path, requirement_id: str
) -> Optional[tuple[Path, str]]:
    """
    Find the most recent plan file for a requirement.

    Plans are stored in runs/<run-id>/plan-<requirement-id>.md
    Returns (plan_path, run_id) or None if not found.
    """
    runs_dir = project_path / "runs"
    if not runs_dir.exists():
        return None

    # Find all plan files for this requirement across all runs
    plan_files: list[tuple[Path, str]] = []
    for run_dir in runs_dir.iterdir():
        if run_dir.is_dir():
            plan_file = run_dir / f"plan-{requirement_id}.md"
            if plan_file.exists():
                plan_files.append((plan_file, run_dir.name))

    if not plan_files:
        return None

    # Sort by run_id (which is a timestamp) and return the most recent
    plan_files.sort(key=lambda x: x[1], reverse=True)
    return plan_files[0]


@router.get(
    "/{project_id}/requirements/{requirement_id}/status",
    response_model=RequirementStatusResponse,
)
async def get_requirement_status(
    project_id: str = PathParam(..., description="Project ID"),
    requirement_id: str = PathParam(..., description="Requirement ID (e.g., 'S-0006')"),
):
    """
    Get the status of a specific requirement.

    NOTE: Stubbed for Phase 0 database migration (S-0032).
    Returns 501 Not Implemented until database-driven state management is implemented.
    """
    # Validate project exists (preserves existing behavior for 404 on invalid project)
    get_project_path(project_id)

    raise HTTPException(
        status_code=501,
        detail="Requirement status retrieval not implemented. Database migration pending (S-0032).",
    )


@router.put(
    "/{project_id}/requirements/{requirement_id}/status",
    response_model=RequirementStatusResponse,
)
async def update_requirement_status(
    request: RequirementStatusUpdate,
    project_id: str = PathParam(..., description="Project ID"),
    requirement_id: str = PathParam(..., description="Requirement ID (e.g., 'S-0006')"),
):
    """
    Update the status of a specific requirement.

    NOTE: Stubbed for Phase 0 database migration (S-0032).
    Returns 501 Not Implemented until database-driven state management is implemented.
    """
    # Validate project exists (preserves existing behavior for 404 on invalid project)
    get_project_path(project_id)

    raise HTTPException(
        status_code=501,
        detail="Requirement status update not implemented. Database migration pending (S-0032).",
    )


@router.get("/{project_id}/plans/{requirement_id}", response_model=PlanInfo)
async def get_plan_info(
    project_id: str = PathParam(..., description="Project ID"),
    requirement_id: str = PathParam(..., description="Requirement ID (e.g., 'S-0006')"),
):
    """
    Get information about a requirement's plan, including whether it exists
    and its metadata.
    """
    project_path = get_project_path(project_id)

    plan_info = find_plan_for_requirement(project_path, requirement_id)

    if not plan_info:
        return PlanInfo(requirement_id=requirement_id, exists=False)

    plan_file, run_id = plan_info

    # Read first 500 chars of content as preview
    content_preview = None
    try:
        content = plan_file.read_text(encoding="utf-8")
        content_preview = content[:500] + ("..." if len(content) > 500 else "")
    except Exception:
        pass

    return PlanInfo(
        requirement_id=requirement_id,
        exists=True,
        plan_path=str(plan_file.relative_to(project_path)),
        run_id=run_id,
        modified_at=str(plan_file.stat().st_mtime),
        content_preview=content_preview,
    )


@router.delete(
    "/{project_id}/plans/{requirement_id}", response_model=PlanDeleteResponse
)
async def delete_plan(
    project_id: str = PathParam(..., description="Project ID"),
    requirement_id: str = PathParam(..., description="Requirement ID (e.g., 'S-0006')"),
):
    """
    Delete all plan files for a specific requirement.

    This is used when acceptance criteria change to invalidate stale plans,
    or when user manually requests a plan reset.

    Deletes plan-<requirement-id>.md from all run directories.
    """
    project_path = get_project_path(project_id)
    runs_dir = project_path / "runs"

    if not runs_dir.exists():
        return PlanDeleteResponse(
            message="No plans found (runs directory does not exist)",
            requirement_id=requirement_id,
        )

    deleted_paths = []
    for run_dir in runs_dir.iterdir():
        if run_dir.is_dir():
            plan_file = run_dir / f"plan-{requirement_id}.md"
            if plan_file.exists():
                try:
                    plan_file.unlink()
                    deleted_paths.append(str(plan_file.relative_to(project_path)))
                except Exception as e:
                    raise HTTPException(
                        status_code=500,
                        detail=f"Failed to delete plan file {plan_file}: {str(e)}",
                    )

    if not deleted_paths:
        return PlanDeleteResponse(
            message="No plan files found for this requirement",
            requirement_id=requirement_id,
        )

    return PlanDeleteResponse(
        message=f"Deleted {len(deleted_paths)} plan file(s)",
        requirement_id=requirement_id,
        deleted_path=deleted_paths[0] if deleted_paths else None,
    )
