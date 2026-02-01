"""
Tests for the Database Writers Module (S-0037)

Tests for:
- AgentWriter - CRUD operations for agents
- RunWriter - CRUD operations for runs and artifacts
- Custom exceptions - AgentNotFoundError, RunNotFoundError

Uses mocking to avoid requiring a real database connection.
"""
import pytest
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch
import sys
import json

# Ensure imports work from tests directory
sys.path.insert(0, str(Path(__file__).parent.parent))

from database.writers import (
    AgentWriter,
    RunWriter,
    AgentNotFoundError,
    RunNotFoundError,
)


class TestExceptions:
    """Tests for custom exception classes"""

    def test_agent_not_found_error_stores_agent_id(self):
        """AgentNotFoundError stores agent_id and has descriptive message"""
        agent_id = "test-agent-123"
        error = AgentNotFoundError(agent_id)
        
        assert error.agent_id == agent_id
        assert agent_id in str(error)
        assert "not found" in str(error).lower()

    def test_run_not_found_error_stores_run_id(self):
        """RunNotFoundError stores run_id and has descriptive message"""
        run_id = "test-run-456"
        error = RunNotFoundError(run_id)
        
        assert error.run_id == run_id
        assert run_id in str(error)
        assert "not found" in str(error).lower()


class TestAgentWriter:
    """Tests for AgentWriter class"""

    @pytest.fixture
    def mock_db(self):
        """Create a mock Database instance"""
        db = MagicMock()
        db.fetch_one = AsyncMock()
        db.fetch_all = AsyncMock()
        db.execute = AsyncMock()
        return db

    @pytest.fixture
    def writer(self, mock_db):
        """Create an AgentWriter with mock database"""
        return AgentWriter(mock_db)

    @pytest.mark.asyncio
    async def test_upsert_agent_creates_new_agent(self, writer, mock_db):
        """upsert_agent creates new agent and returns record"""
        agent_id = "550e8400-e29b-41d4-a716-446655440000"
        project_id = "660e8400-e29b-41d4-a716-446655440001"
        name = "Test Agent"
        agent_type = "builder"
        metadata = {"version": "1.0"}

        # Mock the returned row
        mock_row = {
            "id": agent_id,
            "project_id": project_id,
            "name": name,
            "type": agent_type,
            "status": "idle",
            "metadata": metadata,
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-01T00:00:00Z",
        }
        mock_db.fetch_one.return_value = MagicMock(**mock_row, _mapping=mock_row)
        mock_db.fetch_one.return_value.__iter__ = lambda self: iter(mock_row.items())
        mock_db.fetch_one.return_value.keys = lambda: mock_row.keys()
        mock_db.fetch_one.return_value.__getitem__ = lambda self, key: mock_row[key]

        result = await writer.upsert_agent(
            agent_id=agent_id,
            project_id=project_id,
            name=name,
            type=agent_type,
            metadata=metadata,
        )

        # Verify fetch_one was called
        mock_db.fetch_one.assert_called_once()
        call_args = mock_db.fetch_one.call_args
        
        # Verify SQL contains UPSERT pattern
        query = call_args.kwargs.get("query", call_args[1].get("query", ""))
        assert "INSERT INTO agents" in query
        assert "ON CONFLICT" in query
        assert "RETURNING" in query
        
        # Verify values
        values = call_args.kwargs.get("values", call_args[1].get("values", {}))
        assert values["id"] == agent_id
        assert values["project_id"] == project_id
        assert values["name"] == name
        assert values["type"] == agent_type

    @pytest.mark.asyncio
    async def test_upsert_agent_updates_existing_agent(self, writer, mock_db):
        """upsert_agent updates existing agent on conflict"""
        agent_id = "550e8400-e29b-41d4-a716-446655440000"
        project_id = "660e8400-e29b-41d4-a716-446655440001"
        updated_name = "Updated Agent"

        mock_row = {
            "id": agent_id,
            "project_id": project_id,
            "name": updated_name,
            "type": "planner",
            "status": "idle",
            "metadata": {},
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-02T00:00:00Z",
        }
        mock_db.fetch_one.return_value = MagicMock(**mock_row, _mapping=mock_row)
        mock_db.fetch_one.return_value.__iter__ = lambda self: iter(mock_row.items())
        mock_db.fetch_one.return_value.keys = lambda: mock_row.keys()
        mock_db.fetch_one.return_value.__getitem__ = lambda self, key: mock_row[key]

        result = await writer.upsert_agent(
            agent_id=agent_id,
            project_id=project_id,
            name=updated_name,
            type="planner",
        )

        # Verify SQL has DO UPDATE clause
        call_args = mock_db.fetch_one.call_args
        query = call_args.kwargs.get("query", call_args[1].get("query", ""))
        assert "DO UPDATE" in query

    @pytest.mark.asyncio
    async def test_update_heartbeat_updates_timestamp(self, writer, mock_db):
        """update_heartbeat updates heartbeat_at and updated_at"""
        agent_id = "550e8400-e29b-41d4-a716-446655440000"

        await writer.update_heartbeat(agent_id)

        mock_db.execute.assert_called_once()
        call_args = mock_db.execute.call_args
        query = call_args.kwargs.get("query", call_args[1].get("query", ""))
        values = call_args.kwargs.get("values", call_args[1].get("values", {}))
        
        assert "UPDATE agents" in query
        assert "heartbeat_at" in query
        assert "updated_at" in query
        assert "NOW()" in query
        assert values["id"] == agent_id

    @pytest.mark.asyncio
    async def test_update_status_changes_agent_status(self, writer, mock_db):
        """update_status changes agent status field"""
        agent_id = "550e8400-e29b-41d4-a716-446655440000"
        new_status = "running"

        await writer.update_status(agent_id, new_status)

        mock_db.execute.assert_called_once()
        call_args = mock_db.execute.call_args
        query = call_args.kwargs.get("query", call_args[1].get("query", ""))
        values = call_args.kwargs.get("values", call_args[1].get("values", {}))
        
        assert "UPDATE agents" in query
        assert "status" in query
        assert values["id"] == agent_id
        assert values["status"] == new_status

    @pytest.mark.asyncio
    async def test_get_agent_returns_agent_dict(self, writer, mock_db):
        """get_agent returns agent record as dict"""
        agent_id = "550e8400-e29b-41d4-a716-446655440000"
        mock_row = {
            "id": agent_id,
            "project_id": "proj-123",
            "name": "Test Agent",
            "type": "builder",
            "status": "idle",
        }
        mock_db.fetch_one.return_value = MagicMock(**mock_row, _mapping=mock_row)
        mock_db.fetch_one.return_value.__iter__ = lambda self: iter(mock_row.items())
        mock_db.fetch_one.return_value.keys = lambda: mock_row.keys()
        mock_db.fetch_one.return_value.__getitem__ = lambda self, key: mock_row[key]

        result = await writer.get_agent(agent_id)

        mock_db.fetch_one.assert_called_once()
        call_args = mock_db.fetch_one.call_args
        query = call_args.kwargs.get("query", call_args[1].get("query", ""))
        values = call_args.kwargs.get("values", call_args[1].get("values", {}))
        
        assert "SELECT" in query
        assert "FROM agents" in query
        assert values["id"] == agent_id

    @pytest.mark.asyncio
    async def test_get_agent_returns_none_for_nonexistent(self, writer, mock_db):
        """get_agent returns None when agent does not exist"""
        agent_id = "nonexistent-agent"
        mock_db.fetch_one.return_value = None

        result = await writer.get_agent(agent_id)

        assert result is None

    @pytest.mark.asyncio
    async def test_list_agents_returns_list_for_project(self, writer, mock_db):
        """list_agents returns list of agents for a project"""
        project_id = "660e8400-e29b-41d4-a716-446655440001"
        mock_rows = [
            {"id": "agent-1", "name": "Agent 1", "type": "builder"},
            {"id": "agent-2", "name": "Agent 2", "type": "planner"},
        ]
        
        # Create mock row objects
        mock_row_objects = []
        for row in mock_rows:
            mock_row = MagicMock(**row, _mapping=row)
            mock_row.__iter__ = lambda self, r=row: iter(r.items())
            mock_row.keys = lambda r=row: r.keys()
            mock_row.__getitem__ = lambda self, key, r=row: r[key]
            mock_row_objects.append(mock_row)
        
        mock_db.fetch_all.return_value = mock_row_objects

        result = await writer.list_agents(project_id)

        mock_db.fetch_all.assert_called_once()
        call_args = mock_db.fetch_all.call_args
        query = call_args.kwargs.get("query", call_args[1].get("query", ""))
        values = call_args.kwargs.get("values", call_args[1].get("values", {}))
        
        assert "SELECT" in query
        assert "FROM agents" in query
        assert "project_id" in query
        assert "ORDER BY" in query
        assert "created_at DESC" in query
        assert values["project_id"] == project_id


