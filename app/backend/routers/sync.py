"""
Felix Backend - Sync Router
REST API endpoints for run artifact syncing from CLI agents.

This module provides endpoints for:
- Agent registration (upsert)
- Run creation
- Event logging (batch append)
- Run completion
- Artifact upload/download
- Event querying with pagination

All endpoints are tagged with "sync" for API documentation organization.

NOTE: This is separate from routers/agents.py which handles UI-driven agent operations.
These endpoints are designed for CLI agent sync workflows.
"""

import hashlib
import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

import asyncpg
from databases import Database
from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, Query, UploadFile
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from artifact_storage import get_artifact_storage, ArtifactStorage
from database.db import get_db


# ============================================================================
# DATABASE ERROR TYPES
# ============================================================================

# Exception types that indicate transient database connection issues
# These should return 503 Service Unavailable to signal client retry
DATABASE_CONNECTION_ERRORS = (
    asyncpg.PostgresConnectionError,
    asyncpg.InterfaceError,
    ConnectionRefusedError,
    ConnectionResetError,
    OSError,
)

# Configure logger
logger = logging.getLogger(__name__)


# ============================================================================
# STRUCTURED LOGGING HELPERS
# ============================================================================

def log_sync_info(message: str, *, run_id: Optional[str] = None, agent_id: Optional[str] = None, **extra):
    """
    Log info message with structured context for sync operations.
    
    Args:
        message: Log message
        run_id: Optional run ID for context
        agent_id: Optional agent ID for context
        **extra: Additional key-value pairs to include in log context
    """
    context_parts = []
    if run_id:
        context_parts.append(f"run_id={run_id}")
    if agent_id:
        context_parts.append(f"agent_id={agent_id}")
    for key, value in extra.items():
        context_parts.append(f"{key}={value}")
    
    context_str = f"[{' '.join(context_parts)}] " if context_parts else ""
    logger.info(f"{context_str}{message}")


def log_sync_warning(message: str, *, run_id: Optional[str] = None, agent_id: Optional[str] = None, **extra):
    """
    Log warning message with structured context for sync operations.
    
    Args:
        message: Log message
        run_id: Optional run ID for context
        agent_id: Optional agent ID for context
        **extra: Additional key-value pairs to include in log context
    """
    context_parts = []
    if run_id:
        context_parts.append(f"run_id={run_id}")
    if agent_id:
        context_parts.append(f"agent_id={agent_id}")
    for key, value in extra.items():
        context_parts.append(f"{key}={value}")
    
    context_str = f"[{' '.join(context_parts)}] " if context_parts else ""
    logger.warning(f"{context_str}{message}")


def log_sync_error(message: str, *, run_id: Optional[str] = None, agent_id: Optional[str] = None, exc: Optional[Exception] = None, **extra):
    """
    Log error message with structured context for sync operations.
    
    Args:
        message: Log message
        run_id: Optional run ID for context
        agent_id: Optional agent ID for context
        exc: Optional exception to include (logs stack trace)
        **extra: Additional key-value pairs to include in log context
    """
    context_parts = []
    if run_id:
        context_parts.append(f"run_id={run_id}")
    if agent_id:
        context_parts.append(f"agent_id={agent_id}")
    for key, value in extra.items():
        context_parts.append(f"{key}={value}")
    
    context_str = f"[{' '.join(context_parts)}] " if context_parts else ""
    if exc:
        logger.error(f"{context_str}{message}", exc_info=exc)
    else:
        logger.error(f"{context_str}{message}")


def log_sync_debug(message: str, *, run_id: Optional[str] = None, agent_id: Optional[str] = None, **extra):
    """
    Log debug message with structured context for sync operations.
    
    Args:
        message: Log message
        run_id: Optional run ID for context
        agent_id: Optional agent ID for context
        **extra: Additional key-value pairs to include in log context
    """
    context_parts = []
    if run_id:
        context_parts.append(f"run_id={run_id}")
    if agent_id:
        context_parts.append(f"agent_id={agent_id}")
    for key, value in extra.items():
        context_parts.append(f"{key}={value}")
    
    context_str = f"[{' '.join(context_parts)}] " if context_parts else ""
    logger.debug(f"{context_str}{message}")


