"""
User router for Felix Backend.

Provides endpoints for retrieving current user information.
"""

from typing import Any, Dict
from fastapi import APIRouter, Depends
from databases import Database
from database.db import get_db
from auth import get_current_user

router = APIRouter(prefix="/api/user", tags=["user"])


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
    org_id = user["org_id"]

    # Get organization details
    org_query = """
        SELECT name, slug, owner_id, metadata
        FROM organizations
        WHERE id = :org_id
    """
    org = await db.fetch_one(org_query, {"org_id": org_id})

    if not org:
        return {
            "user_id": user_id,
            "email": None,
            "organization": None,
            "org_slug": None,
            "role": user.get("role", "member"),
        }

    # Extract email from org metadata or generate from user_id
    email = (
        org["metadata"].get("email") if org["metadata"] else f"{user_id}@example.com"
    )

    return {
        "user_id": user_id,
        "email": email,
        "organization": org["name"],
        "org_slug": org["slug"],
        "role": user.get("role", "member"),
    }
