"""
Integration test for agent profiles against a real database.

Skipped unless FELIX_INTEGRATION_DB=1 is set.
"""
import os
import uuid

import pytest
from databases import Database

import config
from repositories import PostgresAgentProfileRepository
from routers.agent_configs import get_active_agent_id, set_active_agent_id


@pytest.mark.asyncio
@pytest.mark.integration
async def test_agent_profiles_round_trip_integration():
    if os.getenv("FELIX_INTEGRATION_DB") != "1":
        pytest.skip("FELIX_INTEGRATION_DB is not set; skipping integration test")

    db = Database(config.DATABASE_URL)
    await db.connect()

    org_id = str(uuid.uuid4())
    try:
        await db.execute(
            """
            INSERT INTO organizations (id, name, slug, owner_id, created_at, updated_at)
            VALUES (:id, :name, :slug, :owner_id, NOW(), NOW())
            """,
            values={
                "id": org_id,
                "name": "integration-org",
                "slug": f"integration-{org_id[:8]}",
                "owner_id": config.DEV_USER_ID,
            },
        )

        repo = PostgresAgentProfileRepository(db)
        profile = await repo.create_profile(
            org_id=org_id,
            name="integration-profile",
            adapter="droid",
            executable="droid",
            args=[],
            model=None,
            working_directory=".",
            environment={},
            description=None,
            source="test",
            created_by_user_id=config.DEV_USER_ID,
        )
        profile_id = str(profile["id"])

        fetched = await repo.get_by_id(org_id, profile_id)
        assert fetched is not None
        assert fetched["name"] == "integration-profile"

        await set_active_agent_id(db, org_id, profile_id)
        active_id = await get_active_agent_id(db, org_id)
        assert active_id == profile_id

        await repo.update_profile(profile_id, {"name": "integration-updated"})
        updated = await repo.get_by_id(org_id, profile_id)
        assert updated["name"] == "integration-updated"

        await repo.delete_profile(profile_id)
        missing = await repo.get_by_id(org_id, profile_id)
        assert missing is None
    finally:
        await db.execute(
            "DELETE FROM agent_profiles WHERE org_id = :org_id",
            values={"org_id": org_id},
        )
        await db.execute(
            "DELETE FROM organizations WHERE id = :id",
            values={"id": org_id},
        )
        await db.disconnect()
