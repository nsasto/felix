"""
User router for Felix Backend.

Provides endpoints for retrieving current user information.
"""

import json
import re
from typing import Any, Dict, Optional, Tuple
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from fastapi.responses import Response
from databases import Database
from database.db import get_db
from auth import get_current_user
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/user", tags=["user"])

MAX_AVATAR_BYTES = 2 * 1024 * 1024

class UserProfileDetails(BaseModel):
    user_id: str
    email: Optional[str] = None
    display_name: Optional[str] = None
    full_name: Optional[str] = None
    title: Optional[str] = None
    bio: Optional[str] = None
    phone: Optional[str] = None
    location: Optional[str] = None
    website: Optional[str] = None
    avatar_url: Optional[str] = None
    updated_at: Optional[str] = None


class UserProfileUpdate(BaseModel):
    display_name: Optional[str] = Field(None, max_length=120)
    full_name: Optional[str] = Field(None, max_length=160)
    title: Optional[str] = Field(None, max_length=160)
    bio: Optional[str] = Field(None, max_length=600)
    phone: Optional[str] = Field(None, max_length=60)
    location: Optional[str] = Field(None, max_length=120)
    website: Optional[str] = Field(None, max_length=200)

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

async def _ensure_user_profile(db: Database, user_id: str, email: Optional[str]) -> Dict[str, Any]:
    row = await db.fetch_one(
        """
        INSERT INTO user_profiles (user_id, email)
        VALUES (:user_id, :email)
        ON CONFLICT (user_id)
        DO UPDATE SET email = COALESCE(user_profiles.email, EXCLUDED.email)
        RETURNING *
        """,
        {"user_id": user_id, "email": email},
    )
    return dict(row) if row else {}


def _profile_to_response(row: Dict[str, Any]) -> UserProfileDetails:
    has_avatar = bool(row.get("avatar_bytes"))
    return UserProfileDetails(
        user_id=row["user_id"],
        email=row.get("email"),
        display_name=row.get("display_name"),
        full_name=row.get("full_name"),
        title=row.get("title"),
        bio=row.get("bio"),
        phone=row.get("phone"),
        location=row.get("location"),
        website=row.get("website"),
        avatar_url="/api/user/avatar" if has_avatar else None,
        updated_at=row.get("updated_at").isoformat()
        if row.get("updated_at")
        else None,
    )


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

@router.get("/profile", response_model=UserProfileDetails)
async def get_user_profile_details(
    user: Dict[str, Any] = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    user_id = user["user_id"]
    email = user.get("email") or user.get("user_email")
    profile = await _ensure_user_profile(db, user_id, email)
    return _profile_to_response(profile)


@router.put("/profile", response_model=UserProfileDetails)
async def update_user_profile_details(
    payload: UserProfileUpdate,
    user: Dict[str, Any] = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    user_id = user["user_id"]
    email = user.get("email") or user.get("user_email")
    updates = payload.model_dump(exclude_unset=True)
    await _ensure_user_profile(db, user_id, email)
    if updates:
        assignments = ", ".join(f"{field} = :{field}" for field in updates)
        updates["user_id"] = user_id
        await db.execute(
            f"UPDATE user_profiles SET {assignments} WHERE user_id = :user_id",
            updates,
        )
    profile = await db.fetch_one(
        "SELECT * FROM user_profiles WHERE user_id = :user_id",
        {"user_id": user_id},
    )
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    return _profile_to_response(dict(profile))


@router.get("/avatar")
async def get_user_avatar(
    user: Dict[str, Any] = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    row = await db.fetch_one(
        "SELECT avatar_bytes, avatar_content_type FROM user_profiles WHERE user_id = :user_id",
        {"user_id": user["user_id"]},
    )
    if not row or not row["avatar_bytes"]:
        raise HTTPException(status_code=404, detail="Avatar not found")
    content_type = row["avatar_content_type"] or "application/octet-stream"
    return Response(content=row["avatar_bytes"], media_type=content_type)


@router.post("/avatar", response_model=UserProfileDetails)
async def upload_user_avatar(
    file: UploadFile = File(...),
    user: Dict[str, Any] = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Avatar must be an image")
    data = await file.read()
    if len(data) > MAX_AVATAR_BYTES:
        raise HTTPException(status_code=400, detail="Avatar exceeds 2MB limit")
    await db.execute(
        """
        INSERT INTO user_profiles (user_id, avatar_bytes, avatar_content_type)
        VALUES (:user_id, :bytes, :content_type)
        ON CONFLICT (user_id)
        DO UPDATE SET avatar_bytes = EXCLUDED.avatar_bytes,
                      avatar_content_type = EXCLUDED.avatar_content_type
        """,
        {
            "user_id": user["user_id"],
            "bytes": data,
            "content_type": file.content_type,
        },
    )
    profile = await db.fetch_one(
        "SELECT * FROM user_profiles WHERE user_id = :user_id",
        {"user_id": user["user_id"]},
    )
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    return _profile_to_response(dict(profile))


@router.delete("/avatar", response_model=UserProfileDetails)
async def delete_user_avatar(
    user: Dict[str, Any] = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    await db.execute(
        """
        UPDATE user_profiles
        SET avatar_bytes = NULL,
            avatar_content_type = NULL
        WHERE user_id = :user_id
        """,
        {"user_id": user["user_id"]},
    )
    profile = await db.fetch_one(
        "SELECT * FROM user_profiles WHERE user_id = :user_id",
        {"user_id": user["user_id"]},
    )
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    return _profile_to_response(dict(profile))


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