class TestRunWriter:
    """Tests for RunWriter class"""

    @pytest.fixture
    def mock_db(self):
        """Create a mock Database instance"""
        db = MagicMock()
        db.fetch_one = AsyncMock()
        db.fetch_all = AsyncMock()
        db.execute = AsyncMock()
        return db

    @pytest.fixture
    def writer(self, mock_db):
        """Create a RunWriter with mock database"""
        return RunWriter(mock_db)

    @pytest.mark.asyncio
    async def test_create_run_creates_pending_run(self, writer, mock_db):
        """create_run creates a new run with status='pending'"""
        project_id = "660e8400-e29b-41d4-a716-446655440001"
        agent_id = "550e8400-e29b-41d4-a716-446655440000"
        requirement_id = "770e8400-e29b-41d4-a716-446655440002"
        metadata = {"task": "build feature"}

        mock_row = {
            "id": "run-123",
            "project_id": project_id,
            "agent_id": agent_id,
            "requirement_id": requirement_id,
            "status": "pending",
            "metadata": metadata,
        }
        mock_db.fetch_one.return_value = MagicMock(**mock_row, _mapping=mock_row)
        mock_db.fetch_one.return_value.__iter__ = lambda self: iter(mock_row.items())
        mock_db.fetch_one.return_value.keys = lambda: mock_row.keys()
        mock_db.fetch_one.return_value.__getitem__ = lambda self, key: mock_row[key]

        result = await writer.create_run(
            project_id=project_id,
            agent_id=agent_id,
            requirement_id=requirement_id,
            metadata=metadata,
        )

        mock_db.fetch_one.assert_called_once()
        call_args = mock_db.fetch_one.call_args
        query = call_args.kwargs.get("query", call_args[1].get("query", ""))
        values = call_args.kwargs.get("values", call_args[1].get("values", {}))
        
        assert "INSERT INTO runs" in query
        assert "'pending'" in query
        assert "RETURNING" in query
        assert values["project_id"] == project_id
        assert values["agent_id"] == agent_id
        assert values["requirement_id"] == requirement_id

    @pytest.mark.asyncio
    async def test_update_run_status_updates_status_and_started_at(self, writer, mock_db):
        """update_run_status updates status and sets started_at for running"""
        run_id = "run-123"
        status = "running"

        await writer.update_run_status(run_id, status)

        mock_db.execute.assert_called_once()
        call_args = mock_db.execute.call_args
        query = call_args.kwargs.get("query", call_args[1].get("query", ""))
        values = call_args.kwargs.get("values", call_args[1].get("values", {}))
        
        assert "UPDATE runs" in query
        assert "status" in query
        assert "started_at" in query
        assert "CASE" in query  # Conditional started_at update
        assert values["id"] == run_id
        assert values["status"] == status

    @pytest.mark.asyncio
    async def test_update_run_status_with_error(self, writer, mock_db):
        """update_run_status stores error message when provided"""
        run_id = "run-123"
        status = "failed"
        error_msg = "Build failed due to syntax error"

        await writer.update_run_status(run_id, status, error=error_msg)

        call_args = mock_db.execute.call_args
        values = call_args.kwargs.get("values", call_args[1].get("values", {}))
        
        assert values["error"] == error_msg

    @pytest.mark.asyncio
    async def test_complete_run_sets_completed_at(self, writer, mock_db):
        """complete_run sets completed_at timestamp"""
        run_id = "run-123"
        status = "completed"

        await writer.complete_run(run_id, status)

        mock_db.execute.assert_called_once()
        call_args = mock_db.execute.call_args
        query = call_args.kwargs.get("query", call_args[1].get("query", ""))
        values = call_args.kwargs.get("values", call_args[1].get("values", {}))
        
        assert "UPDATE runs" in query
        assert "completed_at" in query
        assert "NOW()" in query
        assert values["id"] == run_id
        assert values["status"] == status

    @pytest.mark.asyncio
    async def test_complete_run_with_error(self, writer, mock_db):
        """complete_run stores error message for failed runs"""
        run_id = "run-123"
        status = "failed"
        error_msg = "Validation failed"

        await writer.complete_run(run_id, status, error=error_msg)

        call_args = mock_db.execute.call_args
        values = call_args.kwargs.get("values", call_args[1].get("values", {}))
        
        assert values["status"] == status
        assert values["error"] == error_msg

    @pytest.mark.asyncio
    async def test_get_run_returns_run_dict(self, writer, mock_db):
        """get_run returns run record as dict"""
        run_id = "run-123"
        mock_row = {
            "id": run_id,
            "project_id": "proj-123",
            "agent_id": "agent-123",
            "status": "completed",
        }
        mock_db.fetch_one.return_value = MagicMock(**mock_row, _mapping=mock_row)
        mock_db.fetch_one.return_value.__iter__ = lambda self: iter(mock_row.items())
        mock_db.fetch_one.return_value.keys = lambda: mock_row.keys()
        mock_db.fetch_one.return_value.__getitem__ = lambda self, key: mock_row[key]

        result = await writer.get_run(run_id)

        mock_db.fetch_one.assert_called_once()
        call_args = mock_db.fetch_one.call_args
        query = call_args.kwargs.get("query", call_args[1].get("query", ""))
        values = call_args.kwargs.get("values", call_args[1].get("values", {}))
        
        assert "SELECT" in query
        assert "FROM runs" in query
        assert values["id"] == run_id

    @pytest.mark.asyncio
    async def test_get_run_returns_none_for_nonexistent(self, writer, mock_db):
        """get_run returns None when run does not exist"""
        run_id = "nonexistent-run"
        mock_db.fetch_one.return_value = None

        result = await writer.get_run(run_id)

        assert result is None

    @pytest.mark.asyncio
    async def test_list_runs_returns_list_with_limit(self, writer, mock_db):
        """list_runs returns list of runs with agent_name and respects limit"""
        project_id = "proj-123"
        limit = 10
        mock_rows = [
            {"id": "run-1", "status": "completed", "agent_name": "Agent 1"},
            {"id": "run-2", "status": "running", "agent_name": "Agent 2"},
        ]
        
        # Create mock row objects
        mock_row_objects = []
        for row in mock_rows:
            mock_row = MagicMock(**row, _mapping=row)
            mock_row.__iter__ = lambda self, r=row: iter(r.items())
            mock_row.keys = lambda r=row: r.keys()
            mock_row.__getitem__ = lambda self, key, r=row: r[key]
            mock_row_objects.append(mock_row)
        
        mock_db.fetch_all.return_value = mock_row_objects

        result = await writer.list_runs(project_id, limit=limit)

        mock_db.fetch_all.assert_called_once()
        call_args = mock_db.fetch_all.call_args
        query = call_args.kwargs.get("query", call_args[1].get("query", ""))
        values = call_args.kwargs.get("values", call_args[1].get("values", {}))
        
        assert "SELECT" in query
        assert "FROM runs" in query
        assert "JOIN agents" in query
        assert "agent_name" in query
        assert "ORDER BY" in query
        assert "LIMIT" in query
        assert values["project_id"] == project_id
        assert values["limit"] == limit

    @pytest.mark.asyncio
    async def test_create_artifact_creates_artifact_record(self, writer, mock_db):
        """create_artifact creates artifact record and returns it"""
        run_id = "run-123"
        artifact_type = "log"
        file_path = "/runs/run-123/output.log"
        metadata = {"size": 1024}

        mock_row = {
            "id": "artifact-456",
            "run_id": run_id,
            "artifact_type": artifact_type,
            "file_path": file_path,
            "metadata": metadata,
            "created_at": "2024-01-01T00:00:00Z",
        }
        mock_db.fetch_one.return_value = MagicMock(**mock_row, _mapping=mock_row)
        mock_db.fetch_one.return_value.__iter__ = lambda self: iter(mock_row.items())
        mock_db.fetch_one.return_value.keys = lambda: mock_row.keys()
        mock_db.fetch_one.return_value.__getitem__ = lambda self, key: mock_row[key]

        result = await writer.create_artifact(
            run_id=run_id,
            artifact_type=artifact_type,
            file_path=file_path,
            metadata=metadata,
        )

        mock_db.fetch_one.assert_called_once()
        call_args = mock_db.fetch_one.call_args
        query = call_args.kwargs.get("query", call_args[1].get("query", ""))
        values = call_args.kwargs.get("values", call_args[1].get("values", {}))
        
        assert "INSERT INTO run_artifacts" in query
        assert "RETURNING" in query
        assert values["run_id"] == run_id
        assert values["artifact_type"] == artifact_type
        assert values["file_path"] == file_path


class TestWriterImports:
    """Tests for module imports and exports"""

    def test_writers_module_imports_from_database_package(self):
        """Writers can be imported from database package"""
        from database import AgentWriter, RunWriter
        
        assert AgentWriter is not None
        assert RunWriter is not None

    def test_exceptions_import_from_database_package(self):
        """Exceptions can be imported from database package"""
        from database import AgentNotFoundError, RunNotFoundError
        
        assert AgentNotFoundError is not None
        assert RunNotFoundError is not None

    def test_agent_writer_init_accepts_database(self):
        """AgentWriter.__init__ accepts a Database instance"""
        mock_db = MagicMock()
        writer = AgentWriter(mock_db)
        
        assert writer.db is mock_db

    def test_run_writer_init_accepts_database(self):
        """RunWriter.__init__ accepts a Database instance"""
        mock_db = MagicMock()
        writer = RunWriter(mock_db)
        
        assert writer.db is mock_db
