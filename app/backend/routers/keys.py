"""
Felix Backend - API Key Management
Handles project-scoped API key generation, listing, and revocation.
"""

import secrets
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from databases import Database
from fastapi import APIRouter, Depends, HTTPException, Header
from pydantic import BaseModel, Field

from auth import get_current_user
from database.db import get_db
from repositories.api_keys import PostgresApiKeyRepository, hash_api_key
from repositories.projects import PostgresProjectRepository


router = APIRouter(prefix="/api/projects/{project_id}/keys", tags=["api-keys"])
global_keys_router = APIRouter(prefix="/api/keys", tags=["api-keys"])


# ============================================================================
# REQUEST/RESPONSE MODELS
# ============================================================================


class ApiKeyCreate(BaseModel):
    """Request body for creating a new API key."""

    name: Optional[str] = Field(
        None,
        description="Human-readable name for the key (e.g., 'CI/CD Pipeline', 'Dev Laptop')",
        max_length=100,
    )
    expires_days: Optional[int] = Field(
        None,
        description="Number of days until the key expires (None = never expires)",
        ge=1,
        le=365,
    )


class ApiKeyInfo(BaseModel):
    """Information about an API key (used in list responses)."""

    id: str = Field(..., description="UUID of the API key")
    project_id: str = Field(..., description="Project this key belongs to")
    name: Optional[str] = Field(None, description="Human-readable name")
    created_at: datetime = Field(..., description="When the key was created")
    last_used_at: Optional[datetime] = Field(None, description="Last time key was used")
    expires_at: Optional[datetime] = Field(None, description="When the key expires")


class ApiKeyCreated(BaseModel):
    """Response after creating a new API key (includes plain-text key)."""

    id: str = Field(..., description="UUID of the API key")
    project_id: str = Field(..., description="Project this key belongs to")
    name: Optional[str] = Field(None, description="Human-readable name")
    key: str = Field(
        ...,
        description="Plain-text API key (fsk_...) - SAVE THIS! It cannot be retrieved again.",
    )
    created_at: datetime = Field(..., description="When the key was created")
    expires_at: Optional[datetime] = Field(None, description="When the key expires")


class ApiKeyList(BaseModel):
    """Response containing list of API keys."""

    keys: List[ApiKeyInfo] = Field(..., description="List of API keys")
    count: int = Field(..., description="Total number of keys")


class ApiKeyRevoked(BaseModel):
    """Response after revoking an API key."""

    id: str = Field(..., description="UUID of the revoked key")
    status: str = Field(..., description="Always 'revoked'")


class ApiKeyValidate(BaseModel):
    """Response from validating an API key."""

    project_id: str = Field(..., description="Project this key belongs to")
    project_name: Optional[str] = Field(None, description="Human-readable project name")
    org_id: str = Field(..., description="Organization ID")
    expires_at: Optional[datetime] = Field(None, description="When the key expires")


# ============================================================================
# GLOBAL API KEY ENDPOINTS (no project_id in path)
# ============================================================================


@global_keys_router.get("/validate", response_model=ApiKeyValidate)
async def validate_api_key(
    authorization: str = Header(...),
    db: Database = Depends(get_db),
):
    """
    Validate an API key and return information about it.

    This endpoint is used by CLI setup to verify a key is valid and show
    which project it grants access to.

    Args:
        authorization: Bearer token (e.g., "Bearer fsk_...")
        db: Database connection

    Returns:
        Information about the key and project

    Raises:
        HTTPException 401: If key is invalid or expired
    """
    # Parse Authorization header
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Invalid Authorization header format. Use: Bearer fsk_...",
        )

    plain_key = authorization[7:]  # Strip "Bearer "
    key_hash = hash_api_key(plain_key)

    # Look up key
    api_key_repo = PostgresApiKeyRepository(db)
    key_record = await api_key_repo.get_by_key_hash(key_hash)

    if not key_record:
        raise HTTPException(
            status_code=401,
            detail="Invalid API key",
        )

    # Check if expired
    if key_record.get("expires_at"):
        expires_at = key_record["expires_at"]
        if expires_at < datetime.now(timezone.utc):
            raise HTTPException(
                status_code=401,
                detail="API key has expired",
            )

    # Fetch project details
    project_repo = PostgresProjectRepository(db)
    project_id = str(key_record["project_id"])
    # We don't have org_id in the project fetch, so let's get it from the query
    project_row = await db.fetch_one(
        """
        SELECT p.id, p.name, p.org_id
        FROM projects p
        WHERE p.id = :project_id
        """,
        values={"project_id": project_id},
    )

    if not project_row:
        raise HTTPException(
            status_code=401,
            detail="API key references non-existent project",
        )

    return ApiKeyValidate(
        project_id=str(project_row["id"]),
        project_name=project_row.get("name"),
        org_id=str(project_row["org_id"]),
        expires_at=key_record.get("expires_at"),
    )


# ============================================================================
# HELPER FUNCTIONS
# ============================================================================


