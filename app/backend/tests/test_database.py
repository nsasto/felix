"""
Tests for the Database Integration Layer (S-0036)

Tests for:
- config.py - Environment variable loading
- auth.py - Authentication shim (dev mode and enabled mode)
- database/db.py - Database module imports
"""
import pytest
from starlette.requests import Request
from pathlib import Path
from unittest.mock import patch
import sys

# Ensure imports work from tests directory
sys.path.insert(0, str(Path(__file__).parent.parent))


class TestConfig:
    """Tests for config.py module"""

    def test_config_loads_database_url(self):
        """Config module loads DATABASE_URL from environment"""
        import config
        # DATABASE_URL should be loaded (could be empty string if not set)
        assert hasattr(config, "DATABASE_URL")
        assert isinstance(config.DATABASE_URL, str)

    def test_config_loads_auth_mode(self):
        """Config module loads AUTH_MODE with default 'disabled'"""
        import config
        assert hasattr(config, "AUTH_MODE")
        assert isinstance(config.AUTH_MODE, str)
        # Default should be 'disabled' when not set
        # If .env is loaded, could be 'disabled' or 'enabled'
        assert config.AUTH_MODE in ("disabled", "enabled")

    def test_config_loads_dev_org_id(self):
        """Config module loads DEV_ORG_ID with default UUID"""
        import config
        assert hasattr(config, "DEV_ORG_ID")
        assert isinstance(config.DEV_ORG_ID, str)
        # Should be a valid UUID format (8-4-4-4-12 pattern)
        parts = config.DEV_ORG_ID.split("-")
        assert len(parts) == 5

    def test_config_loads_dev_project_id(self):
        """Config module loads DEV_PROJECT_ID with default UUID"""
        import config
        assert hasattr(config, "DEV_PROJECT_ID")
        assert isinstance(config.DEV_PROJECT_ID, str)
        # Should be a valid UUID format (8-4-4-4-12 pattern)
        parts = config.DEV_PROJECT_ID.split("-")
        assert len(parts) == 5

    def test_config_loads_dev_user_id(self):
        """Config module loads DEV_USER_ID with default value"""
        import config
        assert hasattr(config, "DEV_USER_ID")
        assert isinstance(config.DEV_USER_ID, str)
        assert len(config.DEV_USER_ID) > 0


class TestAuth:
    """Tests for auth.py module"""

    def _make_request(self):
        return Request({"type": "http", "headers": []})

    @pytest.mark.asyncio
    async def test_get_current_user_returns_dict_in_dev_mode(self):
        """get_current_user returns user dict when AUTH_MODE=disabled"""
        with patch("config.AUTH_MODE", "disabled"), \
             patch("config.DEV_USER_ID", "test-user"), \
             patch("config.DEV_ORG_ID", "test-org-id"):
            # Re-import to pick up patched values
            import auth
            # Patch the config module that auth imports
            auth.config.AUTH_MODE = "disabled"
            auth.config.DEV_USER_ID = "test-user"
            auth.config.DEV_ORG_ID = "test-org-id"

            user = await auth.get_current_user(self._make_request())

            assert isinstance(user, dict)
            assert "user_id" in user
            assert "org_id" in user
            assert "role" in user
            assert user["user_id"] == "test-user"
            assert user["org_id"] == "test-org-id"
            assert user["role"] == "owner"

    @pytest.mark.asyncio
    async def test_get_current_user_raises_not_implemented_when_enabled(self):
        """get_current_user raises NotImplementedError when AUTH_MODE=enabled"""
        import auth
        # Save original value
        original_mode = auth.config.AUTH_MODE
        try:
            auth.config.AUTH_MODE = "enabled"
            
            with pytest.raises(NotImplementedError) as exc_info:
                await auth.get_current_user(self._make_request())
            
            assert "Supabase Auth" in str(exc_info.value)
        finally:
            # Restore original value
            auth.config.AUTH_MODE = original_mode


class TestDatabaseModule:
    """Tests for database/db.py module"""

    def test_database_module_imports(self):
        """Database module can be imported successfully"""
        from database.db import database, startup, shutdown, get_db
        
        # Verify imports exist and have correct types
        assert database is not None
        assert callable(startup)
        assert callable(shutdown)
        assert callable(get_db)

    def test_get_db_returns_database_instance(self):
        """get_db() returns the database instance"""
        from database.db import database, get_db
        
        db = get_db()
        assert db is database

    def test_startup_is_async_function(self):
        """startup() is an async function"""
        from database.db import startup
        import inspect
        
        assert inspect.iscoroutinefunction(startup)

    def test_shutdown_is_async_function(self):
        """shutdown() is an async function"""
        from database.db import shutdown
        import inspect
        
        assert inspect.iscoroutinefunction(shutdown)
