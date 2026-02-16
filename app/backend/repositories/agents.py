"""
Agent profile, agent instance, and machine repositories.
"""

from __future__ import annotations

import json
from typing import Any, Dict, List, Optional, Protocol

from databases import Database


class IAgentProfileRepository(Protocol):
    async def list_by_org(self, org_id: str) -> List[Dict[str, Any]]: ...

    async def get_by_id(
        self, org_id: str, profile_id: str
    ) -> Optional[Dict[str, Any]]: ...

    async def get_by_name_adapter(
        self, org_id: str, name: str, adapter: str
    ) -> Optional[Dict[str, Any]]: ...

    async def create_profile(
        self,
        org_id: str,
        name: str,
        adapter: str,
        executable: str,
        args: Optional[List[str]],
        model: Optional[str],
        working_directory: Optional[str],
        environment: Dict[str, str],
        description: Optional[str],
        source: str,
        created_by_user_id: Optional[str],
    ) -> Dict[str, Any]: ...

    async def update_profile(
        self, profile_id: str, updates: Dict[str, Any]
    ) -> None: ...

    async def delete_profile(self, profile_id: str) -> None: ...


class IAgentRepository(Protocol):
    async def get_by_id(self, agent_id: str) -> Optional[Dict[str, Any]]: ...

    async def list_by_project(self, project_id: str) -> List[Dict[str, Any]]: ...

    async def list_by_org(self, org_id: str) -> List[Dict[str, Any]]: ...

    async def create_agent(
        self,
        agent_id: str,
        project_id: str,
        name: str,
        type: str,
        profile_id: Optional[str],
        assigned_user_id: Optional[str],
        machine_id: Optional[str],
        registered_by_user_id: Optional[str],
        registered_by_machine_id: Optional[str],
        override_executable: Optional[str],
        override_model: Optional[str],
        metadata: Optional[Dict[str, Any]],
    ) -> Dict[str, Any]: ...

    async def update_status(self, agent_id: str, status: str) -> None: ...

    async def update_heartbeat(self, agent_id: str) -> None: ...

    async def set_assignment(
        self, agent_id: str, assigned_user_id: Optional[str]
    ) -> None: ...

    async def set_machine(self, agent_id: str, machine_id: Optional[str]) -> None: ...

    async def set_profile(self, agent_id: str, profile_id: Optional[str]) -> None: ...


class IMachineRepository(Protocol):
    async def get_by_id(self, machine_id: str) -> Optional[Dict[str, Any]]: ...

    async def upsert_machine(
        self,
        org_id: str,
        hostname: str,
        fingerprint: str,
        metadata: Optional[Dict[str, Any]],
    ) -> Dict[str, Any]: ...

    async def touch_last_seen(self, machine_id: str) -> None: ...


