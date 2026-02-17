"""
Tests for API Key Authentication (S-0064: Run Artifact Sync - Production Readiness)

Tests for:
- API key hashing (SHA256)
- API key validation against database
- Expired key rejection
- API key usage logging (audit trail)
- 401 Unauthorized for invalid keys
- 503 Service Unavailable for database errors during auth
"""
import hashlib
import pytest
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, Request, Depends, HTTPException
from fastapi.testclient import TestClient

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from routers.sync import (
    verify_api_key,
    hash_api_key,
    log_api_key_usage,
    ApiKeyInfo,
)
from database.db import get_db


# ============================================================================
# Fake Database Implementation
# ============================================================================

class FakeDatabase:
    """Fake database for testing API key operations."""
    
    def __init__(
        self,
        fetch_one_results: Optional[List[Optional[Dict[str, Any]]]] = None,
        execute_error: Optional[Exception] = None,
        fetch_error: Optional[Exception] = None,
    ) -> None:
        self.fetch_one_results = fetch_one_results or []
        self.fetch_one_index = 0
        self.execute_error = execute_error
        self.fetch_error = fetch_error
        self.last_query: Optional[str] = None
        self.last_values: Optional[Dict[str, Any]] = None
        self.executed_queries: List[tuple] = []

    async def fetch_one(self, query: str, values: Dict[str, Any] | None = None):
        self.last_query = query
        self.last_values = values
        self.executed_queries.append((query, values))
        
        if self.fetch_error:
            raise self.fetch_error
        
        if self.fetch_one_index < len(self.fetch_one_results):
            result = self.fetch_one_results[self.fetch_one_index]
            self.fetch_one_index += 1
            return result
        return None

    async def execute(self, query: str, values: Dict[str, Any] | None = None):
        self.last_query = query
        self.last_values = values
        self.executed_queries.append((query, values))
        if self.execute_error:
            raise self.execute_error
        return None


# ============================================================================
# Hash API Key Tests
# ============================================================================

class TestHashApiKey:
    """Tests for API key hashing function."""

    def test_hash_api_key_returns_hex_string(self):
        """hash_api_key returns a hexadecimal string."""
        result = hash_api_key("test_key")
        
        # Should be 64 characters (256 bits / 4 bits per hex char)
        assert len(result) == 64
        # Should be valid hex
        assert all(c in "0123456789abcdef" for c in result)

    def test_hash_api_key_consistent(self):
        """hash_api_key returns same hash for same input."""
        key = "fsk_test_api_key_12345"
        
        hash1 = hash_api_key(key)
        hash2 = hash_api_key(key)
        
        assert hash1 == hash2

    def test_hash_api_key_different_inputs(self):
        """hash_api_key returns different hashes for different inputs."""
        hash1 = hash_api_key("key1")
        hash2 = hash_api_key("key2")
        
        assert hash1 != hash2

    def test_hash_api_key_matches_sha256(self):
        """hash_api_key matches Python's SHA256."""
        key = "fsk_my_secret_key"
        expected = hashlib.sha256(key.encode('utf-8')).hexdigest()
        
        result = hash_api_key(key)
        
        assert result == expected


# ============================================================================
# API Key Validation Tests
# ============================================================================

