"""
User router for Felix Backend.

Provides endpoints for retrieving current user information.
"""

import json
import re
from typing import Any, Dict, Optional, Tuple
from fastapi import APIRouter, Depends
from databases import Database
from database.db import get_db
from auth import get_current_user

router = APIRouter(prefix="/api/user", tags=["user"])

def _slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "org"


async def _find_unique_org_slug(db: Database, base: str) -> str:
    base_slug = _slugify(base)
    slug = base_slug
    suffix = 1
    while True:
        existing = await db.fetch_one(
            "SELECT 1 FROM organizations WHERE slug = :slug",
            {"slug": slug},
        )
        if not existing:
            return slug
        suffix += 1
        slug = f"{base_slug}-{suffix}"


async def _create_personal_org(
    db: Database,
    user_id: str,
    email: Optional[str],
) -> Tuple[Dict[str, Any], str]:
    name = f"{user_id} Org"
    slug = await _find_unique_org_slug(db, name)
    metadata = {"email": email} if email else {}
    org = await db.fetch_one(
        """
        INSERT INTO organizations (name, slug, owner_id, metadata)
        VALUES (:name, :slug, :owner_id, CAST(:metadata AS JSONB))
        RETURNING id, name, slug, owner_id, metadata
        """,
        {
            "name": name,
            "slug": slug,
            "owner_id": user_id,
            "metadata": json.dumps(metadata),
        },
    )
    await db.execute(
        """
        INSERT INTO organization_members (org_id, user_id, role)
        VALUES (:org_id, :user_id, 'owner')
        ON CONFLICT (org_id, user_id) DO NOTHING
        """,
        {"org_id": org["id"], "user_id": user_id},
    )
    return dict(org), "owner"


async def _ensure_user_default_org(
    db: Database,
    user_id: str,
    auth_org_id: Optional[str],
    role_hint: str,
) -> Tuple[Dict[str, Any], str]:
    org = None
    role = None
    if auth_org_id:
        org = await db.fetch_one(
            """
            SELECT o.id, o.name, o.slug, o.owner_id, o.metadata, m.role
            FROM organizations o
            LEFT JOIN organization_members m
              ON m.org_id = o.id AND m.user_id = :user_id
            WHERE o.id = :org_id
            """,
            {"org_id": auth_org_id, "user_id": user_id},
        )
        if org:
            role = org["role"] or role_hint
            await db.execute(
                """
                INSERT INTO organization_members (org_id, user_id, role)
                VALUES (:org_id, :user_id, :role)
                ON CONFLICT (org_id, user_id) DO NOTHING
                """,
                {"org_id": org["id"], "user_id": user_id, "role": role},
            )
            return dict(org), role

    membership = await db.fetch_one(
        """
        SELECT o.id, o.name, o.slug, o.owner_id, o.metadata, m.role
        FROM organizations o
        JOIN organization_members m ON m.org_id = o.id
        WHERE m.user_id = :user_id
        ORDER BY m.created_at
        LIMIT 1
        """,
        {"user_id": user_id},
    )
    if membership:
        return dict(membership), membership["role"]

    email = f"{user_id}@example.com"
    return await _create_personal_org(db, user_id, email)


@router.get("/me")
async def get_user_profile(
    user: Dict[str, Any] = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    """
    Get the current user's profile including organization details.

    Returns:
        Dict with user_id, email, organization name, org_slug, and role.
    """
    user_id = user["user_id"]
    org_id = user.get("org_id")
    role_hint = user.get("role", "member")

    org, role = await _ensure_user_default_org(db, user_id, org_id, role_hint)

    # Extract email from org metadata
    # The metadata might be a string (JSON) or already parsed as dict
    metadata = org.get("metadata")
    if isinstance(metadata, str):
        try:
            metadata = json.loads(metadata)
        except (json.JSONDecodeError, TypeError):
            metadata = {}
    elif metadata is None:
        metadata = {}

    email = metadata.get("email", f"{user_id}@example.com")

    return {
        "user_id": user_id,
        "email": email,
        "organization": org.get("name"),
        "org_slug": org.get("slug"),
        "org_id": str(org.get("id")),
        "role": role,
    }


@router.get("/orgs")
async def list_user_orgs(
    user: Dict[str, Any] = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    """
    List organizations the current user belongs to.
    """
    query = """
        SELECT o.id, o.name, o.slug, m.role
        FROM organizations o
        JOIN organization_members m ON m.org_id = o.id
        WHERE m.user_id = :user_id
        ORDER BY o.name
    """
    rows = await db.fetch_all(query, {"user_id": user["user_id"]})
    if not rows:
        org, role = await _ensure_user_default_org(
            db,
            user["user_id"],
            user.get("org_id"),
            user.get("role", "member"),
        )
        return [
            {
                "id": str(org["id"]),
                "name": org["name"],
                "slug": org["slug"],
                "role": role,
            }
        ]
    return [
        {
            "id": str(row["id"]),
            "name": row["name"],
            "slug": row["slug"],
            "role": row["role"],
        }
        for row in rows
    ]
