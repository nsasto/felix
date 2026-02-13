"""
Tests for requirement repositories and service wiring.
"""

from typing import Any, Dict, List, Optional
from unittest.mock import AsyncMock, MagicMock

import pytest

from repositories.requirements import (
    PostgresRequirementRepository,
    PostgresRequirementContentRepository,
    PostgresRequirementDependencyRepository,
)
from services.requirements import RequirementService


class FakeDatabase:
    def __init__(
        self,
        fetch_one_result: Optional[Dict[str, Any]] = None,
        fetch_all_result: Optional[List[Dict[str, Any]]] = None,
    ) -> None:
        self.fetch_one_result = fetch_one_result
        self.fetch_all_result = fetch_all_result or []
        self.last_query: Optional[str] = None
        self.last_values: Optional[Dict[str, Any]] = None
        self.last_many_values: Optional[List[Dict[str, Any]]] = None

    async def fetch_one(self, query: str, values: Dict[str, Any] | None = None):
        self.last_query = query
        self.last_values = values
        return self.fetch_one_result

    async def fetch_all(self, query: str, values: Dict[str, Any] | None = None):
        self.last_query = query
        self.last_values = values
        return self.fetch_all_result

    async def execute(self, query: str, values: Dict[str, Any] | None = None):
        self.last_query = query
        self.last_values = values
        return None

    async def execute_many(self, query: str, values: List[Dict[str, Any]]):
        self.last_query = query
        self.last_many_values = values
        return None

    def transaction(self):
        class _Transaction:
            async def __aenter__(self_inner):
                return self_inner

            async def __aexit__(self_inner, exc_type, exc, tb):
                return False

        return _Transaction()


@pytest.mark.asyncio
async def test_requirements_repo_get_by_id_filters_project():
    db = FakeDatabase(fetch_one_result={"id": "req-1"})
    repo = PostgresRequirementRepository(db)

    result = await repo.get_by_id("proj-1", "req-1")

    assert result == {"id": "req-1"}
    assert "project_id" in (db.last_values or {})


@pytest.mark.asyncio
async def test_requirements_repo_update_tags_serializes_json():
    db = FakeDatabase()
    repo = PostgresRequirementRepository(db)

    await repo.update_tags("req-1", ["alpha", "beta"])

    assert db.last_values is not None
    assert db.last_values["id"] == "req-1"
    assert db.last_values["tags"] == '["alpha", "beta"]'


@pytest.mark.asyncio
async def test_requirements_repo_resolve_codes_returns_mapping():
    db = FakeDatabase(
        fetch_all_result=[
            {"id": "req-1", "code": "S-0001"},
            {"id": "req-2", "code": "S-0002"},
        ]
    )
    repo = PostgresRequirementRepository(db)

    result = await repo.resolve_codes("proj-1", ["S-0001", "S-0002"])

    assert result == {"S-0001": "req-1", "S-0002": "req-2"}


@pytest.mark.asyncio
async def test_requirement_content_repo_create_version_returns_id():
    db = FakeDatabase(fetch_one_result={"id": "ver-1"})
    repo = PostgresRequirementContentRepository(db)

    version_id = await repo.create_version(
        requirement_id="req-1",
        content="content",
        author_id="user-1",
        source="manual",
        diff_from_id=None,
    )

    assert version_id == "ver-1"


@pytest.mark.asyncio
async def test_requirement_dependency_repo_replace_dependencies():
    db = FakeDatabase()
    repo = PostgresRequirementDependencyRepository(db)

    await repo.replace_dependencies("req-1", ["dep-1", "dep-2"])

    assert db.last_many_values == [
        {"requirement_id": "req-1", "depends_on_id": "dep-1"},
        {"requirement_id": "req-1", "depends_on_id": "dep-2"},
    ]


@pytest.mark.asyncio
async def test_requirement_service_rejects_missing_dependencies():
    db = FakeDatabase()
    service = RequirementService(db)
    service._resolve_requirement = AsyncMock(return_value={"id": "req-1"})
    service.requirements.resolve_codes = AsyncMock(return_value={})
    service.requirements.resolve_ids = AsyncMock(return_value=[])

    with pytest.raises(ValueError, match="Unknown dependency references"):
        await service.update_metadata("proj-1", "req-1", "depends_on", ["S-0002"])


@pytest.mark.asyncio
async def test_requirement_service_updates_dependencies_with_ids_and_codes():
    db = FakeDatabase()
    service = RequirementService(db)
    service._resolve_requirement = AsyncMock(return_value={"id": "req-1"})
    service.requirements.resolve_codes = AsyncMock(return_value={"S-0002": "dep-2"})
    dep_uuid = "00000000-0000-0000-0000-000000000003"
    service.requirements.resolve_ids = AsyncMock(return_value=[dep_uuid])
    service.dependencies.replace_dependencies = AsyncMock()
    service.get_requirement_response = AsyncMock(
        return_value={"id": "S-0001", "depends_on": ["S-0002", dep_uuid]}
    )

    result = await service.update_metadata(
        "proj-1", "req-1", "depends_on", ["S-0002", dep_uuid]
    )

    service.dependencies.replace_dependencies.assert_awaited_with(
        "req-1", ["dep-2", dep_uuid]
    )
    assert result["id"] == "S-0001"


@pytest.mark.asyncio
async def test_requirement_service_updates_content_from_spec():
    db = FakeDatabase()
    service = RequirementService(db)
    service.requirements.get_by_spec_path = AsyncMock(
        return_value={"id": "req-1"}
    )
    service.content.get_current_version_id = AsyncMock(return_value=None)
    service.content.create_version = AsyncMock(return_value="ver-1")
    service.content.upsert_content = AsyncMock()
    service.requirements.touch_updated_at = AsyncMock()

    updated = await service.update_content_from_spec(
        "proj-1", "specs/S-0001-test.md", "# Title"
    )

    assert updated is True
    service.content.create_version.assert_awaited_with(
        requirement_id="req-1",
        content="# Title",
        author_id=None,
        source="spec_file",
        diff_from_id=None,
    )
    service.content.upsert_content.assert_awaited_with(
        requirement_id="req-1",
        content="# Title",
        current_version_id="ver-1",
    )
    service.requirements.touch_updated_at.assert_awaited_with("req-1")
