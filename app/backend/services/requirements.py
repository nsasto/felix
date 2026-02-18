"""
Requirement service layer for metadata updates and dependency management.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional
from uuid import UUID
import os
import json

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


def _resolve_project_id(project_id: str) -> str:
    if _is_uuid(project_id):
        return project_id
    dev_project_id = os.getenv("DEV_PROJECT_ID")
    if dev_project_id and _is_uuid(dev_project_id):
        return dev_project_id
    raise ValueError(
        f"Invalid project_id '{project_id}'. Expected UUID or DEV_PROJECT_ID env var."
    )


def _normalize_tags(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
            return parsed if isinstance(parsed, list) else []
        except json.JSONDecodeError:
            return []
    return []


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
        resolved_project_id = _resolve_project_id(project_id)
        requirement = await self._resolve_requirement(
            resolved_project_id, requirement_id_or_code
        )
        if not requirement:
            return {}

        requirement_id = requirement["id"]

        if field in {"title", "status", "priority"}:
            await self.requirements.update_field(requirement_id, field, value)
        elif field == "tags":
            await self.requirements.update_tags(requirement_id, value)
        elif field == "depends_on":
            await self._replace_dependencies(resolved_project_id, requirement_id, value)
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
        updated_at = record.get("updated_at")

        return {
            "id": record.get("code") or record["id"],
            "code": record.get("code"),
            "uuid": str(record["id"]),
            "title": record["title"],
            "spec_path": record["spec_path"],
            "status": record["status"],
            "priority": record["priority"],
            "tags": _normalize_tags(record.get("tags")),
            "depends_on": depends_on_codes,
            "updated_at": updated_at.isoformat() if updated_at else None,
            "commit_on_complete": record["commit_on_complete"],
            "has_plan": False,
        }

    async def get_requirement_record(
        self, project_id: str, requirement_id_or_code: str
    ) -> Optional[Dict[str, Any]]:
        return await self._resolve_requirement(project_id, requirement_id_or_code)

    async def list_requirements(self, project_id: str) -> List[Dict[str, Any]]:
        resolved_project_id = _resolve_project_id(project_id)
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
            values={"project_id": resolved_project_id},
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
            updated_at = record.get("updated_at")
            results.append(
                {
                    "id": record.get("code") or req_id,
                    "code": record.get("code"),
                    "uuid": str(req_id),
                    "title": record["title"],
                    "spec_path": record["spec_path"],
                    "status": record["status"],
                    "priority": record["priority"],
                    "tags": _normalize_tags(record.get("tags")),
                    "depends_on": deps_by_requirement.get(req_id, []),
                    "updated_at": updated_at.isoformat() if updated_at else None,
                    "commit_on_complete": record["commit_on_complete"],
                    "has_plan": False,
                }
            )

        return results

    async def update_content_from_spec(
        self,
        project_id: str,
        spec_path: str,
        content: str,
        author_id: Optional[str] = None,
        source: str = "spec_file",
    ) -> bool:
        resolved_project_id = _resolve_project_id(project_id)
        requirement = await self.requirements.get_by_spec_path(
            resolved_project_id, spec_path
        )
        if not requirement:
            return False

        requirement_id = requirement["id"]
        current_version_id = await self.content.get_current_version_id(requirement_id)
        new_version_id = await self.content.create_version(
            requirement_id=requirement_id,
            content=content,
            author_id=author_id,
            source=source,
            diff_from_id=current_version_id,
        )
        await self.content.upsert_content(
            requirement_id=requirement_id,
            content=content,
            current_version_id=new_version_id,
        )
        await self.requirements.touch_updated_at(requirement_id)
        return True

    async def update_content(
        self,
        project_id: str,
        requirement_id_or_code: str,
        content: str,
        author_id: Optional[str] = None,
        source: str = "api",
    ) -> bool:
        """Update requirement content by requirement ID or code."""
        resolved_project_id = _resolve_project_id(project_id)
        requirement = await self._resolve_requirement(
            resolved_project_id, requirement_id_or_code
        )
        if not requirement:
            return False

        requirement_id = requirement["id"]
        current_version_id = await self.content.get_current_version_id(requirement_id)
        new_version_id = await self.content.create_version(
            requirement_id=requirement_id,
            content=content,
            author_id=author_id,
            source=source,
            diff_from_id=current_version_id,
        )
        await self.content.upsert_content(
            requirement_id=requirement_id,
            content=content,
            current_version_id=new_version_id,
        )
        await self.requirements.touch_updated_at(requirement_id)
        return True

    async def get_content(
        self, project_id: str, requirement_id_or_code: str
    ) -> Optional[str]:
        resolved_project_id = _resolve_project_id(project_id)
        requirement = await self._resolve_requirement(
            resolved_project_id, requirement_id_or_code
        )
        if not requirement:
            return None

        row = await self.db.fetch_one(
            """
            SELECT content
            FROM requirement_content
            WHERE requirement_id = :requirement_id
            """,
            values={"requirement_id": requirement["id"]},
        )
        return row["content"] if row else None

    async def get_content_by_spec_path(
        self, project_id: str, spec_path: str
    ) -> Optional[str]:
        resolved_project_id = _resolve_project_id(project_id)
        requirement = await self.requirements.get_by_spec_path(
            resolved_project_id, spec_path
        )
        if not requirement:
            return None

        row = await self.db.fetch_one(
            """
            SELECT content
            FROM requirement_content
            WHERE requirement_id = :requirement_id
            """,
            values={"requirement_id": requirement["id"]},
        )
        return row["content"] if row else None

    async def _resolve_requirement(
        self, project_id: str, requirement_id_or_code: str
    ) -> Optional[Dict[str, Any]]:
        project_id = _resolve_project_id(project_id)
        if _is_uuid(requirement_id_or_code):
            return await self.requirements.get_by_id(project_id, requirement_id_or_code)
        return await self.requirements.get_by_code(project_id, requirement_id_or_code)

    async def _replace_dependencies(
        self,
        project_id: str,
        requirement_id: str,
        depends_on: List[str],
    ) -> None:
        project_id = _resolve_project_id(project_id)
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
            raise ValueError(f"Unknown dependency references: {', '.join(missing)}")

        depends_on_ids = list(resolved_codes.values()) + resolved_ids

        if requirement_id in depends_on_ids:
            raise ValueError("Dependency list cannot include itself.")

        await self.dependencies.replace_dependencies(requirement_id, depends_on_ids)
