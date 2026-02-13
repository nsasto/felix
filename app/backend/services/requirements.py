"""
Requirement service layer for metadata updates and dependency management.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional
from uuid import UUID

from databases import Database

from repositories.requirements import (
    PostgresRequirementRepository,
    PostgresRequirementContentRepository,
    PostgresRequirementDependencyRepository,
)


def _is_uuid(value: str) -> bool:
    try:
        UUID(value)
        return True
    except (ValueError, TypeError):
        return False


class RequirementService:
    def __init__(self, db: Database) -> None:
        self.db = db
        self.requirements = PostgresRequirementRepository(db)
        self.content = PostgresRequirementContentRepository(db)
        self.dependencies = PostgresRequirementDependencyRepository(db)

    async def update_metadata(
        self,
        project_id: str,
        requirement_id_or_code: str,
        field: str,
        value: Any,
    ) -> Dict[str, Any]:
        requirement = await self._resolve_requirement(
            project_id, requirement_id_or_code
        )
        if not requirement:
            return {}

        requirement_id = requirement["id"]

        if field in {"title", "status", "priority"}:
            await self.requirements.update_field(requirement_id, field, value)
        elif field == "tags":
            await self.requirements.update_tags(requirement_id, value)
        elif field == "depends_on":
            await self._replace_dependencies(project_id, requirement_id, value)
        else:
            raise ValueError(f"Unsupported metadata field: {field}")

        return await self.get_requirement_response(requirement_id)

    async def get_requirement_response(self, requirement_id: str) -> Dict[str, Any]:
        row = await self.db.fetch_one(
            """
            SELECT
                r.*,
                COALESCE(r.metadata->'tags', '[]'::jsonb) AS tags,
                COALESCE((r.metadata->>'commit_on_complete')::boolean, true) AS commit_on_complete
            FROM requirements r
            WHERE r.id = :id
            """,
            values={"id": requirement_id},
        )
        if not row:
            return {}

        depends_on_codes = await self.dependencies.list_depends_on_codes(requirement_id)
        record = dict(row)

        return {
            "id": record.get("code") or record["id"],
            "title": record["title"],
            "spec_path": record["spec_path"],
            "status": record["status"],
            "priority": record["priority"],
            "tags": record["tags"] or [],
            "depends_on": depends_on_codes,
            "updated_at": record["updated_at"],
            "commit_on_complete": record["commit_on_complete"],
            "has_plan": False,
        }

    async def get_requirement_record(
        self, project_id: str, requirement_id_or_code: str
    ) -> Optional[Dict[str, Any]]:
        return await self._resolve_requirement(project_id, requirement_id_or_code)

    async def list_requirements(self, project_id: str) -> List[Dict[str, Any]]:
        rows = await self.db.fetch_all(
            """
            SELECT
                r.*,
                COALESCE(r.metadata->'tags', '[]'::jsonb) AS tags,
                COALESCE((r.metadata->>'commit_on_complete')::boolean, true) AS commit_on_complete
            FROM requirements r
            WHERE r.project_id = :project_id
            ORDER BY r.code NULLS LAST, r.created_at
            """,
            values={"project_id": project_id},
        )
        if not rows:
            return []

        requirement_ids = [row["id"] for row in rows]
        dependency_rows = await self.db.fetch_all(
            """
            SELECT d.requirement_id, r.code, r.id
            FROM requirement_dependencies d
            JOIN requirements r ON r.id = d.depends_on_id
            WHERE d.requirement_id = ANY(:requirement_ids)
            ORDER BY r.code NULLS LAST, r.id
            """,
            values={"requirement_ids": requirement_ids},
        )

        deps_by_requirement: Dict[str, List[str]] = {}
        for dep in dependency_rows:
            deps_by_requirement.setdefault(dep["requirement_id"], []).append(
                dep["code"] or dep["id"]
            )

        results: List[Dict[str, Any]] = []
        for row in rows:
            record = dict(row)
            req_id = record["id"]
            results.append(
                {
                    "id": record.get("code") or req_id,
                    "title": record["title"],
                    "spec_path": record["spec_path"],
                    "status": record["status"],
                    "priority": record["priority"],
                    "tags": record["tags"] or [],
                    "depends_on": deps_by_requirement.get(req_id, []),
                    "updated_at": record["updated_at"],
                    "commit_on_complete": record["commit_on_complete"],
                    "has_plan": False,
                }
            )

        return results

    async def _resolve_requirement(
        self, project_id: str, requirement_id_or_code: str
    ) -> Optional[Dict[str, Any]]:
        if _is_uuid(requirement_id_or_code):
            return await self.requirements.get_by_id(
                project_id, requirement_id_or_code
            )
        return await self.requirements.get_by_code(project_id, requirement_id_or_code)

    async def _replace_dependencies(
        self,
        project_id: str,
        requirement_id: str,
        depends_on: List[str],
    ) -> None:
        depends_on = depends_on or []
        if not depends_on:
            await self.dependencies.replace_dependencies(requirement_id, [])
            return

        codes = [value for value in depends_on if not _is_uuid(value)]
        ids = [value for value in depends_on if _is_uuid(value)]

        resolved_codes = await self.requirements.resolve_codes(project_id, codes)
        resolved_ids = await self.requirements.resolve_ids(ids)

        missing_codes = sorted(set(codes) - set(resolved_codes.keys()))
        missing_ids = sorted(set(ids) - set(resolved_ids))

        if missing_codes or missing_ids:
            missing = missing_codes + missing_ids
            raise ValueError(
                f"Unknown dependency references: {', '.join(missing)}"
            )

        depends_on_ids = list(resolved_codes.values()) + resolved_ids

        if requirement_id in depends_on_ids:
            raise ValueError("Dependency list cannot include itself.")

        await self.dependencies.replace_dependencies(requirement_id, depends_on_ids)
