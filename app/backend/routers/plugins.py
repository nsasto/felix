"""
Felix Backend - Plugin Management API
Provides REST endpoints for managing plugins
"""

import json
from pathlib import Path
from typing import List, Optional
from datetime import datetime

from fastapi import APIRouter, HTTPException, Depends
from databases import Database
from pydantic import BaseModel

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from database import get_db
from services.projects import get_project_path as get_db_project_path


router = APIRouter(prefix="/plugins", tags=["plugins"])


async def get_project_path(db: Database, project_id: str) -> Path:
    try:
        return await get_db_project_path(db, project_id)
    except LookupError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))


class Plugin(BaseModel):
    """Plugin information"""
    name: str
    version: str
    api_version: str
    description: Optional[str] = None
    author: Optional[str] = None
    permissions: List[str] = []
    hooks: List[str] = []
    requires: List[str] = []
    priority: int = 100
    enabled: bool = True
    circuit_breaker_disabled: bool = False


class PluginState(BaseModel):
    """Plugin state information"""
    plugin: str
    persistent_state: dict = {}
    last_updated: Optional[str] = None


@router.get("/", response_model=List[Plugin])
async def list_plugins(
    project_id: str,
    db: Database = Depends(get_db),
):
    """
    List all plugins for a project
    
    Returns plugin manifests and their current status (enabled/disabled, circuit breaker state).
    """
    project_path = await get_project_path(db, project_id)
    plugins_dir = project_path / "felix" / "plugins"
    
    if not plugins_dir.exists():
        return []
    
    # Load config to check disabled plugins
    config_file = project_path / "felix" / "config.json"
    disabled_plugins = []
    if config_file.exists():
        try:
            config = json.loads(config_file.read_text())
            if "plugins" in config and "disabled" in config["plugins"]:
                disabled_plugins = config["plugins"]["disabled"]
        except (json.JSONDecodeError, IOError):
            pass
    
    plugins = []
    
    for plugin_dir in plugins_dir.iterdir():
        if not plugin_dir.is_dir():
            continue
        
        manifest_file = plugin_dir / "plugin.json"
        if not manifest_file.exists():
            continue
        
        try:
            manifest = json.loads(manifest_file.read_text())
            
            plugins.append(Plugin(
                name=manifest.get("name", plugin_dir.name),
                version=manifest.get("version", "unknown"),
                api_version=manifest.get("api_version", "v1"),
                description=manifest.get("description"),
                author=manifest.get("author"),
                permissions=manifest.get("permissions", []),
                hooks=manifest.get("hooks", []),
                requires=manifest.get("requires", []),
                priority=manifest.get("priority", 100),
                enabled=manifest.get("name", plugin_dir.name) not in disabled_plugins,
                circuit_breaker_disabled=False  # TODO: Read from runtime state
            ))
        except (json.JSONDecodeError, IOError) as e:
            # Skip malformed plugins
            continue
    
    return plugins


@router.get("/{plugin_name}", response_model=Plugin)
async def get_plugin(
    project_id: str,
    plugin_name: str,
    db: Database = Depends(get_db),
):
    """Get details for a specific plugin"""
    project_path = await get_project_path(db, project_id)
    plugin_dir = project_path / "felix" / "plugins" / plugin_name
    
    if not plugin_dir.exists():
        raise HTTPException(status_code=404, detail="Plugin not found")
    
    manifest_file = plugin_dir / "plugin.json"
    if not manifest_file.exists():
        raise HTTPException(status_code=404, detail="Plugin manifest not found")
    
    try:
        manifest = json.loads(manifest_file.read_text())
        
        # Check if disabled
        config_file = project_path / "felix" / "config.json"
        disabled = False
        if config_file.exists():
            try:
                config = json.loads(config_file.read_text())
                if "plugins" in config and "disabled" in config["plugins"]:
                    disabled = plugin_name in config["plugins"]["disabled"]
            except (json.JSONDecodeError, IOError):
                pass
        
        return Plugin(
            name=manifest.get("name", plugin_name),
            version=manifest.get("version", "unknown"),
            api_version=manifest.get("api_version", "v1"),
            description=manifest.get("description"),
            author=manifest.get("author"),
            permissions=manifest.get("permissions", []),
            hooks=manifest.get("hooks", []),
            requires=manifest.get("requires", []),
            priority=manifest.get("priority", 100),
            enabled=not disabled,
            circuit_breaker_disabled=False
        )
    except (json.JSONDecodeError, IOError):
        raise HTTPException(status_code=500, detail="Failed to read plugin manifest")


