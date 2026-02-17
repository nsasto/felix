"""
Tests for Request Size Limit Middleware

Tests the RequestSizeLimitMiddleware that limits incoming request body sizes.
"""

import pytest
from unittest.mock import patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from starlette.requests import Request
from starlette.responses import JSONResponse

from middleware.request_size import (
    RequestSizeLimitMiddleware,
    get_max_request_size_bytes,
    add_request_size_limit,
    DEFAULT_MAX_REQUEST_SIZE_MB,
)


# ============================================================================
# TEST FIXTURES
# ============================================================================

@pytest.fixture
def app_with_middleware():
    """Create a test app with the request size middleware."""
    app = FastAPI()
    
    # Add middleware with a small limit for testing (1 MB)
    app.add_middleware(RequestSizeLimitMiddleware, max_size_bytes=1 * 1024 * 1024)
    
    @app.post("/upload")
    async def upload_endpoint(request: Request):
        body = await request.body()
        return {"size": len(body)}
    
    @app.get("/health")
    async def health():
        return {"status": "ok"}
    
    return app


@pytest.fixture
def client(app_with_middleware):
    """Create test client for the app."""
    return TestClient(app_with_middleware)


# ============================================================================
# CONFIGURATION TESTS
# ============================================================================

class TestConfiguration:
    """Tests for configuration functions."""
    
    def test_default_max_request_size(self):
        """Test that default max request size is correctly calculated."""
        # Clear any environment variable
        with patch.dict("os.environ", {}, clear=True):
            size_bytes = get_max_request_size_bytes()
            expected = DEFAULT_MAX_REQUEST_SIZE_MB * 1024 * 1024
            assert size_bytes == expected
    
    def test_max_request_size_from_env(self):
        """Test that max request size can be set via environment variable."""
        with patch.dict("os.environ", {"FELIX_MAX_REQUEST_SIZE_MB": "100"}):
            size_bytes = get_max_request_size_bytes()
            expected = 100 * 1024 * 1024  # 100 MB
            assert size_bytes == expected
    
    def test_max_request_size_custom_value(self):
        """Test various custom values for max request size."""
        test_cases = [
            ("1", 1 * 1024 * 1024),
            ("10", 10 * 1024 * 1024),
            ("256", 256 * 1024 * 1024),
            ("1024", 1024 * 1024 * 1024),  # 1 GB
        ]
        
        for env_value, expected_bytes in test_cases:
            with patch.dict("os.environ", {"FELIX_MAX_REQUEST_SIZE_MB": env_value}):
                size_bytes = get_max_request_size_bytes()
                assert size_bytes == expected_bytes, f"Failed for env value {env_value}"


# ============================================================================
# MIDDLEWARE BEHAVIOR TESTS
# ============================================================================

class TestMiddlewareBehavior:
    """Tests for the middleware behavior."""
    
    def test_request_under_limit_allowed(self, client):
        """Test that requests under the size limit are allowed."""
        # Send a small request (less than 1 MB limit)
        small_data = b"x" * 1000  # 1 KB
        
        response = client.post(
            "/upload",
            content=small_data,
            headers={"Content-Length": str(len(small_data))}
        )
        
        assert response.status_code == 200
        assert response.json()["size"] == 1000
    
    def test_request_at_limit_allowed(self, client):
        """Test that requests exactly at the size limit are allowed."""
        # Send a request exactly at 1 MB limit
        exact_data = b"x" * (1024 * 1024)  # 1 MB
        
        response = client.post(
            "/upload",
            content=exact_data,
            headers={"Content-Length": str(len(exact_data))}
        )
        
        assert response.status_code == 200
        assert response.json()["size"] == 1024 * 1024
    
    def test_request_over_limit_rejected(self, client):
        """Test that requests over the size limit are rejected with 413."""
        # The middleware checks Content-Length header, not actual body size
        # So we can fake a large Content-Length for testing
        response = client.post(
            "/upload",
            content=b"small",
            headers={"Content-Length": str(2 * 1024 * 1024)}  # Claim 2 MB
        )
        
        assert response.status_code == 413
        assert "Request body too large" in response.json()["detail"]
        assert response.json()["max_size_bytes"] == 1024 * 1024
        assert response.json()["actual_size_bytes"] == 2 * 1024 * 1024
    
    def test_request_without_content_length_allowed(self, client):
        """Test that requests without Content-Length header are allowed through."""
        # GET requests don't have Content-Length
        response = client.get("/health")
        
        assert response.status_code == 200
        assert response.json()["status"] == "ok"
    
    def test_large_content_length_header(self, client):
        """Test rejection of very large Content-Length values."""
        # Claim a 10 GB request
        huge_size = 10 * 1024 * 1024 * 1024  # 10 GB
        
        response = client.post(
            "/upload",
            content=b"x",
            headers={"Content-Length": str(huge_size)}
        )
        
        assert response.status_code == 413
        assert response.json()["actual_size_bytes"] == huge_size
    
    def test_response_includes_max_size_header(self, client):
        """Test that 413 response includes X-Max-Request-Size header."""
        response = client.post(
            "/upload",
            content=b"x",
            headers={"Content-Length": str(5 * 1024 * 1024)}  # 5 MB
        )
        
        assert response.status_code == 413
        assert "X-Max-Request-Size" in response.headers
        assert response.headers["X-Max-Request-Size"] == str(1024 * 1024)


