"""
Tests for Rate Limiting Middleware (S-0064: Run Artifact Sync - Production Readiness)

Tests for:
- Sliding window rate limiting algorithm
- Rate limit headers (X-RateLimit-*)
- 429 Too Many Requests response
- Rate limit key extraction (API key, IP address)
- Configuration via environment variables
"""

import os
import time
import pytest
from unittest.mock import patch, MagicMock
from pathlib import Path

from fastapi import FastAPI, Depends, Request, Response
from fastapi.testclient import TestClient

import sys

sys.path.insert(0, str(Path(__file__).parent.parent))

from middleware.rate_limit import (
    RateLimiter,
    RateLimitState,
    rate_limit_dependency,
    get_rate_limiter,
    reset_rate_limiter,
    extract_rate_limit_key,
    get_rate_limit_config,
    DEFAULT_RATE_LIMIT,
    DEFAULT_WINDOW_SECONDS,
)


# ============================================================================
# RateLimitState Unit Tests
# ============================================================================


class TestRateLimitState:
    """Tests for RateLimitState sliding window implementation"""

    def test_first_request_allowed(self):
        """First request within limit is allowed"""
        state = RateLimitState()
        now = time.time()

        allowed, remaining, reset_time = state.record_request(now, 60, 100)

        assert allowed is True
        assert remaining == 99
        assert reset_time > now

    def test_requests_within_limit_allowed(self):
        """Multiple requests within limit are allowed"""
        state = RateLimitState()
        now = time.time()

        # Make 50 requests
        for i in range(50):
            allowed, remaining, reset_time = state.record_request(now, 60, 100)
            assert allowed is True
            assert remaining == 99 - i

    def test_requests_exceeding_limit_blocked(self):
        """Requests exceeding limit are blocked"""
        state = RateLimitState()
        now = time.time()

        # Fill up to the limit
        for i in range(100):
            allowed, remaining, reset_time = state.record_request(now, 60, 100)
            assert allowed is True

        # Next request should be blocked
        allowed, remaining, reset_time = state.record_request(now, 60, 100)
        assert allowed is False
        assert remaining == 0

    def test_old_requests_expire_from_window(self):
        """Requests older than window are removed"""
        state = RateLimitState()

        # Record requests at t=0
        t0 = time.time()
        for i in range(100):
            state.record_request(t0, 60, 100)

        # All 100 slots used
        allowed, remaining, _ = state.record_request(t0, 60, 100)
        assert allowed is False

        # Fast forward past the window
        t1 = t0 + 61  # 61 seconds later

        # Old requests should have expired, new request allowed
        allowed, remaining, _ = state.record_request(t1, 60, 100)
        assert allowed is True
        assert remaining == 99  # 100 - 1 (the new request)

    def test_sliding_window_partial_expiry(self):
        """Sliding window correctly handles partial expiry"""
        state = RateLimitState()

        # Record 50 requests at t=0
        t0 = time.time()
        for _ in range(50):
            state.record_request(t0, 60, 100)

        # Record 50 more requests at t=30
        t30 = t0 + 30
        for _ in range(50):
            state.record_request(t30, 60, 100)

        # At t=30, all 100 slots used
        allowed, _, _ = state.record_request(t30, 60, 100)
        assert allowed is False

        # At t=65, the first 50 requests expired (from t=0)
        # Only the 50 from t=30 remain
        t65 = t0 + 65
        allowed, remaining, _ = state.record_request(t65, 60, 100)
        assert allowed is True
        assert remaining == 49  # 100 - 50 (remaining) - 1 (new)


# ============================================================================
# RateLimiter Unit Tests
# ============================================================================


class TestRateLimiter:
    """Tests for RateLimiter class"""

    def test_different_keys_have_separate_limits(self):
        """Different rate limit keys have independent limits"""
        limiter = RateLimiter(max_requests=5, window_seconds=60)

        # Key A uses up its limit
        for _ in range(5):
            allowed, _, _ = limiter.check_rate_limit("key_a")
            assert allowed is True

        # Key A is blocked
        allowed, _, _ = limiter.check_rate_limit("key_a")
        assert allowed is False

        # Key B is still allowed
        allowed, _, _ = limiter.check_rate_limit("key_b")
        assert allowed is True

    def test_cleanup_removes_stale_entries(self):
        """cleanup_old_entries removes entries with no recent activity"""
        limiter = RateLimiter(max_requests=100, window_seconds=60)

        # Create some activity
        limiter.check_rate_limit("active_key")
        limiter.check_rate_limit("stale_key")

        assert len(limiter._states) == 2

        # Simulate time passing and cleanup
        # Manually age the stale key
        stale_state = limiter._states["stale_key"]
        stale_state.timestamps = [time.time() - 400]  # 400 seconds old

        limiter.cleanup_old_entries(max_age_seconds=300)

        # Stale key should be removed, active key preserved
        assert "active_key" in limiter._states
        assert "stale_key" not in limiter._states


