"""
Tests for Console Streaming WebSocket (S-0041: Console Streaming WebSocket)

Verifies:
- WebSocket endpoint exists
- run_id validation
- run existence validation
- Event streaming behavior (from_start vs end)
- Message format
"""
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).parent.parent))

from main import app
from database.db import get_db


class FakeDB:
    def __init__(self, events_by_run):
        self._events_by_run = events_by_run

    async def fetch_one(self, query, values):
        if "SELECT id FROM runs" in query:
            run_id = values["run_id"]
            if run_id in self._events_by_run:
                return {"id": run_id}
            return None
        if "SELECT MAX(id)" in query:
            run_id = values["run_id"]
            events = self._events_by_run.get(run_id, [])
            max_id = max((event["id"] for event in events), default=None)
            return {"max_id": max_id}
        return None

    async def fetch_all(self, query, values):
        run_id = values["run_id"]
        last_id = values["last_id"]
        events = self._events_by_run.get(run_id, [])
        return [event for event in events if event["id"] > last_id]


@pytest.fixture
def client():
    app.dependency_overrides.clear()
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_websocket_endpoint_exists_in_router():
    from routers.agents import router

    routes = [route for route in router.routes if hasattr(route, "path")]
    console_routes = [route for route in routes if "/console" in route.path]
    assert len(console_routes) > 0, "Console WebSocket route should be registered"


def test_websocket_rejects_missing_run_id(client):
    with client.websocket_connect("/api/agents/1/console") as websocket:
        data = websocket.receive_json()
        assert data["error"] == "run_id query parameter is required"


def test_websocket_rejects_unknown_run_id(client):
    fake_db = FakeDB(events_by_run={})
    app.dependency_overrides[get_db] = lambda: fake_db

    with client.websocket_connect("/api/agents/1/console?run_id=missing") as websocket:
        data = websocket.receive_json()
        assert data["error"] == "Run not found: missing"


def test_websocket_connects_successfully_with_valid_run_id(client):
    fake_db = FakeDB(events_by_run={"run-001": []})
    app.dependency_overrides[get_db] = lambda: fake_db

    with client.websocket_connect("/api/agents/1/console?run_id=run-001") as websocket:
        data = websocket.receive_json()
        assert data["type"] == "connected"
        assert data["run_id"] == "run-001"


def test_websocket_streams_from_end_by_default(client):
    events = [
        {
            "id": 1,
            "ts": "2026-01-01T00:00:00Z",
            "type": "console",
            "level": "info",
            "message": "Old content\n",
            "payload": None,
        }
    ]
    fake_db = FakeDB(events_by_run={"run-002": events})
    app.dependency_overrides[get_db] = lambda: fake_db

    with client.websocket_connect("/api/agents/1/console?run_id=run-002") as websocket:
        websocket.receive_json()  # connected

        # Append new event after connection
        events.append(
            {
                "id": 2,
                "ts": "2026-01-01T00:00:01Z",
                "type": "console",
                "level": "info",
                "message": "New content\n",
                "payload": None,
            }
        )

        data = websocket.receive_json()
        assert data["type"] == "output"
        assert data["content"] == "New content\n"
        assert data["run_id"] == "run-002"


def test_websocket_streams_from_beginning_when_requested(client):
    events = [
        {
            "id": 1,
            "ts": "2026-01-01T00:00:00Z",
            "type": "console",
            "level": "info",
            "message": "Existing content\n",
            "payload": None,
        }
    ]
    fake_db = FakeDB(events_by_run={"run-003": events})
    app.dependency_overrides[get_db] = lambda: fake_db

    with client.websocket_connect(
        "/api/agents/1/console?run_id=run-003&from_start=true"
    ) as websocket:
        websocket.receive_json()  # connected
        data = websocket.receive_json()
        assert data["type"] == "output"
        assert "Existing content" in data["content"]


def test_output_message_format(client):
    events = [
        {
            "id": 1,
            "ts": "2026-01-01T00:00:00Z",
            "type": "console",
            "level": "info",
            "message": "Test output\n",
            "payload": None,
        }
    ]
    fake_db = FakeDB(events_by_run={"run-format": events})
    app.dependency_overrides[get_db] = lambda: fake_db

    with client.websocket_connect(
        "/api/agents/1/console?run_id=run-format&from_start=true"
    ) as websocket:
        websocket.receive_json()  # connected
        data = websocket.receive_json()
        assert data["type"] == "output"
        assert "content" in data
        assert data["run_id"] == "run-format"