class TestVerifyApiKey:
    """Tests for API key validation."""

    @pytest.mark.asyncio
    async def test_returns_none_when_no_authorization_header(self):
        """Returns None when no Authorization header provided."""
        fake_db = FakeDatabase()
        
        result = await verify_api_key(authorization=None, db=fake_db)
        
        assert result is None

    @pytest.mark.asyncio
    async def test_returns_none_when_empty_authorization_header(self):
        """Returns None when Authorization header is empty."""
        fake_db = FakeDatabase()
        
        result = await verify_api_key(authorization="", db=fake_db)
        
        assert result is None

    @pytest.mark.asyncio
    async def test_returns_none_when_bearer_token_empty(self):
        """Returns None when Bearer token part is empty."""
        fake_db = FakeDatabase()
        
        result = await verify_api_key(authorization="Bearer ", db=fake_db)
        
        assert result is None

    @pytest.mark.asyncio
    async def test_extracts_token_from_bearer_format(self):
        """Extracts token from 'Bearer <token>' format."""
        key = "fsk_test_key_12345"
        key_hash = hash_api_key(key)
        
        fake_db = FakeDatabase(fetch_one_results=[
            {"id": "key-001", "agent_id": None, "name": "Test Key", "expires_at": None}
        ])
        
        result = await verify_api_key(authorization=f"Bearer {key}", db=fake_db)
        
        # Verify the hash was looked up in the first query (SELECT from api_keys)
        select_queries = [v for q, v in fake_db.executed_queries if "SELECT" in q and v]
        assert len(select_queries) >= 1
        assert select_queries[0]["key_hash"] == key_hash
        assert result is not None
        assert result.key_id == "key-001"

    @pytest.mark.asyncio
    async def test_accepts_token_without_bearer_prefix(self):
        """Accepts token without 'Bearer ' prefix."""
        key = "fsk_direct_key_12345"
        key_hash = hash_api_key(key)
        
        fake_db = FakeDatabase(fetch_one_results=[
            {"id": "key-002", "agent_id": None, "name": "Direct Key", "expires_at": None}
        ])
        
        result = await verify_api_key(authorization=key, db=fake_db)
        
        # Verify the hash was looked up in the first query (SELECT from api_keys)
        select_queries = [v for q, v in fake_db.executed_queries if "SELECT" in q and v]
        assert len(select_queries) >= 1
        assert select_queries[0]["key_hash"] == key_hash
        assert result is not None

    @pytest.mark.asyncio
    async def test_raises_401_for_invalid_key(self):
        """Raises HTTPException 401 for key not in database."""
        fake_db = FakeDatabase(fetch_one_results=[None])  # Key not found
        
        with pytest.raises(HTTPException) as exc_info:
            await verify_api_key(authorization="Bearer invalid_key", db=fake_db)
        
        assert exc_info.value.status_code == 401
        assert "Invalid API key" in exc_info.value.detail

    @pytest.mark.asyncio
    async def test_raises_401_for_expired_key(self):
        """Raises HTTPException 401 for expired key."""
        expired_time = datetime.now(timezone.utc) - timedelta(hours=1)
        
        fake_db = FakeDatabase(fetch_one_results=[
            {"id": "key-003", "agent_id": None, "name": "Expired Key", "expires_at": expired_time}
        ])
        
        with pytest.raises(HTTPException) as exc_info:
            await verify_api_key(authorization="Bearer expired_key", db=fake_db)
        
        assert exc_info.value.status_code == 401
        assert "expired" in exc_info.value.detail.lower()

    @pytest.mark.asyncio
    async def test_accepts_key_with_future_expiration(self):
        """Accepts key with expiration in the future."""
        future_time = datetime.now(timezone.utc) + timedelta(days=30)
        
        fake_db = FakeDatabase(fetch_one_results=[
            {"id": "key-004", "agent_id": None, "name": "Future Key", "expires_at": future_time}
        ])
        
        result = await verify_api_key(authorization="Bearer valid_future_key", db=fake_db)
        
        assert result is not None
        assert result.key_id == "key-004"

    @pytest.mark.asyncio
    async def test_accepts_key_with_no_expiration(self):
        """Accepts key with no expiration (expires_at is None)."""
        fake_db = FakeDatabase(fetch_one_results=[
            {"id": "key-005", "agent_id": None, "name": "No Expiry", "expires_at": None}
        ])
        
        result = await verify_api_key(authorization="Bearer never_expires", db=fake_db)
        
        assert result is not None
        assert result.key_id == "key-005"

    @pytest.mark.asyncio
    async def test_returns_api_key_info_with_all_fields(self):
        """Returns ApiKeyInfo with all fields populated."""
        fake_db = FakeDatabase(fetch_one_results=[
            {
                "id": "key-006",
                "agent_id": "agent-001",
                "name": "Agent Specific Key",
                "expires_at": None
            }
        ])
        
        result = await verify_api_key(authorization="Bearer agent_key", db=fake_db)
        
        assert isinstance(result, ApiKeyInfo)
        assert result.key_id == "key-006"
        assert result.agent_id == "agent-001"
        assert result.name == "Agent Specific Key"

    @pytest.mark.asyncio
    async def test_updates_last_used_at_on_successful_validation(self):
        """Updates last_used_at timestamp on successful validation."""
        fake_db = FakeDatabase(fetch_one_results=[
            {"id": "key-007", "agent_id": None, "name": "Test", "expires_at": None}
        ])
        
        await verify_api_key(authorization="Bearer test_key", db=fake_db)
        
        # Check that UPDATE query was executed
        update_queries = [q for q, _ in fake_db.executed_queries if "UPDATE" in q]
        assert len(update_queries) >= 1
        assert "last_used_at" in update_queries[0]

    @pytest.mark.asyncio
    async def test_raises_503_on_database_connection_error(self):
        """Raises HTTPException 503 on database connection error."""
        # Use ConnectionRefusedError which is in DATABASE_CONNECTION_ERRORS
        fake_db = FakeDatabase(fetch_error=ConnectionRefusedError("Database unavailable"))
        
        with pytest.raises(HTTPException) as exc_info:
            await verify_api_key(authorization="Bearer any_key", db=fake_db)
        
        assert exc_info.value.status_code == 503
        assert "unavailable" in exc_info.value.detail.lower()

    @pytest.mark.asyncio
    async def test_handles_timezone_naive_expires_at(self):
        """Handles timezone-naive expires_at datetime correctly."""
        # Some databases return naive datetimes
        naive_future = datetime.utcnow() + timedelta(days=1)
        
        fake_db = FakeDatabase(fetch_one_results=[
            {"id": "key-008", "agent_id": None, "name": "Naive TZ", "expires_at": naive_future}
        ])
        
        result = await verify_api_key(authorization="Bearer naive_tz_key", db=fake_db)
        
        assert result is not None


