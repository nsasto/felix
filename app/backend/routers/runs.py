"""
Felix Backend - Agent Runs API
Handles agent spawning, stopping, and run history.
"""

import os
import sys
import json
import subprocess
import threading
from datetime import datetime
from typing import Dict, Optional, List
from pathlib import Path
from enum import Enum

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

import storage


router = APIRouter(prefix="/api/projects", tags=["runs"])


class RunStatus(str, Enum):
    """Status of an agent run"""

    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    STOPPED = "stopped"


class AgentProcessInfo(BaseModel):
    """Information about a running agent process"""

    project_id: str
    pid: int
    started_at: datetime = Field(default_factory=datetime.now)
    project_path: str
    process: Optional[subprocess.Popen] = None  # Actual process object for monitoring

    class Config:
        arbitrary_types_allowed = True


class RunHistoryEntry(BaseModel):
    """A completed or historical run entry"""

    run_id: str
    project_id: str
    pid: int
    status: RunStatus
    started_at: datetime
    ended_at: Optional[datetime] = None
    exit_code: Optional[int] = None
    project_path: str
    error_message: Optional[str] = None


# In-memory store for running agent processes
# Key: project_id, Value: AgentProcess info
_running_agents: Dict[str, AgentProcessInfo] = {}

# In-memory store for run history (ephemeral, not persisted)
# Key: project_id, Value: List of RunHistoryEntry
_run_history: Dict[str, List[RunHistoryEntry]] = {}

# Counter for generating run IDs
_run_counter: int = 0
_run_counter_lock = threading.Lock()


class RunStartResponse(BaseModel):
    """Response from starting an agent run"""

    message: str
    project_id: str
    run_id: str
    pid: int
    started_at: datetime


class RunStatusResponse(BaseModel):
    """Response with agent run status"""

    project_id: str
    running: bool
    run_id: Optional[str] = None
    pid: Optional[int] = None
    started_at: Optional[datetime] = None
    status: Optional[RunStatus] = None


class RunHistoryResponse(BaseModel):
    """Response for run history list"""

    project_id: str
    runs: List[RunHistoryEntry]
    total: int


class RunDetailResponse(BaseModel):
    """Detailed response for a specific run"""

    run: RunHistoryEntry
    artifacts: List[str] = []  # List of available artifact files


class RunArtifactContent(BaseModel):
    """Response for run artifact content"""

    run_id: str
    filename: str
    content: str
    size: int


def _generate_run_id() -> str:
    """Generate a unique run ID"""
    global _run_counter
    with _run_counter_lock:
        _run_counter += 1
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        return f"run-{timestamp}-{_run_counter:04d}"


def _is_process_running(pid: int) -> bool:
    """Check if a process with given PID is still running"""
    try:
        # On Windows and Unix, this doesn't kill the process with signal 0
        # It just checks if the process exists
        os.kill(pid, 0)
        return True
    except (OSError, ProcessLookupError):
        return False


def _add_to_history(entry: RunHistoryEntry):
    """Add a run entry to the project's history"""
    project_id = entry.project_id
    if project_id not in _run_history:
        _run_history[project_id] = []
    _run_history[project_id].append(entry)

    # Keep only last 100 runs per project to prevent memory bloat
    if len(_run_history[project_id]) > 100:
        _run_history[project_id] = _run_history[project_id][-100:]


def _update_run_status(
    run_id: str,
    project_id: str,
    status: RunStatus,
    exit_code: Optional[int] = None,
    error_message: Optional[str] = None,
):
    """Update the status of a run in history"""
    if project_id in _run_history:
        for entry in _run_history[project_id]:
            if entry.run_id == run_id:
                entry.status = status
                entry.ended_at = datetime.now()
                entry.exit_code = exit_code
                entry.error_message = error_message
                break


def _check_and_update_agent_status(project_id: str):
    """Check if a running agent has completed and update its status"""
    if project_id not in _running_agents:
        return

    info = _running_agents[project_id]

    # Check if process has completed
    if info.process is not None:
        exit_code = info.process.poll()
        if exit_code is not None:
            # Process has completed
            status = RunStatus.COMPLETED if exit_code == 0 else RunStatus.FAILED

            # Find and update the run in history
            if project_id in _run_history:
                for entry in reversed(_run_history[project_id]):
                    if entry.pid == info.pid and entry.status == RunStatus.RUNNING:
                        entry.status = status
                        entry.ended_at = datetime.now()
                        entry.exit_code = exit_code
                        break

            # Remove from running agents
            del _running_agents[project_id]