def is_database_connection_error(exc: Exception) -> bool:
    """
    Check if an exception is a database connection error.
    
    These errors are transient and indicate the database is temporarily
    unreachable. Clients should retry after receiving a 503 response.
    
    Args:
        exc: Exception to check
        
    Returns:
        True if the exception indicates a database connection issue
    """
    # Check if it's one of the known connection error types
    if isinstance(exc, DATABASE_CONNECTION_ERRORS):
        return True
    
    # Check for nested connection errors (e.g., wrapped in databases library)
    if exc.__cause__ and isinstance(exc.__cause__, DATABASE_CONNECTION_ERRORS):
        return True
    
    # Check error message for common connection patterns
    error_message = str(exc).lower()
    connection_keywords = [
        "connection refused",
        "connection reset",
        "connection closed",
        "connection timed out",
        "could not connect",
        "database is unavailable",
        "no connection to server",
        "connection pool exhausted",
        "too many connections",
    ]
    return any(keyword in error_message for keyword in connection_keywords)


def raise_database_unavailable(
    operation: str,
    exc: Exception,
    *,
    run_id: Optional[str] = None,
    agent_id: Optional[str] = None,
    **extra
) -> None:
    """
    Log database connection error and raise 503 Service Unavailable.
    
    This helper standardizes the handling of database connection errors
    across all sync endpoints, ensuring consistent logging and response format.
    
    Args:
        operation: Description of the failed operation (e.g., "agent registration")
        exc: The database exception that was caught
        run_id: Optional run ID for logging context
        agent_id: Optional agent ID for logging context
        **extra: Additional context for logging
        
    Raises:
        HTTPException: 503 Service Unavailable with details
    """
    log_sync_error(
        f"Database unavailable during {operation}",
        run_id=run_id,
        agent_id=agent_id,
        error_type=type(exc).__name__,
        exc=exc,
        **extra
    )
    raise HTTPException(
        status_code=503,
        detail=f"Database temporarily unavailable. Please retry. (Operation: {operation})"
    )


router = APIRouter(tags=["sync"])


# ============================================================================
# AUTH STUB
# ============================================================================

async def verify_api_key(
    authorization: Optional[str] = Header(None, description="Bearer token for authentication")
) -> Optional[str]:
    """
    Verify API key from Authorization header.
    
    TODO: Implement proper API key validation against database.
    Currently accepts any Bearer token for development purposes.
    
    Args:
        authorization: Optional Authorization header value (e.g., "Bearer fsk_xxx")
        
    Returns:
        The API key if provided, None otherwise
    """
    if authorization is None:
        return None
    
    # Extract token from "Bearer <token>" format
    if authorization.startswith("Bearer "):
        return authorization[7:]
    
    return authorization


# ============================================================================
# REQUEST/RESPONSE MODELS
# ============================================================================

class AgentRegistration(BaseModel):
    """Request body for CLI agent registration."""
    agent_id: str = Field(..., description="Unique agent identifier")
    hostname: str = Field(..., description="Hostname where agent is running")
    platform: str = Field(..., description="Operating system platform (e.g., 'windows', 'linux')")
    version: str = Field(..., description="Agent version string")


class AgentRegistrationResponse(BaseModel):
    """Response for agent registration."""
    status: str = Field(..., description="Registration status ('registered')")
    agent_id: str = Field(..., description="Agent ID that was registered")


class RunCreate(BaseModel):
    """Request body for creating a new run."""
    id: Optional[str] = Field(None, description="Optional run ID (UUID will be generated if not provided)")
    requirement_id: Optional[str] = Field(None, description="Requirement ID being worked on")
    agent_id: str = Field(..., description="Agent ID executing the run")
    project_id: str = Field(..., description="Project ID the run belongs to")
    branch: Optional[str] = Field(None, description="Git branch name")
    commit_sha: Optional[str] = Field(None, description="Git commit SHA")
    scenario: Optional[str] = Field(None, description="Run scenario identifier")
    phase: Optional[str] = Field(None, description="Run phase (e.g., 'planning', 'building')")


class RunCreateResponse(BaseModel):
    """Response for run creation."""
    run_id: str = Field(..., description="Created run ID")
    status: str = Field(..., description="Creation status ('created')")


class RunEvent(BaseModel):
    """Model for a single run event."""
    type: str = Field(..., description="Event type (e.g., 'started', 'task_completed')")
    level: str = Field(..., description="Event level ('info', 'warn', 'error', 'debug')")
    message: Optional[str] = Field(None, description="Optional event message")
    payload: Optional[Dict[str, Any]] = Field(None, description="Optional JSON payload")


class EventAppendResponse(BaseModel):
    """Response for event append operation."""
    status: str = Field(..., description="Append status ('appended')")
    count: int = Field(..., description="Number of events appended")


