"""
Felix Backend - Global Settings API
Handles global Felix settings that are project-independent.
Settings are stored in ~/.felix/config.json (Felix home directory).
"""

import logging
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel, Field
from typing import List, Optional
from pathlib import Path
import json
from databases import Database

import sys

sys.path.insert(0, str(Path(__file__).parent.parent))

# Set up logger
logger = logging.getLogger(__name__)

import storage
from auth import get_current_user
from database import get_db
from repositories import PostgresSettingsRepository

router = APIRouter(prefix="/api", tags=["settings"])


# --- Config Models (same as files.py for compatibility) ---


class ExecutorConfig(BaseModel):
    """Executor configuration"""

    mode: str = Field(default="local", description="Executor mode")
    max_iterations: int = Field(default=100, description="Maximum iterations per run")
    default_mode: str = Field(
        default="building", description="Default agent mode (planning or building)"
    )
    auto_transition: bool = Field(
        default=True, description="Auto-transition from planning to building"
    )


class AgentConfig(BaseModel):
    """Agent configuration"""

    agent_id: int = Field(
        default=0,
        description="ID of the active agent configuration",
    )


class PathsConfig(BaseModel):
    """Paths configuration"""

    specs: str = Field(default="specs", description="Specs directory path")
    agents: str = Field(default="AGENTS.md", description="AGENTS.md file path")
    runs: str = Field(default="runs", description="Runs directory path")


class BackpressureConfig(BaseModel):
    """Backpressure configuration"""

    enabled: bool = Field(default=True, description="Whether backpressure is enabled")
    commands: List[str] = Field(
        default_factory=list, description="Backpressure commands to run"
    )
    max_retries: Optional[int] = Field(
        default=3, description="Max retries for backpressure commands"
    )


class UIConfig(BaseModel):
    """UI configuration"""

    pass


