"""
API Key repository interfaces + Postgres implementation.
"""

from __future__ import annotations

import hashlib
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Protocol

from databases import Database


def hash_api_key(key: str) -> str:
    """
    Hash an API key using SHA256.

    This must match the hashing used in scripts/generate-sync-key.py.

    Args:
        key: Plain-text API key

    Returns:
        Hex-encoded SHA256 hash
    """
    return hashlib.sha256(key.encode("utf-8")).hexdigest()


class IApiKeyRepository(Protocol):
    """Protocol defining API key repository operations."""

    async def get_by_key_hash(self, key_hash: str) -> Optional[Dict[str, Any]]:
        """Get API key by its hash."""
        ...

    async def get_by_id(self, key_id: str) -> Optional[Dict[str, Any]]:
        """Get API key by its ID."""
        ...

    async def list_by_project(self, project_id: str) -> List[Dict[str, Any]]:
        """List all API keys for a project."""
        ...

    async def create_key(
        self,
        project_id: str,
        key_hash: str,
        name: Optional[str] = None,
        expires_at: Optional[datetime] = None,
    ) -> Dict[str, Any]:
        """Create a new API key."""
        ...

    async def revoke_key(self, key_id: str) -> bool:
        """Revoke (delete) an API key by ID."""
        ...

    async def update_last_used(self, key_id: str) -> None:
        """Update the last_used_at timestamp for a key."""
        ...


class PostgresApiKeyRepository:
    """Postgres implementation of API key repository."""

    def __init__(self, db: Database) -> None:
        self.db = db

    async def get_by_key_hash(self, key_hash: str) -> Optional[Dict[str, Any]]:
        """
        Get API key by its hash.

        Returns None if key not found.
        """
        row = await self.db.fetch_one(
            """
            SELECT id, project_id, name, expires_at, last_used_at, created_at
            FROM api_keys
            WHERE key_hash = :key_hash
            """,
            values={"key_hash": key_hash},
        )
        return dict(row) if row else None

    async def get_by_id(self, key_id: str) -> Optional[Dict[str, Any]]:
        """Get API key by its ID."""
        row = await self.db.fetch_one(
            """
            SELECT id, project_id, name, expires_at, last_used_at, created_at
            FROM api_keys
            WHERE id = :key_id
            """,
            values={"key_id": key_id},
        )
        return dict(row) if row else None

    async def list_by_project(self, project_id: str) -> List[Dict[str, Any]]:
        """
        List all API keys for a project.

        Returns keys ordered by creation date (newest first).
        Does not include the key_hash in the result for security.
        """
        rows = await self.db.fetch_all(
            """
            SELECT id, project_id, name, expires_at, last_used_at, created_at
            FROM api_keys
            WHERE project_id = :project_id
            ORDER BY created_at DESC
            """,
            values={"project_id": project_id},
        )
        return [dict(row) for row in rows]

    async def create_key(
        self,
        project_id: str,
        key_hash: str,
        name: Optional[str] = None,
        expires_at: Optional[datetime] = None,
    ) -> Dict[str, Any]:
        """
        Create a new API key.

        Args:
            project_id: UUID of the project this key belongs to
            key_hash: SHA256 hash of the raw API key
            name: Optional human-readable name for the key
            expires_at: Optional expiration datetime (timezone-aware)

        Returns:
            Dictionary with the created key's data
        """
        row = await self.db.fetch_one(
            """
            INSERT INTO api_keys (project_id, key_hash, name, expires_at)
            VALUES (:project_id, :key_hash, :name, :expires_at)
            RETURNING id, project_id, name, expires_at, last_used_at, created_at
            """,
            values={
                "project_id": project_id,
                "key_hash": key_hash,
                "name": name,
                "expires_at": expires_at,
            },
        )
        return dict(row) if row else {}

    async def revoke_key(self, key_id: str) -> bool:
        """
        Revoke (delete) an API key by ID.

        Returns True if key was deleted, False if not found.
        """
        result = await self.db.execute(
            """
            DELETE FROM api_keys
            WHERE id = :key_id
            """,
            values={"key_id": key_id},
        )
        # execute() returns the number of rows affected (or None in some drivers)
        return result is not None and result > 0

    async def update_last_used(self, key_id: str) -> None:
        """Update the last_used_at timestamp for a key to NOW()."""
        await self.db.execute(
            """
            UPDATE api_keys
            SET last_used_at = NOW()
            WHERE id = :key_id
            """,
            values={"key_id": key_id},
        )