class RunCompletion(BaseModel):
    """Request body for completing a run."""
    status: str = Field(..., description="Final run status ('completed', 'failed', etc.)")
    exit_code: Optional[int] = Field(None, description="Process exit code")
    duration_sec: Optional[int] = Field(None, description="Total run duration in seconds")
    error_summary: Optional[str] = Field(None, description="Error summary if failed")
    summary_json: Optional[Dict[str, Any]] = Field(None, description="Optional summary data as JSON")


class RunCompletionResponse(BaseModel):
    """Response for run completion."""
    status: str = Field(..., description="Completion status ('finished')")
    run_id: str = Field(..., description="Run ID that was completed")


class FileUploadResult(BaseModel):
    """Result for a single file upload."""
    path: str = Field(..., description="File path within the run")
    status: str = Field(..., description="Upload status ('uploaded', 'skipped')")
    size_bytes: int = Field(..., description="File size in bytes")
    reason: Optional[str] = Field(None, description="Reason for status (e.g., 'unchanged' for skipped)")


class FileUploadResponse(BaseModel):
    """Response for file upload operation."""
    run_id: str = Field(..., description="Run ID files were uploaded to")
    files: List[FileUploadResult] = Field(..., description="Results for each file")
    total: int = Field(..., description="Total files in manifest")
    uploaded: int = Field(..., description="Number of files uploaded")
    skipped: int = Field(..., description="Number of files skipped")


class FileInfo(BaseModel):
    """Information about a run file."""
    path: str = Field(..., description="File path within the run")
    kind: str = Field(..., description="File kind ('artifact' or 'log')")
    size_bytes: int = Field(..., description="File size in bytes")
    sha256: Optional[str] = Field(None, description="SHA256 hash of file content")
    content_type: str = Field(..., description="MIME content type")
    updated_at: datetime = Field(..., description="When file was last updated")


class FileListResponse(BaseModel):
    """Response for listing run files."""
    run_id: str = Field(..., description="Run ID")
    files: List[FileInfo] = Field(..., description="List of files in the run")


class EventInfo(BaseModel):
    """Information about a run event."""
    id: int = Field(..., description="Event ID")
    ts: datetime = Field(..., description="Event timestamp")
    type: str = Field(..., description="Event type")
    level: str = Field(..., description="Event level")
    message: Optional[str] = Field(None, description="Event message")
    payload: Optional[Dict[str, Any]] = Field(None, description="Event payload")


class EventListResponse(BaseModel):
    """Response for listing run events."""
    run_id: str = Field(..., description="Run ID")
    events: List[EventInfo] = Field(..., description="List of events")
    has_more: bool = Field(..., description="Whether more events exist after this page")


# ============================================================================
# AGENT REGISTRATION ENDPOINT
# ============================================================================

@router.post("/api/agents/register", response_model=AgentRegistrationResponse)
async def register_agent(
    request: AgentRegistration,
    db: Database = Depends(get_db),
    api_key: Optional[str] = Depends(verify_api_key),
):
    """
    Register or update a CLI agent.
    
    Uses INSERT ... ON CONFLICT for idempotent upsert behavior.
    On conflict, updates hostname, platform, version, and last_seen_at.
    
    Args:
        request: Agent registration data
        db: Database connection
        api_key: Optional API key for authentication
        
    Returns:
        Registration status and agent ID
        
    Raises:
        HTTPException 500: On database error
    """
    try:
        # Upsert agent record
        query = """
            INSERT INTO agents (id, name, hostname, platform, version, last_seen_at, type, status, created_at, updated_at)
            VALUES (:id, :name, :hostname, :platform, :version, :last_seen_at, 'cli', 'idle', NOW(), NOW())
            ON CONFLICT (id) DO UPDATE SET
                hostname = EXCLUDED.hostname,
                platform = EXCLUDED.platform,
                version = EXCLUDED.version,
                last_seen_at = EXCLUDED.last_seen_at,
                updated_at = NOW()
            RETURNING id
        """
        
        await db.execute(
            query,
            {
                "id": request.agent_id,
                "name": request.agent_id,  # Use agent_id as name for CLI agents
                "hostname": request.hostname,
                "platform": request.platform,
                "version": request.version,
                "last_seen_at": datetime.now(timezone.utc),
            }
        )
        
        log_sync_info(
            f"Agent registered on {request.hostname}",
            agent_id=request.agent_id,
            platform=request.platform,
            version=request.version
        )
        
        return AgentRegistrationResponse(
            status="registered",
            agent_id=request.agent_id,
        )
    except Exception as e:
        # Check for database connection errors - return 503 for transient failures
        if is_database_connection_error(e):
            raise_database_unavailable(
                "agent registration",
                e,
                agent_id=request.agent_id
            )
        # Log and return 500 for other database errors
        log_sync_error(
            "Failed to register agent",
            agent_id=request.agent_id,
            exc=e
        )
        raise HTTPException(
            status_code=500,
            detail=f"Database error during agent registration: {str(e)}"
        )


