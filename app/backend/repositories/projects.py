"""
Project repository interfaces + Postgres implementation.
"""

from __future__ import annotations

import json
import re
import uuid
from typing import Any, Dict, List, Optional, Protocol

from databases import Database


def _slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "project"


class IProjectRepository(Protocol):
    async def list_by_org(self, org_id: str) -> List[Dict[str, Any]]: ...

    async def get_by_id(
        self, org_id: str, project_id: str
    ) -> Optional[Dict[str, Any]]: ...

    async def get_by_id_any(self, project_id: str) -> Optional[Dict[str, Any]]: ...

    async def get_by_git_url(
        self, org_id: str, git_url: str
    ) -> Optional[Dict[str, Any]]: ...

    async def create_project(
        self,
        org_id: str,
        name: str,
        git_url: str,
        description: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]: ...

    async def update_project(
        self,
        org_id: str,
        project_id: str,
        name: Optional[str],
        git_url: Optional[str] = None,
    ) -> Optional[Dict[str, Any]]: ...

    async def delete_project(self, org_id: str, project_id: str) -> bool: ...


class PostgresProjectRepository:
    def __init__(self, db: Database) -> None:
        self.db = db

    async def list_by_org(self, org_id: str) -> List[Dict[str, Any]]:
        rows = await self.db.fetch_all(
            """
            SELECT *
            FROM projects
            WHERE org_id = :org_id
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

    async def get_by_git_url(
        self, org_id: str, git_url: str
    ) -> Optional[Dict[str, Any]]:
        row = await self.db.fetch_one(
            """
            SELECT *
            FROM projects
            WHERE org_id = :org_id AND git_url = :git_url
            """,
            values={"org_id": org_id, "git_url": git_url},
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
        git_url: str,
        description: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        existing = await self.get_by_git_url(org_id, git_url)
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
        metadata_payload = json.dumps(metadata or {})
        row = await self.db.fetch_one(
            """
            INSERT INTO projects (org_id, name, slug, description, metadata, git_url)
            VALUES (:org_id, :name, :slug, :description, CAST(:metadata AS JSONB), :git_url)
            RETURNING *
            """,
            values={
                "org_id": org_id,
                "name": name,
                "slug": slug,
                "description": description,
                "metadata": metadata_payload,
                "git_url": git_url,
            },
        )
        return dict(row) if row else {}

    async def update_project(
        self,
        org_id: str,
        project_id: str,
        name: Optional[str],
        git_url: Optional[str] = None,
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

        if git_url is not None:
            existing_git = await self.db.fetch_one(
                """
                SELECT id
                FROM projects
                WHERE org_id = :org_id AND git_url = :git_url AND id <> :id
                """,
                values={"org_id": org_id, "git_url": git_url, "id": project_id},
            )
            if existing_git:
                raise ValueError("Git URL is already registered for another project.")
            updates["git_url"] = git_url
            assignments.append("git_url = :git_url")

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