# ============================================================================
# API Key Usage Logging Tests
# ============================================================================

class TestLogApiKeyUsage:
    """Tests for API key usage audit logging."""

    @pytest.mark.asyncio
    async def test_does_nothing_when_api_key_is_none(self):
        """Does nothing when api_key is None."""
        fake_db = FakeDatabase()
        fake_request = MagicMock()
        
        await log_api_key_usage(
            db=fake_db,
            api_key=None,
            endpoint="/api/runs",
            request=fake_request,
        )
        
        # No queries should be executed
        assert len(fake_db.executed_queries) == 0

    @pytest.mark.asyncio
    async def test_inserts_usage_log_record(self):
        """Inserts usage log record when api_key provided."""
        fake_db = FakeDatabase()
        fake_request = MagicMock()
        fake_request.client = MagicMock()
        fake_request.client.host = "192.168.1.100"
        fake_request.headers = {"User-Agent": "Felix-CLI/1.0"}
        
        api_key = ApiKeyInfo(key_id="key-001", agent_id=None, name="Test Key")
        
        await log_api_key_usage(
            db=fake_db,
            api_key=api_key,
            endpoint="/api/runs",
            request=fake_request,
            agent_id="agent-001",
        )
        
        # Verify INSERT was executed
        insert_queries = [q for q, v in fake_db.executed_queries if "INSERT INTO api_key_usage_log" in q]
        assert len(insert_queries) == 1

    @pytest.mark.asyncio
    async def test_logs_client_ip_from_request(self):
        """Logs client IP from request.client.host."""
        fake_db = FakeDatabase()
        fake_request = MagicMock()
        fake_request.client = MagicMock()
        fake_request.client.host = "10.0.0.1"
        fake_request.headers = {}
        
        api_key = ApiKeyInfo(key_id="key-001", agent_id=None, name="Test")
        
        await log_api_key_usage(
            db=fake_db,
            api_key=api_key,
            endpoint="/api/runs",
            request=fake_request,
        )
        
        # Check logged IP
        assert fake_db.last_values["ip_address"] == "10.0.0.1"

    @pytest.mark.asyncio
    async def test_logs_ip_from_x_forwarded_for_header(self):
        """Logs client IP from X-Forwarded-For header when present."""
        fake_db = FakeDatabase()
        fake_request = MagicMock()
        fake_request.client = MagicMock()
        fake_request.client.host = "127.0.0.1"  # Proxy IP
        fake_request.headers = {"X-Forwarded-For": "203.0.113.50, 198.51.100.10"}
        
        api_key = ApiKeyInfo(key_id="key-001", agent_id=None, name="Test")
        
        await log_api_key_usage(
            db=fake_db,
            api_key=api_key,
            endpoint="/api/runs",
            request=fake_request,
        )
        
        # Should use first IP from X-Forwarded-For (original client)
        assert fake_db.last_values["ip_address"] == "203.0.113.50"

    @pytest.mark.asyncio
    async def test_truncates_long_user_agent(self):
        """Truncates user agent to prevent overflow."""
        fake_db = FakeDatabase()
        fake_request = MagicMock()
        fake_request.client = MagicMock()
        fake_request.client.host = "10.0.0.1"
        fake_request.headers = {"User-Agent": "A" * 1000}  # Very long user agent
        
        api_key = ApiKeyInfo(key_id="key-001", agent_id=None, name="Test")
        
        await log_api_key_usage(
            db=fake_db,
            api_key=api_key,
            endpoint="/api/runs",
            request=fake_request,
        )
        
        # User agent should be truncated
        assert len(fake_db.last_values["user_agent"]) <= 500

    @pytest.mark.asyncio
    async def test_logs_success_status(self):
        """Logs success status correctly."""
        fake_db = FakeDatabase()
        fake_request = MagicMock()
        fake_request.client = MagicMock()
        fake_request.client.host = "10.0.0.1"
        fake_request.headers = {}
        
        api_key = ApiKeyInfo(key_id="key-001", agent_id=None, name="Test")
        
        await log_api_key_usage(
            db=fake_db,
            api_key=api_key,
            endpoint="/api/runs",
            request=fake_request,
            success=True,
        )
        
        assert fake_db.last_values["success"] is True
        
        # Test failure case
        fake_db.executed_queries.clear()
        await log_api_key_usage(
            db=fake_db,
            api_key=api_key,
            endpoint="/api/runs",
            request=fake_request,
            success=False,
        )
        
        assert fake_db.last_values["success"] is False

    @pytest.mark.asyncio
    async def test_handles_missing_client(self):
        """Handles missing client gracefully."""
        fake_db = FakeDatabase()
        fake_request = MagicMock()
        fake_request.client = None
        fake_request.headers = {}
        
        api_key = ApiKeyInfo(key_id="key-001", agent_id=None, name="Test")
        
        # Should not raise
        await log_api_key_usage(
            db=fake_db,
            api_key=api_key,
            endpoint="/api/runs",
            request=fake_request,
        )

    @pytest.mark.asyncio
    async def test_does_not_fail_on_database_error(self):
        """Does not raise exception on database error (fire-and-forget)."""
        fake_db = FakeDatabase(execute_error=Exception("Database error"))
        fake_request = MagicMock()
        fake_request.client = MagicMock()
        fake_request.client.host = "10.0.0.1"
        fake_request.headers = {}
        
        api_key = ApiKeyInfo(key_id="key-001", agent_id=None, name="Test")
        
        # Should not raise, just log warning
        await log_api_key_usage(
            db=fake_db,
            api_key=api_key,
            endpoint="/api/runs",
            request=fake_request,
        )