# ============================================================================
# RUN CREATION ENDPOINT
# ============================================================================

@router.post("/api/runs", response_model=RunCreateResponse)
async def create_run(
    request: RunCreate,
    db: Database = Depends(get_db),
    api_key: Optional[str] = Depends(verify_api_key),
):
    """
    Create a new run record.
    
    Generates UUID if run ID not provided. Validates agent and project exist.
    Inserts run with status='running' and creates initial 'started' event.
    
    Args:
        request: Run creation data
        db: Database connection
        api_key: Optional API key for authentication
        
    Returns:
        Created run ID and status
        
    Raises:
        HTTPException 404: If agent or project not found
        HTTPException 500: On database error
    """
    try:
        # Generate run ID if not provided
        run_id = request.id or str(uuid.uuid4())
        
        # Verify agent exists
        agent = await db.fetch_one(
            "SELECT id FROM agents WHERE id = :agent_id",
            {"agent_id": request.agent_id}
        )
        if not agent:
            raise HTTPException(
                status_code=404,
                detail=f"Agent not found: {request.agent_id}"
            )
        
        # Verify project exists
        project = await db.fetch_one(
            "SELECT id FROM projects WHERE id = :project_id",
            {"project_id": request.project_id}
        )
        if not project:
            raise HTTPException(
                status_code=404,
                detail=f"Project not found: {request.project_id}"
            )
        
        # Insert run record
        run_query = """
            INSERT INTO runs (
                id, project_id, agent_id, requirement_id, status, 
                branch, commit_sha, scenario, phase, 
                started_at, created_at
            )
            VALUES (
                :id, :project_id, :agent_id, :requirement_id, 'running',
                :branch, :commit_sha, :scenario, :phase,
                NOW(), NOW()
            )
        """
        
        await db.execute(
            run_query,
            {
                "id": run_id,
                "project_id": request.project_id,
                "agent_id": request.agent_id,
                "requirement_id": request.requirement_id,
                "branch": request.branch,
                "commit_sha": request.commit_sha,
                "scenario": request.scenario,
                "phase": request.phase,
            }
        )
        
        # Insert initial 'started' event
        event_query = """
            INSERT INTO run_events (run_id, type, level, message)
            VALUES (:run_id, 'started', 'info', 'Run started')
        """
        
        await db.execute(event_query, {"run_id": run_id})
        
        log_sync_info(
            "Run created",
            run_id=run_id,
            agent_id=request.agent_id,
            project_id=request.project_id,
            requirement_id=request.requirement_id
        )
        
        return RunCreateResponse(
            run_id=run_id,
            status="created",
        )
    except HTTPException:
        raise
    except Exception as e:
        # Check for database connection errors - return 503 for transient failures
        if is_database_connection_error(e):
            raise_database_unavailable(
                "run creation",
                e,
                agent_id=request.agent_id,
                project_id=request.project_id
            )
        # Log and return 500 for other database errors
        log_sync_error(
            "Failed to create run",
            agent_id=request.agent_id,
            project_id=request.project_id,
            exc=e
        )
        raise HTTPException(
            status_code=500,
            detail=f"Database error during run creation: {str(e)}"
        )


# ============================================================================
# EVENT APPEND ENDPOINT
# ============================================================================

