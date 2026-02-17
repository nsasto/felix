"""
Tests for Enhanced Health Check Endpoint (S-0064: Run Artifact Sync - Production Readiness)

Tests for:
- Database connectivity check
- Storage availability check
- Response status codes (200 healthy, 503 unhealthy)
- Response structure with database and storage status
"""
import pytest
import uuid
from unittest.mock import patch, AsyncMock, MagicMock
from pathlib import Path

from fastapi.testclient import TestClient

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

# Import app and dependencies
import main
from main import app
from database.db import database
from artifact_storage import get_artifact_storage as original_get_artifact_storage


# ============================================================================
# Fake/Mock Implementations
# ============================================================================

class FakeHealthyDatabase:
    """Fake database that returns healthy responses."""
    
    async def fetch_one(self, query, values=None):
        return {"result": 1}


class FakeUnhealthyDatabase:
    """Fake database that simulates connection errors."""
    
    async def fetch_one(self, query, values=None):
        raise ConnectionError("Database connection refused")


class FakeHealthyStorage:
    """Fake storage that returns healthy responses."""
    
    def __init__(self):
        self._stored = {}
    
    async def put(self, key: str, content: bytes, content_type: str, metadata=None):
        self._stored[key] = content
    
    async def get(self, key: str) -> bytes:
        return self._stored.get(key, b"")
    
    async def delete(self, key: str):
        if key in self._stored:
            del self._stored[key]
    
    async def exists(self, key: str) -> bool:
        return key in self._stored


class FakeUnhealthyStorage:
    """Fake storage that simulates storage errors."""
    
    async def put(self, key: str, content: bytes, content_type: str, metadata=None):
        raise IOError("Storage unavailable")
    
    async def get(self, key: str) -> bytes:
        raise IOError("Storage unavailable")
    
    async def delete(self, key: str):
        raise IOError("Storage unavailable")
    
    async def exists(self, key: str) -> bool:
        raise IOError("Storage unavailable")


class FakeStorageReadWriteMismatch:
    """Fake storage that returns mismatched content on read."""
    
    async def put(self, key: str, content: bytes, content_type: str, metadata=None):
        pass
    
    async def get(self, key: str) -> bytes:
        return b"wrong_content_that_does_not_match"
    
    async def delete(self, key: str):
        pass


# ============================================================================
# Test Fixtures
# ============================================================================

@pytest.fixture
def client():
    """Create a test client with clean dependency overrides."""
    app.dependency_overrides.clear()
    yield TestClient(app)
    app.dependency_overrides.clear()


def mock_storage_factory(storage_instance):
    """Create a factory function that returns the given storage instance."""
    def factory():
        return storage_instance
    return factory


# ============================================================================
# Health Check Response Structure Tests
# ============================================================================

class TestHealthCheckResponseStructure:
    """Tests for health check response structure."""

    def test_healthy_response_includes_all_fields(self, client):
        """Health check returns all expected fields when healthy."""
        fake_storage = FakeHealthyStorage()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.return_value = {"result": 1}
            
            response = client.get("/health")
            
            assert response.status_code == 200
            data = response.json()
            
            # Verify all fields present
            assert "status" in data
            assert "service" in data
            assert "version" in data
            assert "database" in data
            assert "storage" in data
            
            # Verify field values
            assert data["status"] == "healthy"
            assert data["service"] == "felix-backend"
            assert data["version"] == "0.1.0"
            assert data["database"] is True
            assert data["storage"] is True

    def test_unhealthy_response_includes_all_fields(self, client):
        """Health check returns all expected fields when unhealthy."""
        fake_storage = FakeHealthyStorage()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.side_effect = ConnectionError("Database down")
            
            response = client.get("/health")
            
            assert response.status_code == 503
            data = response.json()
            
            # Verify all fields present
            assert "status" in data
            assert "service" in data
            assert "version" in data
            assert "database" in data
            assert "storage" in data
            
            # Verify status indicates unhealthy
            assert data["status"] == "unhealthy"


# ============================================================================
# Database Connectivity Tests
# ============================================================================

class TestHealthCheckDatabaseConnectivity:
    """Tests for database connectivity check in health endpoint."""

    def test_database_healthy_when_query_succeeds(self, client):
        """Database shows healthy when SELECT 1 succeeds."""
        fake_storage = FakeHealthyStorage()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.return_value = {"result": 1}
            
            response = client.get("/health")
            
            assert response.status_code == 200
            data = response.json()
            assert data["database"] is True

    def test_database_unhealthy_when_query_fails(self, client):
        """Database shows unhealthy when SELECT 1 fails."""
        fake_storage = FakeHealthyStorage()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.side_effect = ConnectionError("Connection refused")
            
            response = client.get("/health")
            
            assert response.status_code == 503
            data = response.json()
            assert data["database"] is False
            assert data["status"] == "unhealthy"

    def test_database_unhealthy_on_timeout(self, client):
        """Database shows unhealthy on query timeout."""
        fake_storage = FakeHealthyStorage()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.side_effect = TimeoutError("Query timed out")
            
            response = client.get("/health")
            
            assert response.status_code == 503
            data = response.json()
            assert data["database"] is False

    def test_database_unhealthy_on_generic_exception(self, client):
        """Database shows unhealthy on any exception."""
        fake_storage = FakeHealthyStorage()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.side_effect = Exception("Unknown database error")
            
            response = client.get("/health")
            
            assert response.status_code == 503
            data = response.json()
            assert data["database"] is False


