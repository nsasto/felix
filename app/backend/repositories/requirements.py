"""
Requirement repository interfaces + Postgres implementations.
"""

from __future__ import annotations

import json
from typing import Any, Dict, List, Optional, Protocol

from databases import Database


class IRequirementRepository(Protocol):
    async def get_by_id(
        self, project_id: str, requirement_id: str
    ) -> Optional[Dict[str, Any]]:
        ...

    async def get_by_code(
        self, project_id: str, code: str
    ) -> Optional[Dict[str, Any]]:
        ...

    async def update_field(
        self, requirement_id: str, field: str, value: Any
    ) -> None:
        ...

    async def update_tags(self, requirement_id: str, tags: List[str]) -> None:
        ...

    async def resolve_codes(
        self, project_id: str, codes: List[str]
    ) -> Dict[str, str]:
        ...

    async def resolve_ids(
        self, ids: List[str]
    ) -> List[str]:
        ...


class IRequirementContentRepository(Protocol):
    async def create_version(
        self,
        requirement_id: str,
        content: str,
        author_id: Optional[str],
        source: str,
        diff_from_id: Optional[str],
    ) -> str:
        ...

    async def upsert_content(
        self,
        requirement_id: str,
        content: str,
        current_version_id: str,
    ) -> None:
        ...


class IRequirementDependencyRepository(Protocol):
    async def list_depends_on_codes(self, requirement_id: str) -> List[str]:
        ...

    async def replace_dependencies(
        self, requirement_id: str, depends_on_ids: List[str]
    ) -> None:
        ...


class PostgresRequirementRepository:
    def __init__(self, db: Database) -> None:
        self.db = db

    async def get_by_id(
        self, project_id: str, requirement_id: str
    ) -> Optional[Dict[str, Any]]:
        row = await self.db.fetch_one(
            "SELECT * FROM requirements WHERE id = :id AND project_id = :project_id",
            values={"id": requirement_id, "project_id": project_id},
        )
        return dict(row) if row else None

    async def get_by_code(
        self, project_id: str, code: str
    ) -> Optional[Dict[str, Any]]:
        row = await self.db.fetch_one(
            """
            SELECT * FROM requirements
            WHERE project_id = :project_id AND code = :code
            """,
            values={"project_id": project_id, "code": code},
        )
        return dict(row) if row else None

    async def update_field(
        self, requirement_id: str, field: str, value: Any
    ) -> None:
        allowed_fields = {"title", "status", "priority"}
        if field not in allowed_fields:
            raise ValueError(f"Unsupported field update: {field}")

        query = f"UPDATE requirements SET {field} = :value WHERE id = :id"
        await self.db.execute(query=query, values={"id": requirement_id, "value": value})

    async def update_tags(self, requirement_id: str, tags: List[str]) -> None:
        tags_json = json.dumps(tags)
        await self.db.execute(
            """
            UPDATE requirements
            SET metadata = jsonb_set(
                COALESCE(metadata, '{}'::jsonb),
                '{tags}',
                :tags::jsonb,
                true
            )
            WHERE id = :id
            """,
            values={"id": requirement_id, "tags": tags_json},
        )

    async def resolve_codes(
        self, project_id: str, codes: List[str]
    ) -> Dict[str, str]:
        if not codes:
            return {}

        rows = await self.db.fetch_all(
            """
            SELECT id, code
            FROM requirements
            WHERE project_id = :project_id AND code = ANY(:codes)
            """,
            values={"project_id": project_id, "codes": codes},
        )
        return {row["code"]: row["id"] for row in rows}

    async def resolve_ids(self, ids: List[str]) -> List[str]:
        if not ids:
            return []

        rows = await self.db.fetch_all(
            """
            SELECT id
            FROM requirements
            WHERE id = ANY(:ids)
            """,
            values={"ids": ids},
        )
        return [row["id"] for row in rows]


class PostgresRequirementContentRepository:
    def __init__(self, db: Database) -> None:
        self.db = db

    async def create_version(
        self,
        requirement_id: str,
        content: str,
        author_id: Optional[str],
        source: str,
        diff_from_id: Optional[str],
    ) -> str:
        row = await self.db.fetch_one(
            """
            INSERT INTO requirement_versions (
                requirement_id, content, author_id, source, diff_from_id
            )
            VALUES (:requirement_id, :content, :author_id, :source, :diff_from_id)
            RETURNING id
            """,
            values={
                "requirement_id": requirement_id,
                "content": content,
                "author_id": author_id,
                "source": source,
                "diff_from_id": diff_from_id,
            },
        )
        return row["id"]

    async def upsert_content(
        self,
        requirement_id: str,
        content: str,
        current_version_id: str,
    ) -> None:
        await self.db.execute(
            """
            INSERT INTO requirement_content (
                requirement_id, content, current_version_id
            )
            VALUES (:requirement_id, :content, :current_version_id)
            ON CONFLICT (requirement_id)
            DO UPDATE SET
                content = EXCLUDED.content,
                current_version_id = EXCLUDED.current_version_id
            """,
            values={
                "requirement_id": requirement_id,
                "content": content,
                "current_version_id": current_version_id,
            },
        )


class PostgresRequirementDependencyRepository:
    def __init__(self, db: Database) -> None:
        self.db = db

    async def list_depends_on_codes(self, requirement_id: str) -> List[str]:
        rows = await self.db.fetch_all(
            """
            SELECT r.code, r.id
            FROM requirement_dependencies d
            JOIN requirements r ON r.id = d.depends_on_id
            WHERE d.requirement_id = :requirement_id
            ORDER BY r.code NULLS LAST, r.id
            """,
            values={"requirement_id": requirement_id},
        )
        return [row["code"] or row["id"] for row in rows]

    async def replace_dependencies(
        self, requirement_id: str, depends_on_ids: List[str]
    ) -> None:
        async with self.db.transaction():
            await self.db.execute(
                "DELETE FROM requirement_dependencies WHERE requirement_id = :id",
                values={"id": requirement_id},
            )
            if not depends_on_ids:
                return

            values = [
                {"requirement_id": requirement_id, "depends_on_id": dep_id}
                for dep_id in depends_on_ids
            ]
            await self.db.execute_many(
                """
                INSERT INTO requirement_dependencies (requirement_id, depends_on_id)
                VALUES (:requirement_id, :depends_on_id)
                """,
                values=values,
            )