@router.post("/api/runs/{run_id}/events", response_model=EventAppendResponse)
async def append_events(
    run_id: str,
    events: List[RunEvent],
    db: Database = Depends(get_db),
    api_key: Optional[str] = Depends(verify_api_key),
):
    """
    Append events to a run.
    
    Batch inserts multiple events efficiently.
    
    Args:
        run_id: Run ID to append events to
        events: List of events to append
        db: Database connection
        api_key: Optional API key for authentication
        
    Returns:
        Append status and count
        
    Raises:
        HTTPException 404: If run not found
        HTTPException 500: On database error
    """
    try:
        # Verify run exists
        run = await db.fetch_one(
            "SELECT id FROM runs WHERE id = :run_id",
            {"run_id": run_id}
        )
        if not run:
            raise HTTPException(
                status_code=404,
                detail=f"Run not found: {run_id}"
            )
        
        # Handle empty event list gracefully
        if not events:
            return EventAppendResponse(status="appended", count=0)
        
        # Batch insert events
        event_query = """
            INSERT INTO run_events (run_id, type, level, message, payload)
            VALUES (:run_id, :type, :level, :message, :payload)
        """
        
        event_values = [
            {
                "run_id": run_id,
                "type": event.type,
                "level": event.level,
                "message": event.message,
                "payload": json.dumps(event.payload) if event.payload else None,
            }
            for event in events
        ]
        
        await db.execute_many(event_query, event_values)
        
        log_sync_debug(
            f"Appended {len(events)} events",
            run_id=run_id,
            event_count=len(events)
        )
        
        return EventAppendResponse(
            status="appended",
            count=len(events),
        )
    except HTTPException:
        raise
    except Exception as e:
        # Check for database connection errors - return 503 for transient failures
        if is_database_connection_error(e):
            raise_database_unavailable(
                "event append",
                e,
                run_id=run_id,
                event_count=len(events)
            )
        # Log and return 500 for other database errors
        log_sync_error(
            "Failed to append events",
            run_id=run_id,
            event_count=len(events),
            exc=e
        )
        raise HTTPException(
            status_code=500,
            detail=f"Database error during event append: {str(e)}"
        )


# ============================================================================
# RUN COMPLETION ENDPOINT
# ============================================================================

@router.post("/api/runs/{run_id}/finish", response_model=RunCompletionResponse)
async def finish_run(
    run_id: str,
    request: RunCompletion,
    db: Database = Depends(get_db),
    api_key: Optional[str] = Depends(verify_api_key),
):
    """
    Mark a run as finished.
    
    Updates run status, exit code, duration, and summary.
    Inserts completion event with appropriate level.
    
    Args:
        run_id: Run ID to finish
        request: Completion data
        db: Database connection
        api_key: Optional API key for authentication
        
    Returns:
        Completion status and run ID
        
    Raises:
        HTTPException 404: If run not found
        HTTPException 500: On database error
    """
    try:
        # Verify run exists
        run = await db.fetch_one(
            "SELECT id FROM runs WHERE id = :run_id",
            {"run_id": run_id}
        )
        if not run:
            raise HTTPException(
                status_code=404,
                detail=f"Run not found: {run_id}"
            )
        
        # Update run record
        update_query = """
            UPDATE runs SET
                status = :status,
                exit_code = :exit_code,
                duration_sec = :duration_sec,
                error_summary = :error_summary,
                summary_json = :summary_json,
                finished_at = NOW(),
                completed_at = NOW()
            WHERE id = :run_id
        """
        
        await db.execute(
            update_query,
            {
                "run_id": run_id,
                "status": request.status,
                "exit_code": request.exit_code,
                "duration_sec": request.duration_sec,
                "error_summary": request.error_summary,
                "summary_json": json.dumps(request.summary_json) if request.summary_json else None,
            }
        )
        
        # Determine event type and level based on status
        event_type = "completed" if request.status in ("completed", "succeeded") else "failed"
        event_level = "info" if event_type == "completed" else "error"
        event_message = f"Run {event_type}"
        if request.error_summary:
            event_message += f": {request.error_summary}"
        
        # Insert completion event
        event_query = """
            INSERT INTO run_events (run_id, type, level, message)
            VALUES (:run_id, :type, :level, :message)
        """
        
        await db.execute(
            event_query,
            {
                "run_id": run_id,
                "type": event_type,
                "level": event_level,
                "message": event_message,
            }
        )
        
        log_sync_info(
            f"Run finished with status {request.status}",
            run_id=run_id,
            status=request.status,
            exit_code=request.exit_code,
            duration_sec=request.duration_sec
        )
        
        return RunCompletionResponse(
            status="finished",
            run_id=run_id,
        )
    except HTTPException:
        raise
    except Exception as e:
        # Check for database connection errors - return 503 for transient failures
        if is_database_connection_error(e):
            raise_database_unavailable(
                "run completion",
                e,
                run_id=run_id,
                status=request.status
            )
        # Log and return 500 for other database errors
        log_sync_error(
            "Failed to finish run",
            run_id=run_id,
            status=request.status,
            exc=e
        )
        raise HTTPException(
            status_code=500,
            detail=f"Database error during run completion: {str(e)}"
        )