class PostgresAgentProfileRepository:
    def __init__(self, db: Database) -> None:
        self.db = db

    async def list_by_org(self, org_id: str) -> List[Dict[str, Any]]:
        rows = await self.db.fetch_all(
            """
            SELECT *
            FROM agent_profiles
            WHERE org_id = :org_id
            ORDER BY name, id
            """,
            values={"org_id": org_id},
        )
        return [dict(row) for row in rows]

    async def get_by_id(self, org_id: str, profile_id: str) -> Optional[Dict[str, Any]]:
        row = await self.db.fetch_one(
            """
            SELECT *
            FROM agent_profiles
            WHERE org_id = :org_id AND id = :id
            """,
            values={"org_id": org_id, "id": profile_id},
        )
        return dict(row) if row else None

    async def get_by_name_adapter(
        self, org_id: str, name: str, adapter: str
    ) -> Optional[Dict[str, Any]]:
        row = await self.db.fetch_one(
            """
            SELECT *
            FROM agent_profiles
            WHERE org_id = :org_id AND name = :name AND adapter = :adapter
            """,
            values={"org_id": org_id, "name": name, "adapter": adapter},
        )
        return dict(row) if row else None

    async def create_profile(
        self,
        org_id: str,
        name: str,
        adapter: str,
        executable: str,
        args: Optional[List[str]],
        model: Optional[str],
        working_directory: Optional[str],
        environment: Dict[str, str],
        description: Optional[str],
        source: str,
        created_by_user_id: Optional[str],
    ) -> Dict[str, Any]:
        row = await self.db.fetch_one(
            """
            INSERT INTO agent_profiles (
                org_id,
                name,
                adapter,
                executable,
                args,
                model,
                working_directory,
                environment,
                description,
                source,
                created_by_user_id
            )
            VALUES (
                :org_id,
                :name,
                :adapter,
                :executable,
                CAST(:args AS jsonb),
                :model,
                :working_directory,
                CAST(:environment AS jsonb),
                :description,
                :source,
                :created_by_user_id
            )
            RETURNING *
            """,
            values={
                "org_id": org_id,
                "name": name,
                "adapter": adapter,
                "executable": executable,
                "args": json.dumps(args) if args is not None else None,
                "model": model,
                "working_directory": working_directory,
                "environment": json.dumps(environment),
                "description": description,
                "source": source,
                "created_by_user_id": created_by_user_id,
            },
        )
        return dict(row) if row else {}

    async def update_profile(self, profile_id: str, updates: Dict[str, Any]) -> None:
        allowed = {
            "name",
            "adapter",
            "executable",
            "args",
            "model",
            "working_directory",
            "environment",
            "description",
            "source",
            "created_by_user_id",
        }
        fields = [key for key in updates.keys() if key in allowed]
        if not fields:
            return

        assignments = []
        values: Dict[str, Any] = {"id": profile_id}
        for field in fields:
            placeholder = field
            if field in {"args", "environment"}:
                assignments.append(f"{field} = :{placeholder}::jsonb")
                values[placeholder] = json.dumps(updates[field])
            else:
                assignments.append(f"{field} = :{placeholder}")
                values[placeholder] = updates[field]

        query = f"""
            UPDATE agent_profiles
            SET {", ".join(assignments)}
            WHERE id = :id
        """
        await self.db.execute(query=query, values=values)

    async def delete_profile(self, profile_id: str) -> None:
        await self.db.execute(
            "DELETE FROM agent_profiles WHERE id = :id",
            values={"id": profile_id},
        )


