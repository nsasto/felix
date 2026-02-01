"""
Database module for Felix Backend.

Provides database connection management and writer classes for CRUD operations.
"""

from .db import database, get_db, startup, shutdown
from .writers import (
    AgentWriter,
    RunWriter,
    AgentNotFoundError,
    RunNotFoundError,
)

__all__ = [
    # Connection management
    "database",
    "get_db",
    "startup",
    "shutdown",
    # Writer classes
    "AgentWriter",
    "RunWriter",
    # Exceptions
    "AgentNotFoundError",
    "RunNotFoundError",
]
