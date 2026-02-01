"""
Felix Backend - FastAPI Server
Provides HTTP API and WebSocket for observing and controlling Felix agents.
"""

import json
import logging
from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from dotenv import load_dotenv

# Load .env file for environment variables (like FELIX_COPILOT_API_KEY)
load_dotenv()

from fastapi import Depends
from databases import Database

from routers import (
    projects,
    files,
    runs,
    agents,
    settings,
    copilot,
    agent_configs,
)
import storage
from database.db import startup as db_startup, shutdown as db_shutdown, get_db
from auth import get_current_user

# Configure logger
logger = logging.getLogger(__name__)


def migrate_agent_config():
    """
    Migrate legacy inline agent config to new agent_id reference system.

    This function runs at startup and handles:
    1. If config.json has legacy inline agent object (with name/executable fields):
       - Ensure agents.json exists with the agent as ID 0
       - Update config.json to use agent_id: 0
    2. If agents.json is missing:
       - Create it with a default system agent as ID 0
    3. If config.json has agent_id but agents.json is missing:
       - Create agents.json with default agent, set agent_id to 0
    """
    felix_home = storage.get_felix_home()
    config_path = felix_home / "config.json"
    agents_path = felix_home / "agents.json"

    # Default agent configuration
    default_agent = {
        "id": 0,
        "name": "felix-primary",
        "executable": "droid",
        "args": ["exec", "--skip-permissions-unsafe"],
        "working_directory": ".",
        "environment": {},
    }

    # Load config.json if it exists
    config_data = None
    if config_path.exists():
        try:
            config_data = json.loads(config_path.read_text(encoding="utf-8-sig"))
        except json.JSONDecodeError as e:
            logger.warning(f"Failed to parse config.json during migration: {e}")
            config_data = None

    # Load agents.json if it exists
    agents_data = None
    if agents_path.exists():
        try:
            agents_data = json.loads(agents_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            logger.warning(f"Failed to parse agents.json during migration: {e}")
            agents_data = None

    migration_needed = False
    config_changed = False
    agents_changed = False

    # Ensure agents.json exists with at least ID 0
    if agents_data is None:
        agents_data = {"agents": []}
        agents_changed = True

    # Check if ID 0 exists in agents.json
    agents_list = agents_data.get("agents", [])
    has_id_0 = any(agent.get("id") == 0 for agent in agents_list)

    if not has_id_0:
        # Need to add default agent with ID 0
        logger.info("Creating system default agent (ID 0) in agents.json")

        # If config has legacy inline agent, use that as ID 0
        if config_data:
            agent_config = config_data.get("agent", {})
            if "name" in agent_config or "executable" in agent_config:
                # Legacy inline agent - use it as the default
                default_agent = {
                    "id": 0,
                    "name": agent_config.get("name", "felix-primary"),
                    "executable": agent_config.get("executable", "droid"),
                    "args": agent_config.get(
                        "args", ["exec", "--skip-permissions-unsafe"]
                    ),
                    "working_directory": agent_config.get("working_directory", "."),
                    "environment": agent_config.get("environment", {}),
                }
                logger.info(
                    f"Migrating legacy agent '{default_agent['name']}' to agents.json as ID 0"
                )

        agents_list.insert(0, default_agent)
        agents_data["agents"] = agents_list
        agents_changed = True
        migration_needed = True

    # Check if config.json needs migration to use agent_id
    if config_data:
        agent_config = config_data.get("agent", {})

        # Check for legacy inline agent (has name/executable but no agent_id)
        has_legacy_fields = "name" in agent_config or "executable" in agent_config
        has_agent_id = "agent_id" in agent_config

        if has_legacy_fields and not has_agent_id:
            # Migrate to agent_id format
            logger.info(
                "Migrating config.json from legacy inline agent to agent_id reference"
            )

            # Replace legacy agent config with agent_id reference
            config_data["agent"] = {"agent_id": 0}
            config_changed = True
            migration_needed = True
        elif not has_agent_id:
            # No agent config at all, add default agent_id: 0
            logger.info("Adding default agent_id: 0 to config.json")
            config_data["agent"] = {"agent_id": 0}
            config_changed = True

    # Save changes
    if agents_changed:
        try:
            agents_path.parent.mkdir(parents=True, exist_ok=True)
            agents_path.write_text(json.dumps(agents_data, indent=2), encoding="utf-8")
            logger.info(f"Saved agents.json to {agents_path}")
        except Exception as e:
            logger.error(f"Failed to save agents.json: {e}")

    if config_changed and config_data:
        try:
            config_path.parent.mkdir(parents=True, exist_ok=True)
            config_path.write_text(json.dumps(config_data, indent=2), encoding="utf-8")
            logger.info(f"Saved config.json to {config_path}")
        except Exception as e:
            logger.error(f"Failed to save config.json: {e}")

    if migration_needed:
        logger.info("Agent configuration migration completed successfully")
    else:
        logger.debug("No agent configuration migration needed")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    print("Felix Backend starting...")

    # Run agent config migration
    try:
        migrate_agent_config()
    except Exception as e:
        logger.error(f"Agent config migration failed: {e}")

    # Connect to database
    await db_startup()

    yield

    # Shutdown
    print("Felix Backend shutting down...")

    # Disconnect from database
    await db_shutdown()

    # Clean up any running agent processes
    running_agents = runs.get_running_agents()
    if running_agents:
        print(f"Terminating {len(running_agents)} running agent(s)...")
        import os
        import signal

        for project_id, info in running_agents.items():
            try:
                os.kill(info.pid, signal.SIGTERM)
                print(f"  Terminated agent for project {project_id} (PID: {info.pid})")
            except (OSError, ProcessLookupError):
                pass  # Process already dead


app = FastAPI(
    title="Felix Backend",
    description="API for Felix - Ralph-style autonomous software delivery",
    version="0.1.0",
    lifespan=lifespan,
)

# CORS configuration for frontend (React on port 3000)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(projects.router)
app.include_router(files.router)
app.include_router(runs.router)
app.include_router(agents.router)
app.include_router(settings.router)
app.include_router(copilot.router)
app.include_router(agent_configs.router)


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "felix-backend", "version": "0.1.0"}


@app.get("/")
async def root():
    """Root endpoint with basic info"""
    return {
        "name": "Felix Backend",
        "description": "Ralph-style autonomous software delivery system",
        "docs": "/docs",
        "health": "/health",
    }


@app.get("/test/db")
async def test_db(
    user: dict = Depends(get_current_user),
    db: Database = Depends(get_db),
):
    """
    Test endpoint to verify database connection and authentication.

    Returns:
        JSON with user context and organization count from database.
    """
    result = await db.fetch_one("SELECT COUNT(*) as count FROM organizations")
    org_count = result["count"] if result else 0

    return {
        "user": user,
        "org_count": org_count,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8080, reload=True, log_level="info")