# ============================================================================
# Rate Limit Key Extraction Tests
# ============================================================================


class TestRateLimitKeyExtraction:
    """Tests for extract_rate_limit_key function"""

    def test_extract_key_from_bearer_token(self):
        """Extracts key from Authorization Bearer token"""
        request = MagicMock()
        request.headers = {"authorization": "Bearer fsk_test_api_key_12345678"}
        request.client = MagicMock()
        request.client.host = "192.168.1.1"

        key = extract_rate_limit_key(request)

        # Should use first 16 chars of token
        assert key == "api_key:fsk_test_api_key"

    def test_extract_key_from_client_ip(self):
        """Falls back to client IP when no Authorization"""
        request = MagicMock()
        request.headers = {}
        request.client = MagicMock()
        request.client.host = "203.0.113.50"

        key = extract_rate_limit_key(request)

        assert key == "ip:203.0.113.50"

    def test_extract_key_from_x_forwarded_for(self):
        """Uses X-Forwarded-For when present (first IP in chain)"""
        request = MagicMock()
        request.headers = {"x-forwarded-for": "203.0.113.50, 198.51.100.10, 192.0.2.1"}
        request.client = MagicMock()
        request.client.host = "127.0.0.1"  # Proxy IP

        key = extract_rate_limit_key(request)

        # Should use the first (original client) IP
        assert key == "ip:203.0.113.50"

    def test_extract_key_handles_missing_client(self):
        """Handles missing client gracefully"""
        request = MagicMock()
        request.headers = {}
        request.client = None

        key = extract_rate_limit_key(request)

        assert key == "ip:unknown"


# ============================================================================
# Configuration Tests
# ============================================================================


class TestRateLimitConfiguration:
    """Tests for rate limit configuration"""

    def test_default_config_values(self):
        """Default config uses expected values"""
        # Clear any env overrides
        with patch.dict(os.environ, {}, clear=True):
            max_req, window = get_rate_limit_config()

            assert max_req == DEFAULT_RATE_LIMIT
            assert window == DEFAULT_WINDOW_SECONDS

    def test_config_from_env_vars(self):
        """Config reads from environment variables"""
        with patch.dict(
            os.environ, {"FELIX_SYNC_RATE_LIMIT": "200", "FELIX_SYNC_RATE_WINDOW": "30"}
        ):
            max_req, window = get_rate_limit_config()

            assert max_req == 200
            assert window == 30


# ============================================================================
# FastAPI Integration Tests
# ============================================================================