class CopilotContextSourcesConfig(BaseModel):
    """Context sources configuration for copilot"""

    agents_md: bool = Field(default=True, description="Include AGENTS.md in context")
    learnings_md: bool = Field(
        default=True, description="Include LEARNINGS.md in context"
    )
    prompt_md: bool = Field(default=True, description="Include prompt.md in context")
    requirements: bool = Field(
        default=True, description="Include requirements in context"
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
    """Copilot configuration"""

    enabled: bool = Field(default=False, description="Whether copilot is enabled")
    provider: str = Field(
        default="openai", description="LLM provider: 'openai', 'anthropic', or 'custom'"
    )
    model: str = Field(default="gpt-4o", description="Model name to use")
    context_sources: CopilotContextSourcesConfig = Field(
        default_factory=CopilotContextSourcesConfig
    )
    features: CopilotFeaturesConfig = Field(default_factory=CopilotFeaturesConfig)


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
    warning: Optional[str] = Field(
        default=None,
        description="Warning message if config had issues",
    )


class ScopedConfigContent(BaseModel):
    """Config content scoped to org/user/project."""

    scope_type: str
    scope_id: str
    config: FelixConfig


class ConfigUpdate(BaseModel):
    """Request body for updating config"""

    config: FelixConfig = Field(..., description="Configuration object")


# --- Helper Functions ---


def get_global_config_path() -> Path:
    """Get the path to global Felix config (~/.felix/config.json)"""
    return storage.get_felix_home() / "config.json"


def load_global_config() -> tuple[FelixConfig, str | None]:
    """
    Load global Felix configuration from ~/.felix/config.json.

    Returns:
        A tuple of (FelixConfig, warning_message) where warning_message is None if no issues.
    """
    config_path = get_global_config_path()
    warning_message = None

    if not config_path.exists():
        # Return default config if file doesn't exist
        return FelixConfig(), None

    try:
        data = json.loads(config_path.read_text(encoding="utf-8-sig"))

        # Parse nested configuration objects
        executor_data = data.get("executor", {})
        agent_data = data.get("agent", {})
        paths_data = data.get("paths", {})
        backpressure_data = data.get("backpressure", {})
        ui_data = data.get("ui", {})
        copilot_data = data.get("copilot", None)

        # Handle agent config migration: detect legacy inline agent vs new agent_id format
        if agent_data:
            if "agent_id" in agent_data:
                # New format - use agent_id directly
                agent_config = AgentConfig(agent_id=agent_data["agent_id"])
            elif "name" in agent_data or "executable" in agent_data:
                # Legacy format - has inline agent definition, use agent_id: 0 (system default)
                agent_config = AgentConfig(agent_id=0)
            else:
                # Unknown format, default to agent_id: 0
                agent_config = AgentConfig()
        else:
            agent_config = AgentConfig()

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
            agent=agent_config,
            paths=PathsConfig(**paths_data) if paths_data else PathsConfig(),
            backpressure=(
                BackpressureConfig(**backpressure_data)
                if backpressure_data
                else BackpressureConfig()
            ),
            ui=UIConfig(**ui_data) if ui_data else UIConfig(),
            copilot=copilot_config,
        )

        return config, warning_message
    except json.JSONDecodeError as e:
        raise HTTPException(
            status_code=500, detail=f"Invalid JSON in config.json: {str(e)}"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to read config: {str(e)}")


def save_global_config(config: FelixConfig) -> None:
    """Save global Felix configuration to ~/.felix/config.json"""
    config_path = get_global_config_path()

    # Ensure the directory exists
    config_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        config_data = config.model_dump()
        config_path.write_text(json.dumps(config_data, indent=2), encoding="utf-8")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to write config: {str(e)}")


def _parse_scoped_config(payload: object) -> tuple[FelixConfig, Optional[str]]:
    warning_message = None
    if not payload:
        return FelixConfig(), None
    if isinstance(payload, str):
        try:
            payload = json.loads(payload)
        except json.JSONDecodeError as e:
            return FelixConfig(), f"Invalid settings JSON: {str(e)}"
    try:
        return FelixConfig(**payload), None
    except Exception as e:
        warning_message = f"Failed to parse settings, using defaults: {str(e)}"
        return FelixConfig(), warning_message


# --- Settings Endpoints ---


@router.get("/settings", response_model=ConfigContent)
async def get_global_settings():
    """
    Get global Felix settings (project-independent).

    Reads configuration from ~/.felix/config.json.
    Returns default values if the config file doesn't exist.
    """
    config, warning = load_global_config()
    return ConfigContent(
        config=config, path=str(get_global_config_path()), warning=warning
    )


@router.put("/settings", response_model=ConfigContent)
async def update_global_settings(request: ConfigUpdate):
    """
    Update global Felix settings (project-independent).

    Saves configuration to ~/.felix/config.json.

    Validates:
    - max_iterations must be a positive integer
    - default_mode must be 'planning' or 'building'
    - ui.theme must be 'dark', 'light', or 'system'
    """
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

    save_global_config(config)

    return ConfigContent(config=config, path=str(get_global_config_path()))


@router.get("/settings/org", response_model=ScopedConfigContent)
async def get_org_settings(
    user: dict = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    repo = PostgresSettingsRepository(db)
    record = await repo.get("org", str(user["org_id"]))
    config, warning = _parse_scoped_config(record["config"] if record else None)
    if warning:
        logger.warning("Org settings warning: %s", warning)
    return ScopedConfigContent(
        scope_type="org", scope_id=str(user["org_id"]), config=config
    )


@router.put("/settings/org", response_model=ScopedConfigContent)
async def update_org_settings(
    request: ConfigUpdate,
    user: dict = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    config = request.config
    if config.executor.max_iterations <= 0:
        raise HTTPException(
            status_code=400, detail="max_iterations must be a positive integer"
        )
    if config.executor.default_mode not in ("planning", "building"):
        raise HTTPException(
            status_code=400, detail="default_mode must be 'planning' or 'building'"
        )
    repo = PostgresSettingsRepository(db)
    await repo.upsert("org", str(user["org_id"]), config.model_dump())
    return ScopedConfigContent(
        scope_type="org", scope_id=str(user["org_id"]), config=config
    )


@router.get("/settings/user", response_model=ScopedConfigContent)
async def get_user_settings(
    user: dict = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    repo = PostgresSettingsRepository(db)
    record = await repo.get("user", str(user["user_id"]))
    config, warning = _parse_scoped_config(record["config"] if record else None)
    if warning:
        logger.warning("User settings warning: %s", warning)
    return ScopedConfigContent(
        scope_type="user", scope_id=str(user["user_id"]), config=config
    )


@router.put("/settings/user", response_model=ScopedConfigContent)
async def update_user_settings(
    request: ConfigUpdate,
    user: dict = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    config = request.config
    if config.executor.max_iterations <= 0:
        raise HTTPException(
            status_code=400, detail="max_iterations must be a positive integer"
        )
    if config.executor.default_mode not in ("planning", "building"):
        raise HTTPException(
            status_code=400, detail="default_mode must be 'planning' or 'building'"
        )
    repo = PostgresSettingsRepository(db)
    await repo.upsert("user", str(user["user_id"]), config.model_dump())
    return ScopedConfigContent(
        scope_type="user", scope_id=str(user["user_id"]), config=config
    )