@router.post("/{plugin_name}/enable")
async def enable_plugin(
    project_id: str,
    plugin_name: str,
    db: Database = Depends(get_db),
):
    """Enable a plugin by removing it from the disabled list"""
    project_path = await get_project_path(db, project_id)
    config_file = project_path / "felix" / "config.json"
    
    if not config_file.exists():
        raise HTTPException(status_code=404, detail="Config file not found")
    
    try:
        config = json.loads(config_file.read_text())
        
        if "plugins" not in config:
            config["plugins"] = {}
        
        if "disabled" not in config["plugins"]:
            config["plugins"]["disabled"] = []
        
        if plugin_name in config["plugins"]["disabled"]:
            config["plugins"]["disabled"].remove(plugin_name)
        
        config_file.write_text(json.dumps(config, indent=2))
        
        return {"status": "enabled", "plugin": plugin_name}
    except (json.JSONDecodeError, IOError) as e:
        raise HTTPException(status_code=500, detail=f"Failed to update config: {str(e)}")


@router.post("/{plugin_name}/disable")
async def disable_plugin(
    project_id: str,
    plugin_name: str,
    db: Database = Depends(get_db),
):
    """Disable a plugin by adding it to the disabled list"""
    project_path = await get_project_path(db, project_id)
    config_file = project_path / "felix" / "config.json"
    
    if not config_file.exists():
        raise HTTPException(status_code=404, detail="Config file not found")
    
    try:
        config = json.loads(config_file.read_text())
        
        if "plugins" not in config:
            config["plugins"] = {}
        
        if "disabled" not in config["plugins"]:
            config["plugins"]["disabled"] = []
        
        if plugin_name not in config["plugins"]["disabled"]:
            config["plugins"]["disabled"].append(plugin_name)
        
        config_file.write_text(json.dumps(config, indent=2))
        
        return {"status": "disabled", "plugin": plugin_name}
    except (json.JSONDecodeError, IOError) as e:
        raise HTTPException(status_code=500, detail=f"Failed to update config: {str(e)}")


@router.post("/{plugin_name}/reset-circuit-breaker")
async def reset_circuit_breaker(
    project_id: str,
    plugin_name: str,
    db: Database = Depends(get_db),
):
    """
    Reset circuit breaker for a plugin
    
    Note: This API endpoint is a placeholder. The actual circuit breaker state
    is managed in memory by felix-agent.ps1 and resets on agent restart.
    Consider adding persistent circuit breaker state if needed.
    """
    project_path = await get_project_path(db, project_id)
    plugin_dir = project_path / "felix" / "plugins" / plugin_name
    
    if not plugin_dir.exists():
        raise HTTPException(status_code=404, detail="Plugin not found")
    
    return {
        "status": "reset",
        "plugin": plugin_name,
        "note": "Circuit breaker state is in-memory. Will reset on next agent run."
    }


@router.get("/{plugin_name}/state", response_model=PluginState)
async def get_plugin_state(
    project_id: str,
    plugin_name: str,
    db: Database = Depends(get_db),
):
    """Get persistent state for a plugin"""
    project_path = await get_project_path(db, project_id)
    state_file = project_path / "felix" / "plugins" / plugin_name / "persistent-state.json"
    
    if not state_file.exists():
        return PluginState(plugin=plugin_name, persistent_state={})
    
    try:
        state_data = json.loads(state_file.read_text())
        last_modified = datetime.fromtimestamp(state_file.stat().st_mtime).isoformat()
        
        return PluginState(
            plugin=plugin_name,
            persistent_state=state_data,
            last_updated=last_modified
        )
    except (json.JSONDecodeError, IOError):
        raise HTTPException(status_code=500, detail="Failed to read plugin state")