class TestRateLimitDependency:
    """Tests for rate_limit_dependency FastAPI integration"""

    @pytest.fixture(autouse=True)
    def reset_limiter(self):
        """Reset global rate limiter before each test"""
        reset_rate_limiter()
        yield
        reset_rate_limiter()

    @pytest.fixture
    def test_app(self):
        """Create a test FastAPI app with rate limited endpoint"""
        app = FastAPI()

        @app.get("/test")
        async def test_endpoint(
            request: Request,
            response: Response,
            _: None = Depends(rate_limit_dependency),
        ):
            return {"message": "success"}

        return app

    def test_adds_rate_limit_headers(self, test_app):
        """Rate limit dependency adds X-RateLimit-* headers"""
        with patch.dict(
            os.environ, {"FELIX_SYNC_RATE_LIMIT": "100", "FELIX_SYNC_RATE_WINDOW": "60"}
        ):
            reset_rate_limiter()
            client = TestClient(test_app)

            response = client.get("/test")

            assert response.status_code == 200
            assert "X-RateLimit-Limit" in response.headers
            assert "X-RateLimit-Remaining" in response.headers
            assert "X-RateLimit-Reset" in response.headers

            assert response.headers["X-RateLimit-Limit"] == "100"
            assert int(response.headers["X-RateLimit-Remaining"]) == 99

    def test_returns_429_when_limit_exceeded(self, test_app):
        """Returns 429 Too Many Requests when limit exceeded"""
        with patch.dict(
            os.environ,
            {
                "FELIX_SYNC_RATE_LIMIT": "3",  # Very low limit for testing
                "FELIX_SYNC_RATE_WINDOW": "60",
            },
        ):
            reset_rate_limiter()
            client = TestClient(test_app)

            # Use up the limit
            for i in range(3):
                response = client.get("/test")
                assert response.status_code == 200

            # Next request should be rate limited
            response = client.get("/test")

            assert response.status_code == 429
            assert "Rate limit exceeded" in response.json()["detail"]
            assert response.headers["X-RateLimit-Remaining"] == "0"
            assert "Retry-After" in response.headers

    def test_different_ips_have_separate_limits(self, test_app):
        """Different client IPs have separate rate limits"""
        with patch.dict(
            os.environ, {"FELIX_SYNC_RATE_LIMIT": "2", "FELIX_SYNC_RATE_WINDOW": "60"}
        ):
            reset_rate_limiter()
            client = TestClient(test_app)

            # Client A uses up limit
            for _ in range(2):
                response = client.get("/test", headers={"X-Forwarded-For": "1.1.1.1"})
                assert response.status_code == 200

            # Client A is blocked
            response = client.get("/test", headers={"X-Forwarded-For": "1.1.1.1"})
            assert response.status_code == 429

            # Client B is not blocked
            response = client.get("/test", headers={"X-Forwarded-For": "2.2.2.2"})
            assert response.status_code == 200

    def test_bearer_token_used_as_key(self, test_app):
        """Bearer token is used as rate limit key when present"""
        with patch.dict(
            os.environ, {"FELIX_SYNC_RATE_LIMIT": "2", "FELIX_SYNC_RATE_WINDOW": "60"}
        ):
            reset_rate_limiter()
            client = TestClient(test_app)

            # Use token A's limit
            for _ in range(2):
                response = client.get(
                    "/test", headers={"Authorization": "Bearer token_a"}
                )
                assert response.status_code == 200

            # Token A blocked
            response = client.get("/test", headers={"Authorization": "Bearer token_a"})
            assert response.status_code == 429

            # Token B not blocked
            response = client.get("/test", headers={"Authorization": "Bearer token_b"})
            assert response.status_code == 200


# ============================================================================
# Sync Endpoints Rate Limiting Integration Tests
# ============================================================================


class TestSyncEndpointsRateLimiting:
    """Tests for rate limiting on actual sync endpoints"""

    @pytest.fixture(autouse=True)
    def reset_limiter(self):
        """Reset global rate limiter before each test"""
        reset_rate_limiter()
        yield
        reset_rate_limiter()

    def test_sync_endpoints_have_rate_limit_headers(self):
        """Sync endpoints include rate limit headers"""
        from main import app
        from database.db import get_db
        from routers.sync import verify_api_key, ApiKeyInfo

        class FakeDB:
            async def fetch_one(self, *args, **kwargs):
                # Return agent exists, project exists
                return {"id": "test-agent", "project_id": "test-project"}

            async def execute(self, *args, **kwargs):
                return None

        # Mock API key to match project
        mock_api_key = ApiKeyInfo(
            key_id="test-key", project_id="test-project", name="Test Key"
        )

        # Override BEFORE creating the client
        app.dependency_overrides[get_db] = lambda: FakeDB()
        app.dependency_overrides[verify_api_key] = lambda: mock_api_key

        with patch.dict(
            os.environ, {"FELIX_SYNC_RATE_LIMIT": "100", "FELIX_SYNC_RATE_WINDOW": "60"}
        ):
            reset_rate_limiter()

            client = TestClient(app)

            response = client.post(
                "/api/runs",
                json={"agent_id": "test-agent", "project_id": "test-project"},
            )

            # Should have rate limit headers regardless of outcome
            assert "X-RateLimit-Limit" in response.headers
            assert "X-RateLimit-Remaining" in response.headers
            assert "X-RateLimit-Reset" in response.headers

            # Verify the values
            assert response.headers["X-RateLimit-Limit"] == "100"

        app.dependency_overrides.clear()
