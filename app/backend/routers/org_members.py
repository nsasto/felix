"""
Organization members and invites API.
"""

from typing import Any, Dict

from fastapi import APIRouter, Depends, HTTPException
from databases import Database

from auth import get_current_user
from database.db import get_db
from models import (
    OrganizationInvite,
    OrganizationInviteRequest,
    OrganizationInviteUpdate,
    OrganizationMember,
    OrganizationMemberRoleUpdate,
    OrganizationMembersResponse,
)
from repositories.org_members import OrganizationMembersRepository

router = APIRouter(prefix="/api/orgs", tags=["orgs"])

ALLOWED_ROLES = {"owner", "admin", "member"}


def _ensure_org_access(user: Dict[str, Any], org_id: str) -> None:
    if str(user.get("org_id")) != str(org_id):
        raise HTTPException(status_code=403, detail="Not authorized for org")


@router.get("/{org_id}/members", response_model=OrganizationMembersResponse)
async def list_org_members(
    org_id: str,
    user: Dict[str, Any] = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    _ensure_org_access(user, org_id)
    repo = OrganizationMembersRepository(db)
    members = await repo.list_members(org_id)
    invites = await repo.list_invites(org_id)
    return OrganizationMembersResponse(
        members=[OrganizationMember(**{
            "id": str(m["id"]),
            "org_id": str(m["org_id"]),
            "user_id": m["user_id"],
            "role": m["role"],
            "email": m.get("email"),
            "display_name": m.get("display_name"),
            "full_name": m.get("full_name"),
            "created_at": m["created_at"],
            "updated_at": m.get("updated_at"),
        }) for m in members],
        invites=[OrganizationInvite(**{
            "id": str(i["id"]),
            "org_id": str(i["org_id"]),
            "email": i["email"],
            "role": i["role"],
            "status": i["status"],
            "invited_by_user_id": i.get("invited_by_user_id"),
            "created_at": i["created_at"],
            "updated_at": i["updated_at"],
        }) for i in invites],
    )


@router.post("/{org_id}/invites", response_model=OrganizationInvite, status_code=201)
async def create_org_invite(
    org_id: str,
    payload: OrganizationInviteRequest,
    user: Dict[str, Any] = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    _ensure_org_access(user, org_id)
    role = payload.role.lower()
    if role not in ALLOWED_ROLES:
        raise HTTPException(status_code=400, detail="Invalid role")
    repo = OrganizationMembersRepository(db)
    invite = await repo.create_invite(
        org_id=org_id,
        email=payload.email.lower(),
        role=role,
        invited_by_user_id=user.get("user_id"),
    )
    return OrganizationInvite(
        id=str(invite["id"]),
        org_id=str(invite["org_id"]),
        email=invite["email"],
        role=invite["role"],
        status=invite["status"],
        invited_by_user_id=invite.get("invited_by_user_id"),
        created_at=invite["created_at"],
        updated_at=invite["updated_at"],
    )


@router.patch("/{org_id}/invites/{invite_id}", response_model=OrganizationInvite)
async def update_org_invite(
    org_id: str,
    invite_id: str,
    payload: OrganizationInviteUpdate,
    user: Dict[str, Any] = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    _ensure_org_access(user, org_id)
    role = payload.role.lower()
    if role not in ALLOWED_ROLES:
        raise HTTPException(status_code=400, detail="Invalid role")
    repo = OrganizationMembersRepository(db)
    invite = await repo.update_invite_role(org_id, invite_id, role)
    if not invite:
        raise HTTPException(status_code=404, detail="Invite not found")
    return OrganizationInvite(
        id=str(invite["id"]),
        org_id=str(invite["org_id"]),
        email=invite["email"],
        role=invite["role"],
        status=invite["status"],
        invited_by_user_id=invite.get("invited_by_user_id"),
        created_at=invite["created_at"],
        updated_at=invite["updated_at"],
    )


@router.post("/{org_id}/invites/{invite_id}/resend", response_model=OrganizationInvite)
async def resend_org_invite(
    org_id: str,
    invite_id: str,
    user: Dict[str, Any] = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    _ensure_org_access(user, org_id)
    repo = OrganizationMembersRepository(db)
    invite = await repo.touch_invite(org_id, invite_id)
    if not invite:
        raise HTTPException(status_code=404, detail="Invite not found")
    return OrganizationInvite(
        id=str(invite["id"]),
        org_id=str(invite["org_id"]),
        email=invite["email"],
        role=invite["role"],
        status=invite["status"],
        invited_by_user_id=invite.get("invited_by_user_id"),
        created_at=invite["created_at"],
        updated_at=invite["updated_at"],
    )


@router.delete("/{org_id}/invites/{invite_id}", response_model=OrganizationInvite)
async def revoke_org_invite(
    org_id: str,
    invite_id: str,
    user: Dict[str, Any] = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    _ensure_org_access(user, org_id)
    repo = OrganizationMembersRepository(db)
    invite = await repo.revoke_invite(org_id, invite_id)
    if not invite:
        raise HTTPException(status_code=404, detail="Invite not found")
    return OrganizationInvite(
        id=str(invite["id"]),
        org_id=str(invite["org_id"]),
        email=invite["email"],
        role=invite["role"],
        status=invite["status"],
        invited_by_user_id=invite.get("invited_by_user_id"),
        created_at=invite["created_at"],
        updated_at=invite["updated_at"],
    )


@router.patch("/{org_id}/members/{user_id}", response_model=OrganizationMember)
async def update_member_role(
    org_id: str,
    user_id: str,
    payload: OrganizationMemberRoleUpdate,
    user: Dict[str, Any] = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    _ensure_org_access(user, org_id)
    role = payload.role.lower()
    if role not in ALLOWED_ROLES:
        raise HTTPException(status_code=400, detail="Invalid role")
    repo = OrganizationMembersRepository(db)
    member = await repo.update_member_role(org_id, user_id, role)
    if not member:
        raise HTTPException(status_code=404, detail="Member not found")
    return OrganizationMember(
        id=str(member["id"]),
        org_id=str(member["org_id"]),
        user_id=member["user_id"],
        role=member["role"],
        created_at=member["created_at"],
        updated_at=member.get("updated_at"),
    )


@router.delete("/{org_id}/members/{user_id}")
async def delete_member(
    org_id: str,
    user_id: str,
    user: Dict[str, Any] = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    _ensure_org_access(user, org_id)
    repo = OrganizationMembersRepository(db)
    deleted = await repo.delete_member(org_id, user_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Member not found")
    return {"status": "ok"}