def _cleanup_dead_agents():
    """Remove entries for agents that are no longer running and update their history"""
    dead_projects = []
    for project_id, info in _running_agents.items():
        # First check via the process object if available
        if info.process is not None:
            exit_code = info.process.poll()
            if exit_code is not None:
                # Process completed, update history
                status = RunStatus.COMPLETED if exit_code == 0 else RunStatus.FAILED
                if project_id in _run_history:
                    for entry in reversed(_run_history[project_id]):
                        if entry.pid == info.pid and entry.status == RunStatus.RUNNING:
                            entry.status = status
                            entry.ended_at = datetime.now()
                            entry.exit_code = exit_code
                            break
                dead_projects.append(project_id)
                continue

        # Fallback to PID check
        if not _is_process_running(info.pid):
            # Process died without proper exit code capture
            if project_id in _run_history:
                for entry in reversed(_run_history[project_id]):
                    if entry.pid == info.pid and entry.status == RunStatus.RUNNING:
                        entry.status = RunStatus.FAILED
                        entry.ended_at = datetime.now()
                        entry.error_message = "Process terminated unexpectedly"
                        break
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

    # Agent script is always at the project root
    agent_script = project_path / "felix-agent.ps1"

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

        # Generate run ID
        run_id = _generate_run_id()
        started_at = datetime.now()

        # Store process info with process object for exit code tracking
        agent_info = AgentProcessInfo(
            project_id=project_id,
            pid=process.pid,
            started_at=started_at,
            project_path=str(project_path),
            process=process,
        )
        _running_agents[project_id] = agent_info

        # Create run history entry
        history_entry = RunHistoryEntry(
            run_id=run_id,
            project_id=project_id,
            pid=process.pid,
            status=RunStatus.RUNNING,
            started_at=started_at,
            project_path=str(project_path),
        )
        _add_to_history(history_entry)

        return RunStartResponse(
            message=f"Agent started for project {project.name}",
            project_id=project_id,
            run_id=run_id,
            pid=process.pid,
            started_at=started_at,
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
        # Find the current run_id from history
        run_id = None
        if project_id in _run_history:
            for entry in reversed(_run_history[project_id]):
                if entry.pid == info.pid and entry.status == RunStatus.RUNNING:
                    run_id = entry.run_id
                    break

        return RunStatusResponse(
            project_id=project_id,
            running=True,
            run_id=run_id,
            pid=info.pid,
            started_at=info.started_at,
            status=RunStatus.RUNNING,
        )

    return RunStatusResponse(project_id=project_id, running=False)


class RunStopResponse(BaseModel):
    """Response from stopping an agent run"""

    message: str
    project_id: str
    run_id: Optional[str] = None
    pid: int
    status: RunStatus


@router.post("/{project_id}/runs/stop", response_model=RunStopResponse)
async def stop_agent_run(project_id: str):
    """
    Stop a running Felix agent for the specified project.

    Sends a termination signal to the agent process and updates run history.
    Returns 404 if no agent is running for this project.
    """
    import signal

    # Clean up any dead agents first
    _cleanup_dead_agents()

    # Check if project exists
    project = storage.get_project_by_id(project_id)
    if not project:
        raise HTTPException(status_code=404, detail=f"Project not found: {project_id}")

    # Check if agent is running for this project
    if project_id not in _running_agents:
        raise HTTPException(
            status_code=404,
            detail=f"No agent running for project {project_id}",
        )

    info = _running_agents[project_id]

    # Verify process is still running
    if not _is_process_running(info.pid):
        # Process already dead, clean up
        del _running_agents[project_id]
        raise HTTPException(
            status_code=404,
            detail=f"Agent process already terminated for project {project_id}",
        )

    # Find the run_id from history
    run_id = None
    if project_id in _run_history:
        for entry in reversed(_run_history[project_id]):
            if entry.pid == info.pid and entry.status == RunStatus.RUNNING:
                run_id = entry.run_id
                break

    try:
        # Terminate the process
        if info.process is not None:
            # Use the process object for cleaner termination
            info.process.terminate()
            # Give it a moment to terminate gracefully
            try:
                info.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                # Force kill if it doesn't terminate gracefully
                info.process.kill()
        else:
            # Fallback to os.kill
            if sys.platform == "win32":
                # On Windows, use taskkill for more reliable termination
                subprocess.run(
                    ["taskkill", "/F", "/PID", str(info.pid)],
                    capture_output=True,
                    timeout=10,
                )
            else:
                # On Unix, send SIGTERM first, then SIGKILL if needed
                os.kill(info.pid, signal.SIGTERM)
                # Give it a moment
                import time

                time.sleep(1)
                if _is_process_running(info.pid):
                    os.kill(info.pid, signal.SIGKILL)

        # Update run history
        if project_id in _run_history:
            for entry in reversed(_run_history[project_id]):
                if entry.pid == info.pid and entry.status == RunStatus.RUNNING:
                    entry.status = RunStatus.STOPPED
                    entry.ended_at = datetime.now()
                    entry.error_message = "Agent stopped by user"
                    break

        # Remove from running agents
        del _running_agents[project_id]

        return RunStopResponse(
            message=f"Agent stopped for project {project.name}",
            project_id=project_id,
            run_id=run_id,
            pid=info.pid,
            status=RunStatus.STOPPED,
        )

    except Exception as e:
        # Even on error, try to clean up
        if project_id in _running_agents:
            del _running_agents[project_id]
        raise HTTPException(
            status_code=500,
            detail=f"Failed to stop agent process: {str(e)}",
        )


@router.get("/{project_id}/runs", response_model=RunHistoryResponse)
async def get_run_history(project_id: str):
    """
    Get the run history for a project.

    Returns a list of all runs (running, completed, failed, stopped) in reverse chronological order.
    Scans the runs/ directory on disk to populate history from past runs.
    """
    # Clean up any dead agents first
    _cleanup_dead_agents()

    # Check if project exists
    project = storage.get_project_by_id(project_id)
    if not project:
        raise HTTPException(status_code=404, detail=f"Project not found: {project_id}")

    # Start with in-memory history
    runs = _run_history.get(project_id, []).copy()

    # Scan runs/ directory on disk to find historical runs not in memory
    project_path = Path(project.path)
    runs_dir = project_path / "runs"

    if runs_dir.exists():
        # Get run IDs already in memory to avoid duplicates
        existing_run_ids = {r.run_id for r in runs}

        # Scan run directories
        for run_dir in runs_dir.iterdir():
            if not run_dir.is_dir():
                continue

            run_id = run_dir.name

            # Skip if already in memory
            if run_id in existing_run_ids:
                continue

            # Try to parse timestamp from directory name (format: YYYY-MM-DDTHH-MM-SS)
            try:
                # Parse timestamp from directory name
                timestamp_str = run_id.replace("T", " ").replace("-", ":")
                # Adjust for the date part (keep dashes in date)
                parts = run_id.split("T")
                if len(parts) == 2:
                    date_part = parts[0]  # YYYY-MM-DD
                    time_part = parts[1].replace("-", ":")  # HH:MM:SS
                    timestamp_str = f"{date_part} {time_part}"
                    started_at = datetime.fromisoformat(timestamp_str)
                else:
                    # Fallback to directory modification time
                    started_at = datetime.fromtimestamp(run_dir.stat().st_mtime)
            except Exception:
                # If parsing fails, use directory modification time
                started_at = datetime.fromtimestamp(run_dir.stat().st_mtime)

            # Determine status based on artifacts
            status = RunStatus.COMPLETED
            exit_code = None
            ended_at = None
            error_message = None

            # Check for output.log to determine if run completed
            output_log = run_dir / "output.log"
            if output_log.exists():
                try:
                    # Try to determine status from log
                    log_content = output_log.read_text(
                        encoding="utf-8", errors="ignore"
                    )
                    if "FAILED" in log_content or "ERROR" in log_content:
                        status = RunStatus.FAILED
                    ended_at = datetime.fromtimestamp(output_log.stat().st_mtime)
                except Exception:
                    pass

            # Create historical entry
            history_entry = RunHistoryEntry(
                run_id=run_id,
                project_id=project_id,
                pid=0,  # Unknown PID for historical runs
                status=status,
                started_at=started_at,
                ended_at=ended_at,
                exit_code=exit_code,
                project_path=str(project_path),
                error_message=error_message,
            )
            runs.append(history_entry)

    # Return in reverse chronological order (newest first)
    runs_sorted = sorted(runs, key=lambda r: r.started_at, reverse=True)

    return RunHistoryResponse(
        project_id=project_id,
        runs=runs_sorted,
        total=len(runs_sorted),
    )


@router.get("/{project_id}/runs/{run_id}", response_model=RunDetailResponse)
async def get_run_detail(project_id: str, run_id: str):
    """
    Get detailed information about a specific run, including available artifacts.

    Artifacts are read from the runs/ directory in the project.
    """
    # Check if project exists
    project = storage.get_project_by_id(project_id)
    if not project:
        raise HTTPException(status_code=404, detail=f"Project not found: {project_id}")

    # Find the run in history
    run_entry = None
    if project_id in _run_history:
        for entry in _run_history[project_id]:
            if entry.run_id == run_id:
                run_entry = entry
                break

    if not run_entry:
        raise HTTPException(status_code=404, detail=f"Run not found: {run_id}")

    # Scan for artifacts in the project's runs directory
    artifacts = []
    runs_dir = Path(project.path) / "runs"
    if runs_dir.exists():
        # Look for directories that might match this run
        # The agent creates directories like runs/<timestamp>/
        for run_dir in runs_dir.iterdir():
            if run_dir.is_dir():
                # List artifact files
                for artifact_file in run_dir.iterdir():
                    if artifact_file.is_file():
                        artifacts.append(f"{run_dir.name}/{artifact_file.name}")

    return RunDetailResponse(
        run=run_entry,
        artifacts=artifacts,
    )


@router.get(
    "/{project_id}/runs/{run_id}/artifacts/{filename:path}",
    response_model=RunArtifactContent,
)
async def get_run_artifact(project_id: str, run_id: str, filename: str):
    """
    Read the content of a specific run artifact file.

    Artifacts are files in the runs/<run_id>/ directory such as:
    - report.md: Run report in markdown format
    - output.log: Agent output log
    - plan-<requirement-id>.md: Plan snapshot for the run
    - diff.patch: Changes made during the run

    The filename can include subdirectories (e.g., "subdir/file.txt").

    Returns 404 if the artifact file doesn't exist.
    Returns 400 for invalid filenames (path traversal attempts).
    """
    # Check if project exists
    project = storage.get_project_by_id(project_id)
    if not project:
        raise HTTPException(status_code=404, detail=f"Project not found: {project_id}")

    # Validate filename - prevent path traversal
    if ".." in filename or filename.startswith("/") or filename.startswith("\\"):
        raise HTTPException(
            status_code=400, detail="Invalid filename: path traversal not allowed"
        )

    # Normalize path separators
    filename = filename.replace("\\", "/")

    project_path = Path(project.path)
    runs_dir = project_path / "runs"

    if not runs_dir.exists():
        raise HTTPException(
            status_code=404, detail="No runs directory found in project"
        )

    # Build path to artifact
    # run_id is typically a timestamp like "2026-01-25T17-03-59"
    artifact_path = runs_dir / run_id / filename

    # Ensure the path is still within runs directory (extra security check)
    try:
        artifact_path = artifact_path.resolve()
        runs_dir_resolved = runs_dir.resolve()
        if not str(artifact_path).startswith(str(runs_dir_resolved)):
            raise HTTPException(
                status_code=400, detail="Invalid path: outside runs directory"
            )
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid path")

    if not artifact_path.exists():
        raise HTTPException(
            status_code=404, detail=f"Artifact not found: {run_id}/{filename}"
        )

    if not artifact_path.is_file():
        raise HTTPException(status_code=400, detail="Path is not a file")

    try:
        content = artifact_path.read_text(encoding="utf-8")
        return RunArtifactContent(
            run_id=run_id, filename=filename, content=content, size=len(content)
        )
    except UnicodeDecodeError:
        raise HTTPException(
            status_code=400,
            detail="Cannot read file: not a text file or invalid encoding",
        )
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Failed to read artifact: {str(e)}"
        )


# Expose the running agents dict for cleanup during shutdown
def get_running_agents() -> Dict[str, AgentProcessInfo]:
    """Get the dictionary of running agents (for shutdown cleanup)"""
    return _running_agents


def get_run_history() -> Dict[str, List[RunHistoryEntry]]:
    """Get the run history dictionary (for inspection/testing)"""
    return _run_history
