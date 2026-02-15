"""
Project repository interfaces + Postgres implementation.
"""

from __future__ import annotations

import re
import uuid
from typing import Any, Dict, List, Optional, Protocol

from databases import Database


def _slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "project"


class IProjectRepository(Protocol):
    async def list_by_org(self, org_id: str) -> List[Dict[str, Any]]:
        ...

    async def get_by_id(self, org_id: str, project_id: str) -> Optional[Dict[str, Any]]:
        ...

    async def get_by_id_any(self, project_id: str) -> Optional[Dict[str, Any]]:
        ...

    async def get_by_path(self, org_id: str, path: str) -> Optional[Dict[str, Any]]:
        ...

    async def create_project(
        self,
        org_id: str,
        name: str,
        path: str,
        description: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        ...

    async def update_project(
        self,
        org_id: str,
        project_id: str,
        name: Optional[str],
        path: Optional[str],
    ) -> Optional[Dict[str, Any]]:
        ...

    async def delete_project(self, org_id: str, project_id: str) -> bool:
        ...


class PostgresProjectRepository:
    def __init__(self, db: Database) -> None:
        self.db = db

    async def list_by_org(self, org_id: str) -> List[Dict[str, Any]]:
        rows = await self.db.fetch_all(
            """
            SELECT *
            FROM projects
            WHERE org_id = :org_id AND path IS NOT NULL
            ORDER BY created_at DESC
            """,
            values={"org_id": org_id},
        )
        return [dict(row) for row in rows]

    async def get_by_id(self, org_id: str, project_id: str) -> Optional[Dict[str, Any]]:
        row = await self.db.fetch_one(
            """
            SELECT *
            FROM projects
            WHERE org_id = :org_id AND id = :id
            """,
            values={"org_id": org_id, "id": project_id},
        )
        return dict(row) if row else None

    async def get_by_id_any(self, project_id: str) -> Optional[Dict[str, Any]]:
        row = await self.db.fetch_one(
            "SELECT * FROM projects WHERE id = :id",
            values={"id": project_id},
        )
        return dict(row) if row else None

    async def get_by_path(self, org_id: str, path: str) -> Optional[Dict[str, Any]]:
        row = await self.db.fetch_one(
            """
            SELECT *
            FROM projects
            WHERE org_id = :org_id AND path = :path
            """,
            values={"org_id": org_id, "path": path},
        )
        return dict(row) if row else None

    async def _find_unique_slug(self, org_id: str, base: str) -> str:
        slug = _slugify(base)
        existing = await self.db.fetch_one(
            """
            SELECT 1
            FROM projects
            WHERE org_id = :org_id AND slug = :slug
            """,
            values={"org_id": org_id, "slug": slug},
        )
        if not existing:
            return slug

        suffix = uuid.uuid4().hex[:6]
        return f"{slug}-{suffix}"

    async def create_project(
        self,
        org_id: str,
        name: str,
        path: str,
        description: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        existing = await self.get_by_path(org_id, path)
        if existing:
            if name and name != existing.get("name"):
                slug = await self._find_unique_slug(org_id, name)
                row = await self.db.fetch_one(
                    """
                    UPDATE projects
                    SET name = :name, slug = :slug, updated_at = NOW()
                    WHERE id = :id
                    RETURNING *
                    """,
                    values={"name": name, "slug": slug, "id": existing["id"]},
                )
                return dict(row) if row else existing
            return existing

        slug = await self._find_unique_slug(org_id, name)
        row = await self.db.fetch_one(
            """
            INSERT INTO projects (org_id, name, slug, description, metadata, path)
            VALUES (:org_id, :name, :slug, :description, :metadata::jsonb, :path)
            RETURNING *
            """,
            values={
                "org_id": org_id,
                "name": name,
                "slug": slug,
                "description": description,
                "metadata": metadata or {},
                "path": path,
            },
        )
        return dict(row) if row else {}

    async def update_project(
        self,
        org_id: str,
        project_id: str,
        name: Optional[str],
        path: Optional[str],
    ) -> Optional[Dict[str, Any]]:
        existing = await self.get_by_id(org_id, project_id)
        if not existing:
            return None

        updates: Dict[str, Any] = {"id": project_id, "org_id": org_id}
        assignments = []

        if name is not None:
            clean_name = name.strip()
            if not clean_name:
                updates["name"] = None
                assignments.append("name = :name")
            else:
                slug = await self._find_unique_slug(org_id, clean_name)
                updates["name"] = clean_name
                updates["slug"] = slug
                assignments.append("name = :name")
                assignments.append("slug = :slug")

        if path is not None:
            existing_path = await self.db.fetch_one(
                """
                SELECT id
                FROM projects
                WHERE org_id = :org_id AND path = :path AND id <> :id
                """,
                values={"org_id": org_id, "path": path, "id": project_id},
            )
            if existing_path:
                raise ValueError("Path is already registered for another project.")
            updates["path"] = path
            assignments.append("path = :path")

        if not assignments:
            return existing

        query = f"""
            UPDATE projects
            SET {", ".join(assignments)}, updated_at = NOW()
            WHERE id = :id AND org_id = :org_id
            RETURNING *
        """
        row = await self.db.fetch_one(query, values=updates)
        return dict(row) if row else None

    async def delete_project(self, org_id: str, project_id: str) -> bool:
        row = await self.db.fetch_one(
            """
            DELETE FROM projects
            WHERE id = :id AND org_id = :org_id
            RETURNING 1
            """,
            values={"id": project_id, "org_id": org_id},
        )
        return row is not None
