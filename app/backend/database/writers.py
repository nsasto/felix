"""
Database writers module for Felix Backend.

Provides AgentWriter and RunWriter classes that encapsulate all CRUD operations
for agents, runs, and artifacts.
"""

import json
import logging
from typing import Dict, List, Optional, Any

from databases import Database


# Configure logging
logger = logging.getLogger(__name__)


# ============================================================================
# Custom Exceptions
# ============================================================================


class AgentNotFoundError(Exception):
    """Raised when an agent lookup fails."""

    def __init__(self, agent_id: str):
        self.agent_id = agent_id
        super().__init__(f"Agent not found: {agent_id}")


class RunNotFoundError(Exception):
    """Raised when a run lookup fails."""

    def __init__(self, run_id: str):
        self.run_id = run_id
        super().__init__(f"Run not found: {run_id}")


# ============================================================================
# AgentWriter Class
# ============================================================================


class AgentWriter:
    """
    Encapsulates all CRUD operations for agents.

    Provides methods to create, update, and retrieve agent records from the database.
    """

    def __init__(self, db: Database) -> None:
        """
        Initialize the AgentWriter with a database connection.

        Args:
            db: The databases.Database instance to use for queries.
        """
        self.db = db

    async def upsert_agent(
        self,
        agent_id: str,
        project_id: str,
        name: str,
        type: str,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Create or update an agent record using PostgreSQL UPSERT.

        Args:
            agent_id: The unique identifier for the agent (UUID string).
            project_id: The project this agent belongs to (UUID string).
            name: The display name of the agent.
            type: The type of agent (e.g., 'builder', 'planner').
            metadata: Optional JSON metadata for the agent.

        Returns:
            The inserted or updated agent record as a dict.
        """
        try:
            metadata_json = json.dumps(metadata) if metadata else "{}"
            query = """
                INSERT INTO agents (id, project_id, name, type, status, metadata, created_at, updated_at)
                VALUES (:id, :project_id, :name, :type, 'idle', :metadata::jsonb, NOW(), NOW())
                ON CONFLICT (id) DO UPDATE SET
                    name = EXCLUDED.name,
                    type = EXCLUDED.type,
                    metadata = EXCLUDED.metadata,
                    updated_at = NOW()
                RETURNING *
            """
            row = await self.db.fetch_one(
                query=query,
                values={
                    "id": agent_id,
                    "project_id": project_id,
                    "name": name,
                    "type": type,
                    "metadata": metadata_json,
                },
            )
            return dict(row) if row else {}
        except Exception as e:
            logger.error(f"Error upserting agent {agent_id}: {e}")
            raise

    async def update_heartbeat(self, agent_id: str) -> None:
        """
        Update the heartbeat timestamp for an agent.

        Args:
            agent_id: The unique identifier for the agent (UUID string).
        """
        try:
            query = """
                UPDATE agents
                SET heartbeat_at = NOW(), updated_at = NOW()
                WHERE id = :id
            """
            await self.db.execute(query=query, values={"id": agent_id})
        except Exception as e:
            logger.error(f"Error updating heartbeat for agent {agent_id}: {e}")
            raise

    async def update_status(self, agent_id: str, status: str) -> None:
        """
        Update the status of an agent.

        Args:
            agent_id: The unique identifier for the agent (UUID string).
            status: The new status (one of 'idle', 'running', 'stopped', 'error').
        """
        try:
            query = """
                UPDATE agents
                SET status = :status, updated_at = NOW()
                WHERE id = :id
            """
            await self.db.execute(
                query=query, values={"id": agent_id, "status": status}
            )
        except Exception as e:
            logger.error(f"Error updating status for agent {agent_id}: {e}")
            raise

    async def get_agent(self, agent_id: str) -> Optional[Dict[str, Any]]:
        """
        Fetch an agent by ID.

        Args:
            agent_id: The unique identifier for the agent (UUID string).

        Returns:
            The agent record as a dict, or None if not found.
        """
        try:
            query = """
                SELECT * FROM agents WHERE id = :id
            """
            row = await self.db.fetch_one(query=query, values={"id": agent_id})
            return dict(row) if row else None
        except Exception as e:
            logger.error(f"Error fetching agent {agent_id}: {e}")
            raise

    async def list_agents(self, project_id: str) -> List[Dict[str, Any]]:
        """
        List all agents for a project.

        Args:
            project_id: The project ID to filter by (UUID string).

        Returns:
            A list of agent records as dicts, ordered by created_at DESC.
        """
        try:
            query = """
                SELECT * FROM agents
                WHERE project_id = :project_id
                ORDER BY created_at DESC
            """
            rows = await self.db.fetch_all(query=query, values={"project_id": project_id})
            return [dict(row) for row in rows]
        except Exception as e:
            logger.error(f"Error listing agents for project {project_id}: {e}")
            raise


# ============================================================================
# RunWriter Class
# ============================================================================


class RunWriter:
    """
    Encapsulates all CRUD operations for runs and run artifacts.

    Provides methods to create, update, and retrieve run records from the database.
    """

    def __init__(self, db: Database) -> None:
        """
        Initialize the RunWriter with a database connection.

        Args:
            db: The databases.Database instance to use for queries.
        """
        self.db = db

    async def create_run(
        self,
        project_id: str,
        agent_id: str,
        requirement_id: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Create a new run record with status='pending'.

        Args:
            project_id: The project this run belongs to (UUID string).
            agent_id: The agent executing this run (UUID string).
            requirement_id: Optional requirement being worked on (UUID string).
            metadata: Optional JSON metadata for the run.

        Returns:
            The created run record as a dict.
        """
        try:
            metadata_json = json.dumps(metadata) if metadata else "{}"
            query = """
                INSERT INTO runs (project_id, agent_id, requirement_id, status, metadata)
                VALUES (:project_id, :agent_id, :requirement_id, 'pending', :metadata::jsonb)
                RETURNING *
            """
            row = await self.db.fetch_one(
                query=query,
                values={
                    "project_id": project_id,
                    "agent_id": agent_id,
                    "requirement_id": requirement_id,
                    "metadata": metadata_json,
                },
            )
            return dict(row) if row else {}
        except Exception as e:
            logger.error(f"Error creating run for agent {agent_id}: {e}")
            raise

    async def update_run_status(
        self,
        run_id: str,
        status: str,
        error: Optional[str] = None,
    ) -> None:
        """
        Update the status of a run.

        Sets started_at to NOW() if status='running' and started_at is NULL.

        Args:
            run_id: The unique identifier for the run (UUID string).
            status: The new status (one of 'pending', 'running', 'completed', 'failed', 'cancelled').
            error: Optional error message if status indicates failure.
        """
        try:
            query = """
                UPDATE runs
                SET status = :status,
                    error = COALESCE(:error, error),
                    started_at = CASE
                        WHEN :status = 'running' AND started_at IS NULL THEN NOW()
                        ELSE started_at
                    END
                WHERE id = :id
            """
            await self.db.execute(
                query=query,
                values={
                    "id": run_id,
                    "status": status,
                    "error": error,
                },
            )
        except Exception as e:
            logger.error(f"Error updating status for run {run_id}: {e}")
            raise

    async def complete_run(
        self,
        run_id: str,
        status: str,
        error: Optional[str] = None,
    ) -> None:
        """
        Mark a run as completed or failed, setting the completed_at timestamp.

        Args:
            run_id: The unique identifier for the run (UUID string).
            status: The final status (expects 'completed' or 'failed').
            error: Optional error message if the run failed.
        """
        try:
            query = """
                UPDATE runs
                SET status = :status,
                    error = :error,
                    completed_at = NOW()
                WHERE id = :id
            """
            await self.db.execute(
                query=query,
                values={
                    "id": run_id,
                    "status": status,
                    "error": error,
                },
            )
        except Exception as e:
            logger.error(f"Error completing run {run_id}: {e}")
            raise

    async def get_run(self, run_id: str) -> Optional[Dict[str, Any]]:
        """
        Fetch a run by ID.

        Args:
            run_id: The unique identifier for the run (UUID string).

        Returns:
            The run record as a dict, or None if not found.
        """
        try:
            query = """
                SELECT * FROM runs WHERE id = :id
            """
            row = await self.db.fetch_one(query=query, values={"id": run_id})
            return dict(row) if row else None
        except Exception as e:
            logger.error(f"Error fetching run {run_id}: {e}")
            raise

    async def list_runs(
        self,
        project_id: str,
        limit: int = 50,
    ) -> List[Dict[str, Any]]:
        """
        List recent runs for a project with agent names.

        Args:
            project_id: The project ID to filter by (UUID string).
            limit: Maximum number of runs to return (default 50).

        Returns:
            A list of run records as dicts with agent_name, ordered by created_at DESC.
        """
        try:
            query = """
                SELECT r.*, a.name AS agent_name
                FROM runs r
                JOIN agents a ON r.agent_id = a.id
                WHERE r.project_id = :project_id
                ORDER BY r.id DESC
                LIMIT :limit
            """
            rows = await self.db.fetch_all(
                query=query,
                values={"project_id": project_id, "limit": limit},
            )
            return [dict(row) for row in rows]
        except Exception as e:
            logger.error(f"Error listing runs for project {project_id}: {e}")
            raise

    async def create_artifact(
        self,
        run_id: str,
        artifact_type: str,
        file_path: str,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Create an artifact record for a run.

        Args:
            run_id: The run this artifact belongs to (UUID string).
            artifact_type: The type of artifact (e.g., 'log', 'report', 'plan').
            file_path: The path to the artifact file.
            metadata: Optional JSON metadata for the artifact.

        Returns:
            The created artifact record as a dict.
        """
        try:
            metadata_json = json.dumps(metadata) if metadata else "{}"
            query = """
                INSERT INTO run_artifacts (run_id, artifact_type, file_path, metadata)
                VALUES (:run_id, :artifact_type, :file_path, :metadata::jsonb)
                RETURNING *
            """
            row = await self.db.fetch_one(
                query=query,
                values={
                    "run_id": run_id,
                    "artifact_type": artifact_type,
                    "file_path": file_path,
                    "metadata": metadata_json,
                },
            )
            return dict(row) if row else {}
        except Exception as e:
            logger.error(f"Error creating artifact for run {run_id}: {e}")
            raise