def generate_api_key() -> str:
    """
    Generate a new API key with fsk_ prefix (Felix Sync Key).

    Format: fsk_{32 chars}
    Total length: 36 characters
    Security: 32 bytes of randomness = 256 bits of entropy

    Returns:
        Newly generated API key (plain-text)
    """
    random_bytes = secrets.token_bytes(32)
    key_suffix = random_bytes.hex()  # 64 hex chars
    return f"fsk_{key_suffix}"


# ============================================================================
# API KEY ENDPOINTS
# ============================================================================


@router.post("", response_model=ApiKeyCreated, status_code=201)
async def create_api_key(
    project_id: str,
    body: ApiKeyCreate,
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Generate a new API key for a project.

    The returned plain-text key is shown only once and cannot be retrieved later.
    Store it securely in your CLI configuration or CI/CD secrets.

    Args:
        project_id: UUID of the project to create a key for
        body: Key creation parameters (name, expiration)
        db: Database connection
        user: Current authenticated user

    Returns:
        Created key with plain-text value (store it!)

    Raises:
        HTTPException 404: If project not found or user has no access
        HTTPException 500: On database error
    """
    project_repo = PostgresProjectRepository(db)
    api_key_repo = PostgresApiKeyRepository(db)

    # Verify project exists and user has access
    project = await project_repo.get_by_id(user["org_id"], project_id)
    if not project:
        raise HTTPException(
            status_code=404,
            detail=f"Project not found or you do not have access to it: {project_id}",
        )

    # Generate new API key
    plain_key = generate_api_key()
    key_hash = hash_api_key(plain_key)

    # Calculate expiration if requested
    expires_at = None
    if body.expires_days:
        from datetime import timedelta

        expires_at = datetime.now(timezone.utc) + timedelta(days=body.expires_days)

    # Create key in database
    try:
        key_record = await api_key_repo.create_key(
            project_id=project_id,
            key_hash=key_hash,
            name=body.name,
            expires_at=expires_at,
        )

        return ApiKeyCreated(
            id=str(key_record["id"]),
            project_id=str(key_record["project_id"]),
            name=key_record.get("name"),
            key=plain_key,  # Only time we return the plain key!
            created_at=key_record["created_at"],
            expires_at=key_record.get("expires_at"),
        )
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Failed to create API key: {str(e)}"
        )


@router.get("", response_model=ApiKeyList)
async def list_api_keys(
    project_id: str,
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    List all API keys for a project.

    Returns metadata about each key (ID, name, created/last used timestamps).
    Does NOT return the plain-text keys (they cannot be retrieved after creation).

    Args:
        project_id: UUID of the project to list keys for
        db: Database connection
        user: Current authenticated user

    Returns:
        List of API key metadata

    Raises:
        HTTPException 404: If project not found or user has no access
        HTTPException 500: On database error
    """
    project_repo = PostgresProjectRepository(db)
    api_key_repo = PostgresApiKeyRepository(db)

    # Verify project exists and user has access
    project = await project_repo.get_by_id(user["org_id"], project_id)
    if not project:
        raise HTTPException(
            status_code=404,
            detail=f"Project not found or you do not have access to it: {project_id}",
        )

    # List keys
    try:
        keys = await api_key_repo.list_by_project(project_id)

        return ApiKeyList(
            keys=[
                ApiKeyInfo(
                    id=str(key["id"]),
                    project_id=str(key["project_id"]),
                    name=key.get("name"),
                    created_at=key["created_at"],
                    last_used_at=key.get("last_used_at"),
                    expires_at=key.get("expires_at"),
                )
                for key in keys
            ],
            count=len(keys),
        )
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Failed to list API keys: {str(e)}"
        )


@router.delete("/{key_id}", response_model=ApiKeyRevoked)
async def revoke_api_key(
    project_id: str,
    key_id: str,
    db: Database = Depends(get_db),
    user: Dict[str, Any] = Depends(get_current_user),
):
    """
    Revoke (delete) an API key.

    Once revoked, the key cannot be used for authentication and cannot be recovered.

    Args:
        project_id: UUID of the project owning the key
        key_id: UUID of the API key to revoke
        db: Database connection
        user: Current authenticated user

    Returns:
        Revocation confirmation

    Raises:
        HTTPException 404: If project or key not found, or user has no access
        HTTPException 500: On database error
    """
    project_repo = PostgresProjectRepository(db)
    api_key_repo = PostgresApiKeyRepository(db)

    # Verify project exists and user has access
    project = await project_repo.get_by_id(user["org_id"], project_id)
    if not project:
        raise HTTPException(
            status_code=404,
            detail=f"Project not found or you do not have access to it: {project_id}",
        )

    # Verify key exists and belongs to this project
    key_record = await api_key_repo.get_by_id(key_id)
    if not key_record or str(key_record["project_id"]) != project_id:
        raise HTTPException(
            status_code=404,
            detail=f"API key not found or does not belong to this project: {key_id}",
        )

    # Revoke the key
    try:
        success = await api_key_repo.revoke_key(key_id)
        if not success:
            raise HTTPException(
                status_code=404,
                detail=f"API key not found: {key_id}",
            )

        return ApiKeyRevoked(id=key_id, status="revoked")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Failed to revoke API key: {str(e)}"
        )