# ============================================================================
# EDGE CASES
# ============================================================================

class TestEdgeCases:
    """Tests for edge cases and error handling."""
    
    def test_invalid_content_length_header(self, client):
        """Test handling of invalid (non-numeric) Content-Length header."""
        # Invalid Content-Length should be ignored (let request through)
        response = client.post(
            "/upload",
            content=b"test data",
            headers={"Content-Length": "invalid"}
        )
        
        # The middleware should let it through; the server may still reject it
        # depending on how the server handles malformed headers
        # In TestClient, we just verify no 413 error from our middleware
        assert response.status_code != 413 or "Request body too large" not in response.text
    
    def test_zero_content_length(self, client):
        """Test handling of zero Content-Length header."""
        response = client.post(
            "/upload",
            content=b"",
            headers={"Content-Length": "0"}
        )
        
        assert response.status_code == 200
        assert response.json()["size"] == 0
    
    def test_negative_content_length(self, client):
        """Test handling of negative Content-Length header."""
        # Negative values should be rejected or ignored
        response = client.post(
            "/upload",
            content=b"test",
            headers={"Content-Length": "-1"}
        )
        
        # Should not cause a 413 (negative is less than max)
        # or should be handled gracefully
        assert response.status_code != 500  # No server error


# ============================================================================
# ADD MIDDLEWARE HELPER TESTS
# ============================================================================

class TestAddMiddlewareHelper:
    """Tests for the add_request_size_limit helper function."""
    
    def test_add_middleware_with_custom_size(self):
        """Test adding middleware with custom size."""
        app = FastAPI()
        
        add_request_size_limit(app, max_size_mb=50)
        
        @app.post("/test")
        async def test_endpoint():
            return {"ok": True}
        
        client = TestClient(app)
        
        # Request claiming 51 MB should be rejected
        response = client.post(
            "/test",
            content=b"x",
            headers={"Content-Length": str(51 * 1024 * 1024)}
        )
        
        assert response.status_code == 413
    
    def test_add_middleware_with_default_size(self):
        """Test adding middleware with default size."""
        app = FastAPI()
        
        with patch.dict("os.environ", {"FELIX_MAX_REQUEST_SIZE_MB": "10"}):
            add_request_size_limit(app)
        
        @app.post("/test")
        async def test_endpoint():
            return {"ok": True}
        
        client = TestClient(app)
        
        # Request claiming 11 MB should be rejected (10 MB limit from env)
        response = client.post(
            "/test",
            content=b"x",
            headers={"Content-Length": str(11 * 1024 * 1024)}
        )
        
        assert response.status_code == 413


# ============================================================================
# INTEGRATION WITH MAIN APP
# ============================================================================

class TestIntegrationWithMainApp:
    """Tests verifying middleware integrates correctly with the main app."""
    
    def test_health_endpoint_not_affected(self):
        """Test that the health endpoint works normally with the middleware."""
        from main import app
        
        client = TestClient(app)
        response = client.get("/health")
        
        # Should work (may return 200 or 503 depending on DB/storage state)
        # The point is it's not blocked by request size middleware
        assert response.status_code in [200, 503]
    
    def test_root_endpoint_not_affected(self):
        """Test that the root endpoint works normally with the middleware."""
        from main import app
        
        client = TestClient(app)
        response = client.get("/")
        
        assert response.status_code == 200
        assert "Felix Backend" in response.json()["name"]


# ============================================================================
# PERFORMANCE CHARACTERISTICS
# ============================================================================

class TestPerformanceCharacteristics:
    """Tests verifying performance-related behavior."""
    
    def test_rejection_happens_before_body_read(self, client):
        """Test that large requests are rejected before reading the body."""
        # This is important for DoS protection - we shouldn't try to read
        # a 10GB request body before rejecting it
        
        # Claim 10 GB request
        huge_size = 10 * 1024 * 1024 * 1024
        
        # Only send 1 byte of actual data
        response = client.post(
            "/upload",
            content=b"x",
            headers={"Content-Length": str(huge_size)}
        )
        
        # Should be rejected immediately based on header
        assert response.status_code == 413
    
    def test_middleware_allows_get_requests_through_quickly(self, client):
        """Test that GET requests aren't delayed by size checking."""
        import time
        
        start = time.time()
        response = client.get("/health")
        elapsed = time.time() - start
        
        assert response.status_code == 200
        assert elapsed < 1.0  # Should be very fast