# ============================================================================
# Storage Availability Tests
# ============================================================================

class TestHealthCheckStorageAvailability:
    """Tests for storage availability check in health endpoint."""

    def test_storage_healthy_when_write_read_delete_succeeds(self, client):
        """Storage shows healthy when write/read/delete cycle succeeds."""
        fake_storage = FakeHealthyStorage()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.return_value = {"result": 1}
            
            response = client.get("/health")
            
            assert response.status_code == 200
            data = response.json()
            assert data["storage"] is True

    def test_storage_unhealthy_when_put_fails(self, client):
        """Storage shows unhealthy when put operation fails."""
        fake_storage = FakeUnhealthyStorage()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.return_value = {"result": 1}
            
            response = client.get("/health")
            
            assert response.status_code == 503
            data = response.json()
            assert data["storage"] is False
            assert data["status"] == "unhealthy"

    def test_storage_unhealthy_on_read_write_mismatch(self, client):
        """Storage shows unhealthy when read content doesn't match write."""
        fake_storage = FakeStorageReadWriteMismatch()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.return_value = {"result": 1}
            
            response = client.get("/health")
            
            assert response.status_code == 503
            data = response.json()
            assert data["storage"] is False

    def test_storage_uses_health_check_prefix(self, client):
        """Storage health check uses _health_check/ prefix for test key."""
        storage_calls = []
        
        class FakeStorageWithTracking:
            async def put(self, key: str, content: bytes, content_type: str, metadata=None):
                storage_calls.append(("put", key))
                
            async def get(self, key: str) -> bytes:
                storage_calls.append(("get", key))
                return b"health_check_test"
                
            async def delete(self, key: str):
                storage_calls.append(("delete", key))
        
        fake_storage = FakeStorageWithTracking()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.return_value = {"result": 1}
            
            response = client.get("/health")
            
            # Verify storage operations were called
            assert len(storage_calls) >= 3
            
            # Verify _health_check/ prefix is used
            for operation, key in storage_calls:
                assert key.startswith("_health_check/")


# ============================================================================
# Combined Status Tests
# ============================================================================

class TestHealthCheckCombinedStatus:
    """Tests for combined status logic."""

    def test_healthy_only_when_both_database_and_storage_healthy(self, client):
        """Returns healthy only when both database and storage are healthy."""
        fake_storage = FakeHealthyStorage()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.return_value = {"result": 1}
            
            response = client.get("/health")
            
            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "healthy"
            assert data["database"] is True
            assert data["storage"] is True

    def test_unhealthy_when_only_database_fails(self, client):
        """Returns unhealthy when only database fails."""
        fake_storage = FakeHealthyStorage()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.side_effect = ConnectionError("Database down")
            
            response = client.get("/health")
            
            assert response.status_code == 503
            data = response.json()
            assert data["status"] == "unhealthy"
            assert data["database"] is False
            assert data["storage"] is True  # Storage still checked

    def test_unhealthy_when_only_storage_fails(self, client):
        """Returns unhealthy when only storage fails."""
        fake_storage = FakeUnhealthyStorage()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.return_value = {"result": 1}
            
            response = client.get("/health")
            
            assert response.status_code == 503
            data = response.json()
            assert data["status"] == "unhealthy"
            assert data["database"] is True  # Database still checked
            assert data["storage"] is False

    def test_unhealthy_when_both_fail(self, client):
        """Returns unhealthy when both database and storage fail."""
        fake_storage = FakeUnhealthyStorage()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.side_effect = ConnectionError("Database down")
            
            response = client.get("/health")
            
            assert response.status_code == 503
            data = response.json()
            assert data["status"] == "unhealthy"
            assert data["database"] is False
            assert data["storage"] is False


# ============================================================================
# HTTP Status Code Tests
# ============================================================================

class TestHealthCheckStatusCodes:
    """Tests for HTTP status code responses."""

    def test_returns_200_when_healthy(self, client):
        """Returns 200 OK when all systems healthy."""
        fake_storage = FakeHealthyStorage()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.return_value = {"result": 1}
            
            response = client.get("/health")
            
            assert response.status_code == 200

    def test_returns_503_when_database_unhealthy(self, client):
        """Returns 503 Service Unavailable when database unhealthy."""
        fake_storage = FakeHealthyStorage()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.side_effect = Exception("Database error")
            
            response = client.get("/health")
            
            assert response.status_code == 503

    def test_returns_503_when_storage_unhealthy(self, client):
        """Returns 503 Service Unavailable when storage unhealthy."""
        fake_storage = FakeUnhealthyStorage()
        
        with patch.object(database, "fetch_one", new_callable=AsyncMock) as mock_db, \
             patch("main.get_artifact_storage", return_value=fake_storage):
            mock_db.return_value = {"result": 1}
            
            response = client.get("/health")
            
            assert response.status_code == 503
