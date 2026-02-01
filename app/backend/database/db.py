"""
Database connection management module for Felix Backend.

Provides async database connection using the 'databases' library with asyncpg.
"""

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


async def startup() -> None:
    """
    Connect to the database. Should be called during FastAPI app startup.

    Logs a success message when connection is established.
    """
    await database.connect()
    print("Database connection established successfully.")


async def shutdown() -> None:
    """
    Disconnect from the database. Should be called during FastAPI app shutdown.

    Logs a success message when disconnection is complete.
    """
    await database.disconnect()
    print("Database connection closed successfully.")