# ============================================================================
# FILE UPLOAD ENDPOINT
# ============================================================================

def determine_file_kind(path: str) -> str:
    """Determine file kind based on extension."""
    lower_path = path.lower()
    if lower_path.endswith(".log") or lower_path.endswith(".txt"):
        return "log"
    return "artifact"


def determine_content_type(path: str) -> str:
    """Determine content type based on file extension."""
    lower_path = path.lower()
    extension_map = {
        ".json": "application/json",
        ".txt": "text/plain",
        ".log": "text/plain",
        ".md": "text/markdown",
        ".py": "text/x-python",
        ".js": "text/javascript",
        ".html": "text/html",
        ".css": "text/css",
        ".xml": "application/xml",
        ".yaml": "application/yaml",
        ".yml": "application/yaml",
    }
    
    for ext, content_type in extension_map.items():
        if lower_path.endswith(ext):
            return content_type
    
    return "application/octet-stream"


@router.post("/api/runs/{run_id}/files", response_model=FileUploadResponse)
async def upload_files(
    run_id: str,
    manifest: str = Form(..., description="JSON manifest with file metadata"),
    files: List[UploadFile] = File(..., description="Files to upload"),
    db: Database = Depends(get_db),
    storage: ArtifactStorage = Depends(get_artifact_storage),
    api_key: Optional[str] = Depends(verify_api_key),
):
    """
    Upload files for a run.
    
    Accepts multipart form with manifest JSON and file uploads.
    Uses SHA256 for idempotency - skips unchanged files.
    
    Manifest format:
    [
        {"path": "output.log", "sha256": "abc123..."},
        {"path": "plan.md", "sha256": "def456..."}
    ]
    
    Args:
        run_id: Run ID to upload files to
        manifest: JSON string with file metadata
        files: Uploaded files
        db: Database connection
        storage: Artifact storage instance
        api_key: Optional API key for authentication
        
    Returns:
        Upload results for each file
        
    Raises:
        HTTPException 400: If manifest JSON is invalid
        HTTPException 404: If run not found
        HTTPException 500: On database or storage error
    """
    try:
        # Parse manifest
        try:
            manifest_data = json.loads(manifest)
        except json.JSONDecodeError as e:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid manifest JSON: {str(e)}"
            )
        
        # Verify run exists and get project_id
        run = await db.fetch_one(
            "SELECT id, project_id FROM runs WHERE id = :run_id",
            {"run_id": run_id}
        )
        if not run:
            raise HTTPException(
                status_code=404,
                detail=f"Run not found: {run_id}"
            )
        
        project_id = str(run["project_id"])
        
        # Create lookup for uploaded files by name
        files_by_name = {f.filename: f for f in files}
        
        results: List[FileUploadResult] = []
        uploaded_count = 0
        skipped_count = 0
        
        for item in manifest_data:
            file_path = item.get("path")
            manifest_sha256 = item.get("sha256")
            
            if not file_path:
                continue
            
            # Check existing file record
            existing = await db.fetch_one(
                "SELECT sha256 FROM run_files WHERE run_id = :run_id AND path = :path",
                {"run_id": run_id, "path": file_path}
            )
            
            # Skip if unchanged
            if existing and existing["sha256"] == manifest_sha256:
                results.append(FileUploadResult(
                    path=file_path,
                    status="skipped",
                    size_bytes=0,
                    reason="unchanged",
                ))
                skipped_count += 1
                continue
            
            # Get uploaded file
            upload_file = files_by_name.get(file_path)
            if not upload_file:
                log_sync_warning(
                    f"File in manifest but not uploaded: {file_path}",
                    run_id=run_id,
                    file_path=file_path
                )
                continue
            
            # Read file content
            content = await upload_file.read()
            size_bytes = len(content)
            
            # Calculate SHA256
            sha256 = hashlib.sha256(content).hexdigest()
            
            # Generate storage key
            storage_key = f"runs/{project_id}/{run_id}/{file_path}"
            
            # Determine file metadata
            kind = determine_file_kind(file_path)
            content_type = determine_content_type(file_path)
            
            # Upload to storage
            await storage.put(storage_key, content, content_type)
            
            # Upsert run_files record
            upsert_query = """
                INSERT INTO run_files (run_id, path, kind, storage_key, size_bytes, sha256, content_type)
                VALUES (:run_id, :path, :kind, :storage_key, :size_bytes, :sha256, :content_type)
                ON CONFLICT (run_id, path) DO UPDATE SET
                    kind = EXCLUDED.kind,
                    storage_key = EXCLUDED.storage_key,
                    size_bytes = EXCLUDED.size_bytes,
                    sha256 = EXCLUDED.sha256,
                    content_type = EXCLUDED.content_type,
                    updated_at = NOW()
            """
            
            await db.execute(
                upsert_query,
                {
                    "run_id": run_id,
                    "path": file_path,
                    "kind": kind,
                    "storage_key": storage_key,
                    "size_bytes": size_bytes,
                    "sha256": sha256,
                    "content_type": content_type,
                }
            )
            
            results.append(FileUploadResult(
                path=file_path,
                status="uploaded",
                size_bytes=size_bytes,
            ))
            uploaded_count += 1
        
        log_sync_info(
            f"Uploaded {uploaded_count} files ({skipped_count} skipped)",
            run_id=run_id,
            uploaded=uploaded_count,
            skipped=skipped_count,
            total=len(manifest_data)
        )
        
        return FileUploadResponse(
            run_id=run_id,
            files=results,
            total=len(manifest_data),
            uploaded=uploaded_count,
            skipped=skipped_count,
        )
    except HTTPException:
        raise
    except Exception as e:
        # Check for database connection errors - return 503 for transient failures
        if is_database_connection_error(e):
            raise_database_unavailable(
                "file upload",
                e,
                run_id=run_id
            )
        # Log and return 500 for other errors
        log_sync_error(
            "Failed to upload files",
            run_id=run_id,
            exc=e
        )
        raise HTTPException(
            status_code=500,
            detail=f"Error during file upload: {str(e)}"
        )


