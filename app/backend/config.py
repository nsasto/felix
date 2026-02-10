"""
Configuration module for Felix Backend.

Loads environment variables from .env file and provides defaults.
"""

import os
from dotenv import load_dotenv

# Load .env file (redundant with main.py but ensures config works standalone)
load_dotenv()

# Default UUID for development (all zeros with trailing 1)
_DEFAULT_DEV_UUID = "-".join(["0" * 8, "0" * 4, "0" * 4, "0" * 4, "0" * 11 + "1"])

# Database Configuration
# Requires DATABASE_URL environment variable to be set
DATABASE_URL: str = os.getenv("DATABASE_URL", "")

# Authentication Configuration
# When AUTH_MODE=disabled, dev mode credentials are used
# When AUTH_MODE=enabled, Supabase Auth will be required (Phase 2)
AUTH_MODE: str = os.getenv("AUTH_MODE", "disabled")

# Development Mode Defaults (used when AUTH_MODE=disabled)
DEV_ORG_ID: str = os.getenv("DEV_ORG_ID", _DEFAULT_DEV_UUID)
DEV_PROJECT_ID: str = os.getenv("DEV_PROJECT_ID", _DEFAULT_DEV_UUID)
DEV_USER_ID: str = os.getenv("DEV_USER_ID", "nsasto")
