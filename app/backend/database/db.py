"""
Database connection management module for Felix Backend.

Provides async database connection using the 'databases' library with asyncpg.
"""

import sys
from databases import Database
import config

# Database instance using the DATABASE_URL from config
database = Database(config.DATABASE_URL)


def get_db() -> Database:
    """
    Get the database instance for use as a FastAPI dependency.

    Returns:
        Database: The shared database instance.

    Example:
        @app.get("/items")
        async def get_items(db: Database = Depends(get_db)):
            return await db.fetch_all("SELECT * FROM items")
    """
    return database


async def verify_schema() -> None:
    """
    Verify that the database schema exists and is properly set up.

    Checks for required tables and provides helpful error messages if not found.
    """
    expected_tables = [
        "schema_migrations",
        "organizations",
        "organization_members",
        "settings",
        "projects",
        "requirements",
        "agents",
        "agent_states",
        "agent_profiles",
        "machines",
        "runs",
        "run_artifacts",
    ]

    try:
        # Query for existing tables
        query = """
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public' 
            AND table_type = 'BASE TABLE'
        """
        rows = await database.fetch_all(query)
        existing_tables = [row["table_name"] for row in rows]

        # Check for missing tables
        missing_tables = [t for t in expected_tables if t not in existing_tables]

        if missing_tables:
            print("\n" + "=" * 80, file=sys.stderr)
            print("ERROR: Database schema is not set up!", file=sys.stderr)
            print("=" * 80, file=sys.stderr)
            print(f"\nMissing tables: {', '.join(missing_tables)}", file=sys.stderr)
            print("\nTo set up the database, run:", file=sys.stderr)
            print("  .\\scripts\\setup-db.ps1", file=sys.stderr)
            print("\nOr manually:", file=sys.stderr)
            print('  psql -U postgres -c "CREATE DATABASE felix;"', file=sys.stderr)
            print(
                "  psql -U postgres -d felix -f app\\backend\\migrations\\001_initial_schema.sql",
                file=sys.stderr,
            )
            print(
                "  psql -U postgres -d felix -f app\\backend\\migrations\\001_seed_dev_data.sql",
                file=sys.stderr,
            )
            print("\n" + "=" * 80, file=sys.stderr)
            sys.exit(1)

        # Check migration tracking
        migration_count = await database.fetch_val(
            "SELECT COUNT(*) FROM schema_migrations"
        )
        print(
            f"✓ Database schema verified ({len(existing_tables)} tables, {migration_count} migrations applied)"
        )

    except Exception as e:
        print("\n" + "=" * 80, file=sys.stderr)
        print("ERROR: Cannot connect to database or verify schema!", file=sys.stderr)
        print("=" * 80, file=sys.stderr)
        print(f"\nError: {e}", file=sys.stderr)
        print(f"\nDatabase URL: {config.DATABASE_URL}", file=sys.stderr)
        print("\nPlease ensure:", file=sys.stderr)
        print(
            "  1. PostgreSQL is running (pg_ctl.exe -D C:\\dev\\postgres\\pgsql\\data start)",
            file=sys.stderr,
        )
        print("  2. Database 'felix' exists", file=sys.stderr)
        print(
            "  3. Migrations have been applied (.\\scripts\\setup-db.ps1)",
            file=sys.stderr,
        )
        print("\n" + "=" * 80, file=sys.stderr)
        sys.exit(1)


async def startup() -> None:
    """
    Connect to the database. Should be called during FastAPI app startup.

    Logs a success message when connection is established.
    Verifies schema exists and provides helpful errors if not.
    """
    await database.connect()
    print("Database connection established successfully.")

    # Verify schema is set up
    await verify_schema()


async def shutdown() -> None:
    """
    Disconnect from the database. Should be called during FastAPI app shutdown.

    Logs a success message when disconnection is complete.
    """
    await database.disconnect()
    print("Database connection closed successfully.")