# ============================================================================
# Integration Tests with Sync Endpoints
# ============================================================================

class TestApiKeyIntegration:
    """Integration tests for API key authentication on sync endpoints."""

    @pytest.fixture
    def client(self):
        """Create test client with clean overrides."""
        from main import app
        app.dependency_overrides.clear()
        yield TestClient(app)
        app.dependency_overrides.clear()

    def test_sync_endpoint_accepts_valid_api_key(self, client):
        """Sync endpoint accepts valid API key."""
        from main import app
        
        key = "fsk_valid_test_key"
        key_hash = hash_api_key(key)
        
        class FakeDB:
            async def fetch_one(self, query, values=None):
                if "api_keys" in query:
                    return {
                        "id": "key-001",
                        "agent_id": None,
                        "name": "Test Key",
                        "expires_at": None
                    }
                elif "agents" in query:
                    return {"id": "agent-001"}
                elif "projects" in query:
                    return {"id": "project-001"}
                return None
            
            async def execute(self, query, values=None):
                return None
        
        app.dependency_overrides[get_db] = lambda: FakeDB()
        
        # Reset rate limiter to avoid 429
        from middleware.rate_limit import reset_rate_limiter
        reset_rate_limiter()
        
        response = client.post(
            "/api/runs",
            json={
                "agent_id": "agent-001",
                "project_id": "project-001"
            },
            headers={"Authorization": f"Bearer {key}"}
        )
        
        # Should not be 401
        assert response.status_code != 401

    def test_sync_endpoint_rejects_invalid_api_key(self, client):
        """Sync endpoint rejects invalid API key with 401."""
        from main import app
        
        class FakeDB:
            async def fetch_one(self, query, values=None):
                if "api_keys" in query:
                    return None  # Key not found
                return None
            
            async def execute(self, query, values=None):
                return None
        
        app.dependency_overrides[get_db] = lambda: FakeDB()
        
        # Reset rate limiter
        from middleware.rate_limit import reset_rate_limiter
        reset_rate_limiter()
        
        response = client.post(
            "/api/runs",
            json={
                "agent_id": "agent-001",
                "project_id": "project-001"
            },
            headers={"Authorization": "Bearer invalid_key"}
        )
        
        assert response.status_code == 401
        assert "Invalid API key" in response.json()["detail"]

    def test_sync_endpoint_allows_no_api_key(self, client):
        """Sync endpoint allows requests without API key (for dev mode)."""
        from main import app
        
        class FakeDB:
            async def fetch_one(self, query, values=None):
                if "agents" in query:
                    return {"id": "agent-001"}
                elif "projects" in query:
                    return {"id": "project-001"}
                return None
            
            async def execute(self, query, values=None):
                return None
        
        app.dependency_overrides[get_db] = lambda: FakeDB()
        
        # Reset rate limiter
        from middleware.rate_limit import reset_rate_limiter
        reset_rate_limiter()
        
        # No Authorization header
        response = client.post(
            "/api/runs",
            json={
                "agent_id": "agent-001",
                "project_id": "project-001"
            }
        )
        
        # Should not be 401
        assert response.status_code != 401