class PostgresAgentRepository:
    def __init__(self, db: Database) -> None:
        self.db = db

    async def get_by_id(self, agent_id: str) -> Optional[Dict[str, Any]]:
        row = await self.db.fetch_one(
            "SELECT * FROM agents WHERE id = :id",
            values={"id": agent_id},
        )
        return dict(row) if row else None

    async def list_by_project(self, project_id: str) -> List[Dict[str, Any]]:
        rows = await self.db.fetch_all(
            """
            SELECT a.*, ap.name AS profile_name, m.hostname AS hostname
            FROM agents a
            LEFT JOIN agent_profiles ap ON ap.id = a.profile_id
            LEFT JOIN machines m ON m.id = a.machine_id
            WHERE a.project_id = :project_id
            ORDER BY a.created_at DESC
            """,
            values={"project_id": project_id},
        )
        return [dict(row) for row in rows]

    async def list_by_org(self, org_id: str) -> List[Dict[str, Any]]:
        rows = await self.db.fetch_all(
            """
            SELECT a.*, ap.name AS profile_name, m.hostname AS hostname
            FROM agents a
            JOIN projects p ON p.id = a.project_id
            LEFT JOIN agent_profiles ap ON ap.id = a.profile_id
            LEFT JOIN machines m ON m.id = a.machine_id
            WHERE p.org_id = :org_id
            ORDER BY a.created_at DESC
            """,
            values={"org_id": org_id},
        )
        return [dict(row) for row in rows]

    async def create_agent(
        self,
        agent_id: str,
        project_id: str,
        name: str,
        type: str,
        profile_id: Optional[str],
        assigned_user_id: Optional[str],
        machine_id: Optional[str],
        registered_by_user_id: Optional[str],
        registered_by_machine_id: Optional[str],
        override_executable: Optional[str],
        override_model: Optional[str],
        metadata: Optional[Dict[str, Any]],
    ) -> Dict[str, Any]:
        row = await self.db.fetch_one(
            """
            INSERT INTO agents (
                id,
                project_id,
                name,
                type,
                status,
                metadata,
                profile_id,
                assigned_user_id,
                machine_id,
                registered_by_user_id,
                registered_by_machine_id,
                override_executable,
                override_model
            )
            VALUES (
                :id,
                :project_id,
                :name,
                :type,
                'idle',
                CAST(:metadata_payload AS jsonb),
                :profile_id,
                :assigned_user_id,
                :machine_id,
                :registered_by_user_id,
                :registered_by_machine_id,
                :override_executable,
                :override_model
            )
            ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                type = EXCLUDED.type,
                metadata = EXCLUDED.metadata,
                profile_id = EXCLUDED.profile_id,
                assigned_user_id = EXCLUDED.assigned_user_id,
                machine_id = EXCLUDED.machine_id,
                registered_by_user_id = EXCLUDED.registered_by_user_id,
                registered_by_machine_id = EXCLUDED.registered_by_machine_id,
                override_executable = EXCLUDED.override_executable,
                override_model = EXCLUDED.override_model,
                updated_at = NOW()
            RETURNING *
            """,
            values={
                "id": agent_id,
                "project_id": project_id,
                "name": name,
                "type": type,
                "metadata_payload": json.dumps(metadata) if metadata else "{}",
                "profile_id": profile_id,
                "assigned_user_id": assigned_user_id,
                "machine_id": machine_id,
                "registered_by_user_id": registered_by_user_id,
                "registered_by_machine_id": registered_by_machine_id,
                "override_executable": override_executable,
                "override_model": override_model,
            },
        )
        return dict(row) if row else {}

    async def update_status(self, agent_id: str, status: str) -> None:
        await self.db.execute(
            """
            UPDATE agents
            SET status = :status, updated_at = NOW()
            WHERE id = :id
            """,
            values={"id": agent_id, "status": status},
        )

    async def update_heartbeat(self, agent_id: str) -> None:
        await self.db.execute(
            """
            UPDATE agents
            SET heartbeat_at = NOW(), updated_at = NOW()
            WHERE id = :id
            """,
            values={"id": agent_id},
        )

    async def set_assignment(
        self, agent_id: str, assigned_user_id: Optional[str]
    ) -> None:
        await self.db.execute(
            """
            UPDATE agents
            SET assigned_user_id = :assigned_user_id, updated_at = NOW()
            WHERE id = :id
            """,
            values={"id": agent_id, "assigned_user_id": assigned_user_id},
        )

    async def set_machine(self, agent_id: str, machine_id: Optional[str]) -> None:
        await self.db.execute(
            """
            UPDATE agents
            SET machine_id = :machine_id, updated_at = NOW()
            WHERE id = :id
            """,
            values={"id": agent_id, "machine_id": machine_id},
        )

    async def set_profile(self, agent_id: str, profile_id: Optional[str]) -> None:
        await self.db.execute(
            """
            UPDATE agents
            SET profile_id = :profile_id, updated_at = NOW()
            WHERE id = :id
            """,
            values={"id": agent_id, "profile_id": profile_id},
        )


class PostgresMachineRepository:
    def __init__(self, db: Database) -> None:
        self.db = db

    async def get_by_id(self, machine_id: str) -> Optional[Dict[str, Any]]:
        row = await self.db.fetch_one(
            "SELECT * FROM machines WHERE id = :id",
            values={"id": machine_id},
        )
        return dict(row) if row else None

    async def upsert_machine(
        self,
        org_id: str,
        hostname: str,
        fingerprint: str,
        metadata: Optional[Dict[str, Any]],
    ) -> Dict[str, Any]:
        row = await self.db.fetch_one(
            """
            INSERT INTO machines (
                org_id,
                hostname,
                fingerprint,
                metadata,
                last_seen_at
            )
            VALUES (
                :org_id,
                :hostname,
                :fingerprint,
                CAST(:metadata_payload AS jsonb),
                NOW()
            )
            ON CONFLICT (org_id, fingerprint) DO UPDATE SET
                hostname = EXCLUDED.hostname,
                metadata = EXCLUDED.metadata,
                last_seen_at = NOW(),
                updated_at = NOW()
            RETURNING *
            """,
            values={
                "org_id": org_id,
                "hostname": hostname,
                "fingerprint": fingerprint,
                "metadata_payload": json.dumps(metadata) if metadata else "{}",
            },
        )
        return dict(row) if row else {}

    async def touch_last_seen(self, machine_id: str) -> None:
        await self.db.execute(
            """
            UPDATE machines
            SET last_seen_at = NOW(), updated_at = NOW()
            WHERE id = :id
            """,
            values={"id": machine_id},
        )
