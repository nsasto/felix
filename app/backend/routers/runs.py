"""
Felix Backend - Agent Runs API
Handles agent spawning, stopping, and run history.
"""

import os
import sys
import subprocess
from datetime import datetime
from typing import Dict, Optional
from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

import storage


router = APIRouter(prefix="/api/projects", tags=["runs"])


# In-memory store for running agent processes
# Key: project_id, Value: AgentProcess info
_running_agents: Dict[str, "AgentProcessInfo"] = {}


class AgentProcessInfo(BaseModel):
    """Information about a running agent process"""

    project_id: str
    pid: int
    started_at: datetime = Field(default_factory=datetime.now)
    project_path: str


class RunStartResponse(BaseModel):
    """Response from starting an agent run"""

    message: str
    project_id: str
    pid: int
    started_at: datetime


class RunStatusResponse(BaseModel):
    """Response with agent run status"""

    project_id: str
    running: bool
    pid: Optional[int] = None
    started_at: Optional[datetime] = None


def _is_process_running(pid: int) -> bool:
    """Check if a process with given PID is still running"""
    try:
        # On Windows and Unix, this doesn't kill the process with signal 0
        # It just checks if the process exists
        os.kill(pid, 0)
        return True
    except (OSError, ProcessLookupError):
        return False


def _cleanup_dead_agents():
    """Remove entries for agents that are no longer running"""
    dead_projects = []
    for project_id, info in _running_agents.items():
        if not _is_process_running(info.pid):
            dead_projects.append(project_id)

    for project_id in dead_projects:
        del _running_agents[project_id]


@router.post("/{project_id}/runs/start", response_model=RunStartResponse)
async def start_agent_run(project_id: str):
    """
    Spawn a Felix agent process for the specified project.

    The agent runs detached and writes its state to felix/state.json.
    Returns immediately after spawning - does not wait for completion.

    Returns 409 if an agent is already running for this project.
    """
    # Clean up any dead agents first
    _cleanup_dead_agents()

    # Check if agent already running for this project
    if project_id in _running_agents:
        info = _running_agents[project_id]
        if _is_process_running(info.pid):
            raise HTTPException(
                status_code=409,
                detail=f"Agent already running for project {project_id} (PID: {info.pid})",
            )
        else:
            # Process died, remove stale entry
            del _running_agents[project_id]

    # Get project details
    project = storage.get_project_by_id(project_id)
    if not project:
        raise HTTPException(status_code=404, detail=f"Project not found: {project_id}")

    project_path = Path(project.path)
    if not project_path.exists():
        raise HTTPException(
            status_code=400, detail=f"Project directory does not exist: {project.path}"
        )

    # Locate the agent script
    # The agent is felix-agent.ps1 at the project root
    # For now, we assume it's in the same repo as the backend
    # TODO: Make this configurable or use a global felix-agent installation
    repo_root = Path(__file__).parent.parent.parent  # app/backend -> app -> root
    agent_script = repo_root / "felix-agent.ps1"

    if not agent_script.exists():
        raise HTTPException(
            status_code=500, detail=f"Agent script not found: {agent_script}"
        )

    try:
        # Spawn agent process detached
        # Use subprocess.Popen with DETACHED_PROCESS flag on Windows
        # or start_new_session on Unix to detach from parent

        # Use PowerShell to run the agent script
        powershell_exe = "powershell.exe" if sys.platform == "win32" else "pwsh"

        # Build command
        cmd = [powershell_exe, "-File", str(agent_script), str(project_path)]

        # Platform-specific process creation flags
        kwargs = {
            "stdout": subprocess.PIPE,
            "stderr": subprocess.STDOUT,
            "cwd": str(project_path),
        }

        if sys.platform == "win32":
            # Windows: CREATE_NEW_PROCESS_GROUP | DETACHED_PROCESS
            CREATE_NEW_PROCESS_GROUP = 0x00000200
            DETACHED_PROCESS = 0x00000008
            kwargs["creationflags"] = CREATE_NEW_PROCESS_GROUP | DETACHED_PROCESS
        else:
            # Unix: start new session to detach
            kwargs["start_new_session"] = True

        process = subprocess.Popen(cmd, **kwargs)

        # Store process info
        agent_info = AgentProcessInfo(
            project_id=project_id,
            pid=process.pid,
            started_at=datetime.now(),
            project_path=str(project_path),
        )
        _running_agents[project_id] = agent_info

        return RunStartResponse(
            message=f"Agent started for project {project.name}",
            project_id=project_id,
            pid=process.pid,
            started_at=agent_info.started_at,
        )

    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Failed to spawn agent process: {str(e)}"
        )


@router.get("/{project_id}/runs/status", response_model=RunStatusResponse)
async def get_agent_status(project_id: str):
    """
    Get the current status of the agent for a project.

    Returns whether an agent is currently running and its PID if so.
    """
    # Clean up any dead agents first
    _cleanup_dead_agents()

    # Check if project exists
    project = storage.get_project_by_id(project_id)
    if not project:
        raise HTTPException(status_code=404, detail=f"Project not found: {project_id}")

    if project_id in _running_agents:
        info = _running_agents[project_id]
        return RunStatusResponse(
            project_id=project_id,
            running=True,
            pid=info.pid,
            started_at=info.started_at,
        )

    return RunStatusResponse(project_id=project_id, running=False)


# Expose the running agents dict for cleanup during shutdown
def get_running_agents() -> Dict[str, AgentProcessInfo]:
    """Get the dictionary of running agents (for shutdown cleanup)"""
    return _running_agents
