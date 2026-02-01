"""
Database writers module for Felix Backend.

Provides AgentWriter and RunWriter classes that encapsulate all CRUD operations
for agents, runs, and artifacts.
"""

import json
import logging
from typing import Dict, List, Optional, Any

from databases import Database


# Configure logging
logger = logging.getLogger(__name__)


# ============================================================================
# Custom Exceptions
# ============================================================================


class AgentNotFoundError(Exception):
    """Raised when an agent lookup fails."""

    def __init__(self, agent_id: str):
        self.agent_id = agent_id
        super().__init__(f"Agent not found: {agent_id}")


class RunNotFoundError(Exception):
    """Raised when a run lookup fails."""

    def __init__(self, run_id: str):
        self.run_id = run_id
        super().__init__(f"Run not found: {run_id}")
