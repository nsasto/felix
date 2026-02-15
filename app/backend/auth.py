"""
Authentication module for Felix Backend.

Provides authentication dependencies for FastAPI routes.
In dev mode (AUTH_MODE=disabled), returns mock user credentials.
When AUTH_MODE=enabled, Supabase Auth will be required (Phase 2).
"""

from typing import Any, Dict
import uuid
from fastapi import Request
import config


async def get_current_user(request: Request) -> Dict[str, Any]:
    """
    Get the current authenticated user as a FastAPI dependency.

    When AUTH_MODE=disabled (development mode):
        Returns a dict with dev user credentials from config.

    When AUTH_MODE=enabled (production mode):
        Raises NotImplementedError until Supabase Auth is integrated.

    Returns:
        Dict with user_id, org_id, and role keys.

    Raises:
        NotImplementedError: When AUTH_MODE=enabled (Supabase Auth not yet implemented).

    Example:
        @app.get("/protected")
        async def protected_route(user: dict = Depends(get_current_user)):
            return {"user_id": user["user_id"]}
    """
    if config.AUTH_MODE == "disabled":
        org_id = config.DEV_ORG_ID
        header_org_id = request.headers.get("X-Felix-Org-Id")
        if header_org_id:
            try:
                uuid.UUID(header_org_id)
                org_id = header_org_id
            except ValueError:
                pass
        return {
            "user_id": config.DEV_USER_ID,
            "org_id": org_id,
            "role": "owner",
        }
    else:
        raise NotImplementedError(
            "Supabase Auth integration is not yet implemented. "
            "Set AUTH_MODE=disabled for development mode."
        )
