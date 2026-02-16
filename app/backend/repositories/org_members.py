"""
Organization members and invites repository.
"""

from typing import Any, Dict, List, Optional

from databases import Database


class OrganizationMembersRepository:
    def __init__(self, db: Database) -> None:
        self.db = db

    async def list_members(self, org_id: str) -> List[Dict[str, Any]]:
        rows = await self.db.fetch_all(
            """
            SELECT
                m.id,
                m.org_id,
                m.user_id,
                m.role,
                m.created_at,
                m.updated_at,
                p.email,
                p.display_name,
                p.full_name
            FROM organization_members m
            LEFT JOIN user_profiles p ON p.user_id = m.user_id
            WHERE m.org_id = :org_id
            ORDER BY m.created_at DESC
            """,
            values={"org_id": org_id},
        )
        return [dict(row) for row in rows]

    async def list_invites(self, org_id: str) -> List[Dict[str, Any]]:
        rows = await self.db.fetch_all(
            """
            SELECT *
            FROM organization_invites
            WHERE org_id = :org_id
            ORDER BY created_at DESC
            """,
            values={"org_id": org_id},
        )
        return [dict(row) for row in rows]

    async def create_invite(
        self,
        org_id: str,
        email: str,
        role: str,
        invited_by_user_id: Optional[str],
    ) -> Dict[str, Any]:
        row = await self.db.fetch_one(
            """
            INSERT INTO organization_invites (
                org_id,
                email,
                role,
                status,
                invited_by_user_id
            )
            VALUES (
                :org_id,
                :email,
                :role,
                'pending',
                :invited_by_user_id
            )
            RETURNING *
            """,
            values={
                "org_id": org_id,
                "email": email,
                "role": role,
                "invited_by_user_id": invited_by_user_id,
            },
        )
        return dict(row) if row else {}

    async def update_invite_role(
        self,
        org_id: str,
        invite_id: str,
        role: str,
    ) -> Optional[Dict[str, Any]]:
        row = await self.db.fetch_one(
            """
            UPDATE organization_invites
            SET role = :role
            WHERE id = :id AND org_id = :org_id AND status = 'pending'
            RETURNING *
            """,
            values={"id": invite_id, "org_id": org_id, "role": role},
        )
        return dict(row) if row else None

    async def touch_invite(self, org_id: str, invite_id: str) -> Optional[Dict[str, Any]]:
        row = await self.db.fetch_one(
            """
            UPDATE organization_invites
            SET updated_at = NOW()
            WHERE id = :id AND org_id = :org_id
            RETURNING *
            """,
            values={"id": invite_id, "org_id": org_id},
        )
        return dict(row) if row else None

    async def revoke_invite(self, org_id: str, invite_id: str) -> Optional[Dict[str, Any]]:
        row = await self.db.fetch_one(
            """
            UPDATE organization_invites
            SET status = 'revoked'
            WHERE id = :id AND org_id = :org_id
            RETURNING *
            """,
            values={"id": invite_id, "org_id": org_id},
        )
        return dict(row) if row else None

    async def update_member_role(
        self,
        org_id: str,
        user_id: str,
        role: str,
    ) -> Optional[Dict[str, Any]]:
        row = await self.db.fetch_one(
            """
            UPDATE organization_members
            SET role = :role
            WHERE org_id = :org_id AND user_id = :user_id
            RETURNING id, org_id, user_id, role, created_at, updated_at
            """,
            values={"org_id": org_id, "user_id": user_id, "role": role},
        )
        return dict(row) if row else None

    async def delete_member(self, org_id: str, user_id: str) -> bool:
        result = await self.db.execute(
            """
            DELETE FROM organization_members
            WHERE org_id = :org_id AND user_id = :user_id
            """,
            values={"org_id": org_id, "user_id": user_id},
        )
        return bool(result)
