"""
Settings repository interfaces + Postgres implementation.
"""

from __future__ import annotations

import json
from typing import Any, Dict, Optional, Protocol

from databases import Database


class ISettingsRepository(Protocol):
    async def get(self, scope_type: str, scope_id: str) -> Optional[Dict[str, Any]]:
        ...

    async def upsert(
        self,
        scope_type: str,
        scope_id: str,
        config: Dict[str, Any],
        schema_version: int = 1,
    ) -> Dict[str, Any]:
        ...


class PostgresSettingsRepository:
    def __init__(self, db: Database) -> None:
        self.db = db

    async def get(self, scope_type: str, scope_id: str) -> Optional[Dict[str, Any]]:
        row = await self.db.fetch_one(
            """
            SELECT *
            FROM settings
            WHERE scope_type = :scope_type AND scope_id = :scope_id
            """,
            values={"scope_type": scope_type, "scope_id": scope_id},
        )
        return dict(row) if row else None

    async def upsert(
        self,
        scope_type: str,
        scope_id: str,
        config: Dict[str, Any],
        schema_version: int = 1,
    ) -> Dict[str, Any]:
        payload = json.dumps(config)
        row = await self.db.fetch_one(
            """
            INSERT INTO settings (scope_type, scope_id, config, schema_version)
            VALUES (:scope_type, :scope_id, CAST(:config AS JSONB), :schema_version)
            ON CONFLICT (scope_type, scope_id)
            DO UPDATE SET
              config = EXCLUDED.config,
              schema_version = EXCLUDED.schema_version,
              updated_at = NOW()
            RETURNING *
            """,
            values={
                "scope_type": scope_type,
                "scope_id": scope_id,
                "config": payload,
                "schema_version": schema_version,
            },
        )
        return dict(row) if row else {}