# ============================================================================
# FILE LIST ENDPOINT
# ============================================================================

@router.get("/api/runs/{run_id}/files", response_model=FileListResponse)
async def list_files(
    run_id: str,
    db: Database = Depends(get_db),
    api_key: Optional[str] = Depends(verify_api_key),
):
    """
    List files for a run.
    
    Returns files ordered by kind (artifact first) then path.
    
    Args:
        run_id: Run ID to list files for
        db: Database connection
        api_key: Optional API key for authentication
        
    Returns:
        List of file information
        
    Raises:
        HTTPException 404: If run not found
        HTTPException 500: On database error
    """
    try:
        # Verify run exists
        run = await db.fetch_one(
            "SELECT id FROM runs WHERE id = :run_id",
            {"run_id": run_id}
        )
        if not run:
            raise HTTPException(
                status_code=404,
                detail=f"Run not found: {run_id}"
            )
        
        # Query files ordered by kind (artifact first), then path
        query = """
            SELECT path, kind, size_bytes, sha256, content_type, updated_at
            FROM run_files
            WHERE run_id = :run_id
            ORDER BY kind ASC, path ASC
        """
        
        rows = await db.fetch_all(query, {"run_id": run_id})
        
        files = [
            FileInfo(
                path=row["path"],
                kind=row["kind"],
                size_bytes=row["size_bytes"],
                sha256=row["sha256"],
                content_type=row["content_type"],
                updated_at=row["updated_at"],
            )
            for row in rows
        ]
        
        return FileListResponse(
            run_id=run_id,
            files=files,
        )
    except HTTPException:
        raise
    except Exception as e:
        # Check for database connection errors - return 503 for transient failures
        if is_database_connection_error(e):
            raise_database_unavailable(
                "file listing",
                e,
                run_id=run_id
            )
        # Log and return 500 for other errors
        log_sync_error(
            "Failed to list files",
            run_id=run_id,
            exc=e
        )
        raise HTTPException(
            status_code=500,
            detail=f"Database error during file listing: {str(e)}"
        )


# ============================================================================
# FILE DOWNLOAD ENDPOINT
# ============================================================================

