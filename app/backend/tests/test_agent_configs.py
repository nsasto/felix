"""
Tests for the Agent Configuration API (S-0020: Consolidate Agent Settings Management)

These tests validate:
1. CRUD operations for agent configurations
2. Active agent selection behavior
"""

from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.testclient import TestClient

import sys

sys.path.insert(0, str(Path(__file__).parent.parent))

from auth import get_current_user
from database.db import get_db
from main import app


@pytest.fixture
def mock_db():
    mock_database = MagicMock()
    mock_database.fetch_one = AsyncMock(
        return_value={"metadata": {"active_agent_profile_id": "profile-1"}}
    )
    mock_database.execute = AsyncMock(return_value=None)
    return mock_database


@pytest.fixture
def client(mock_db):
    def override_get_db():
        return mock_db

    def override_get_current_user():
        return {"user_id": "dev-user", "org_id": "org-1"}

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_current_user] = override_get_current_user

    # Mock database startup/shutdown to avoid real connections
    with patch("main.db_startup", new_callable=AsyncMock), patch(
        "main.db_shutdown", new_callable=AsyncMock
    ):
        with TestClient(app) as test_client:
            yield test_client

    app.dependency_overrides.clear()


@pytest.fixture
def mock_repo():
    with patch("routers.agent_configs.PostgresAgentProfileRepository") as MockRepo:
        repo = MagicMock()
        MockRepo.return_value = repo
        yield repo


def _profile(profile_id: str, name: str = "profile"):
    return {
        "id": profile_id,
        "name": name,
        "adapter": "droid",
        "executable": "droid",
        "args": [],
        "model": None,
        "working_directory": ".",
        "environment": {},
        "description": None,
    }


class TestGetAgentConfigs:
    def test_get_agents_returns_profiles_and_active(self, client, mock_db, mock_repo):
        mock_repo.list_by_org = AsyncMock(
            return_value=[_profile("profile-1", "primary")]
        )

        response = client.get("/api/agent-configs")

        assert response.status_code == 200
        data = response.json()
        assert data["active_agent_id"] == "profile-1"
        assert len(data["agents"]) == 1
        assert data["agents"][0]["name"] == "primary"


class TestGetSingleAgentConfig:
    def test_get_agent_returns_404_when_missing(self, client, mock_repo):
        mock_repo.get_by_id = AsyncMock(return_value=None)

        response = client.get("/api/agent-configs/missing")

        assert response.status_code == 404


class TestCreateAgentConfig:
    def test_create_agent_sets_active_when_missing(self, client, mock_db, mock_repo):
        mock_db.fetch_one = AsyncMock(return_value=None)
        mock_repo.create_profile = AsyncMock(return_value=_profile("profile-2", "new"))

        response = client.post(
            "/api/agent-configs",
            json={"name": "new", "adapter": "droid", "executable": "droid"},
        )

        assert response.status_code == 201
        assert response.json()["agent"]["id"] == "profile-2"
        assert mock_db.execute.called


class TestUpdateAgentConfig:
    def test_update_agent_uses_repo(self, client, mock_repo):
        mock_repo.get_by_id = AsyncMock(
            side_effect=[
                _profile("profile-1", "before"),
                _profile("profile-1", "after"),
            ]
        )
        mock_repo.update_profile = AsyncMock(return_value=None)

        response = client.put(
            "/api/agent-configs/profile-1",
            json={"name": "after"},
        )

        assert response.status_code == 200
        assert response.json()["agent"]["name"] == "after"


class TestDeleteAgentConfig:
    def test_delete_active_agent_clears_active(self, client, mock_db, mock_repo):
        mock_repo.get_by_id = AsyncMock(return_value=_profile("profile-1", "primary"))
        mock_repo.delete_profile = AsyncMock(return_value=None)
        mock_repo.list_by_org = AsyncMock(return_value=[])

        response = client.delete("/api/agent-configs/profile-1")

        assert response.status_code == 200
        assert response.json()["status"] == "deleted"
        assert mock_db.execute.called


class TestSetActiveAgent:
    def test_set_active_agent_updates_org_metadata(self, client, mock_db, mock_repo):
        mock_repo.get_by_id = AsyncMock(return_value=_profile("profile-9", "active"))

        response = client.post(
            "/api/agent-configs/active", json={"agent_id": "profile-9"}
        )

        assert response.status_code == 200
        assert response.json()["agent_id"] == "profile-9"
        assert mock_db.execute.called


class TestGetActiveAgent:
    def test_get_active_agent_returns_profile(self, client, mock_repo):
        mock_repo.get_by_id = AsyncMock(return_value=_profile("profile-1", "primary"))

        response = client.get("/api/agent-configs/active/current")

        assert response.status_code == 200
        assert response.json()["agent"]["id"] == "profile-1"