@router.get("/api/runs/{run_id}/files/{file_path:path}")
async def download_file(
    run_id: str,
    file_path: str,
    db: Database = Depends(get_db),
    storage: ArtifactStorage = Depends(get_artifact_storage),
    api_key: Optional[str] = Depends(verify_api_key),
):
    """
    Download a file from a run.
    
    Streams file content with appropriate headers.
    
    Args:
        run_id: Run ID containing the file
        file_path: Path of file within the run
        db: Database connection
        storage: Artifact storage instance
        api_key: Optional API key for authentication
        
    Returns:
        StreamingResponse with file content
        
    Raises:
        HTTPException 404: If file not found in DB or storage
        HTTPException 500: On database or storage error
    """
    try:
        # Fetch file record
        file_record = await db.fetch_one(
            "SELECT storage_key, content_type, size_bytes FROM run_files WHERE run_id = :run_id AND path = :path",
            {"run_id": run_id, "path": file_path}
        )
        if not file_record:
            raise HTTPException(
                status_code=404,
                detail=f"File not found in database: {file_path}"
            )
        
        storage_key = file_record["storage_key"]
        content_type = file_record["content_type"]
        size_bytes = file_record["size_bytes"]
        
        # Check file exists in storage
        if not await storage.exists(storage_key):
            raise HTTPException(
                status_code=404,
                detail=f"File not found in storage: {file_path}"
            )
        
        # Get file content
        content = await storage.get(storage_key)
        
        # Extract filename for Content-Disposition
        filename = file_path.split("/")[-1]
        
        # Stream response
        return StreamingResponse(
            iter([content]),
            media_type=content_type,
            headers={
                "Content-Disposition": f'attachment; filename="{filename}"',
                "Content-Length": str(size_bytes),
            }
        )
    except HTTPException:
        raise
    except Exception as e:
        # Check for database connection errors - return 503 for transient failures
        if is_database_connection_error(e):
            raise_database_unavailable(
                "file download",
                e,
                run_id=run_id,
                file_path=file_path
            )
        # Log and return 500 for other errors
        log_sync_error(
            f"Failed to download file: {file_path}",
            run_id=run_id,
            file_path=file_path,
            exc=e
        )
        raise HTTPException(
            status_code=500,
            detail=f"Error during file download: {str(e)}"
        )


# ============================================================================
# EVENT QUERY ENDPOINT
# ============================================================================

@router.get("/api/runs/{run_id}/events", response_model=EventListResponse)
async def list_events(
    run_id: str,
    after: Optional[int] = Query(None, description="Cursor for pagination - return events after this ID"),
    limit: int = Query(100, ge=1, le=1000, description="Maximum number of events to return"),
    db: Database = Depends(get_db),
    api_key: Optional[str] = Depends(verify_api_key),
):
    """
    Query events for a run.
    
    Returns events in timeline order (oldest first) with cursor-based pagination.
    
    Args:
        run_id: Run ID to query events for
        after: Optional cursor - return events with ID greater than this
        limit: Maximum events to return (default 100)
        db: Database connection
        api_key: Optional API key for authentication
        
    Returns:
        List of events with pagination info
        
    Raises:
        HTTPException 404: If run not found
        HTTPException 500: On database error
    """
    try:
        # Verify run exists
        run = await db.fetch_one(
            "SELECT id FROM runs WHERE id = :run_id",
            {"run_id": run_id}
        )
        if not run:
            raise HTTPException(
                status_code=404,
                detail=f"Run not found: {run_id}"
            )
        
        # Build query with optional cursor
        if after is not None:
            query = """
                SELECT id, ts, type, level, message, payload
                FROM run_events
                WHERE run_id = :run_id AND id > :after
                ORDER BY id ASC
                LIMIT :limit
            """
            params = {"run_id": run_id, "after": after, "limit": limit + 1}
        else:
            query = """
                SELECT id, ts, type, level, message, payload
                FROM run_events
                WHERE run_id = :run_id
                ORDER BY id ASC
                LIMIT :limit
            """
            params = {"run_id": run_id, "limit": limit + 1}
        
        rows = await db.fetch_all(query, params)
        
        # Check if there are more results
        has_more = len(rows) > limit
        if has_more:
            rows = rows[:limit]
        
        events = [
            EventInfo(
                id=row["id"],
                ts=row["ts"],
                type=row["type"],
                level=row["level"],
                message=row["message"],
                payload=json.loads(row["payload"]) if row["payload"] else None,
            )
            for row in rows
        ]
        
        return EventListResponse(
            run_id=run_id,
            events=events,
            has_more=has_more,
        )
    except HTTPException:
        raise
    except Exception as e:
        # Check for database connection errors - return 503 for transient failures
        if is_database_connection_error(e):
            raise_database_unavailable(
                "event listing",
                e,
                run_id=run_id
            )
        # Log and return 500 for other errors
        log_sync_error(
            "Failed to list events",
            run_id=run_id,
            exc=e
        )
        raise HTTPException(
            status_code=500,
            detail=f"Database error during event listing: {str(e)}"
        )
