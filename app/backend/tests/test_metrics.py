"""
Tests for the Metrics Router (S-0064: Prometheus Metrics Endpoint)

Tests for:
- GET /metrics - Prometheus-format metrics endpoint
- MetricsRegistry class - counter and histogram functionality
- Convenience functions for recording metrics
"""
import pytest
import re
from pathlib import Path

from fastapi.testclient import TestClient

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from main import app
from routers.metrics import (
    MetricsRegistry,
    get_registry,
    record_sync_request,
    record_run_created,
    record_events_inserted,
    record_sync_failure,
    record_artifact_upload,
)


# ============================================================================
# Test Fixtures
# ============================================================================

@pytest.fixture
def client():
    """Create test client."""
    return TestClient(app)


@pytest.fixture
def fresh_registry():
    """Create a fresh metrics registry for testing."""
    registry = MetricsRegistry()
    return registry


@pytest.fixture(autouse=True)
def reset_global_registry():
    """Reset the global registry before each test."""
    get_registry().reset()
    yield
    get_registry().reset()


# ============================================================================
# MetricsRegistry Unit Tests
# ============================================================================

class TestMetricsRegistry:
    """Tests for the MetricsRegistry class."""
    
    def test_inc_counter_default_value(self, fresh_registry):
        """Test counter increment with default value of 1."""
        fresh_registry.inc_counter("test_counter")
        assert fresh_registry.get_counter("test_counter") == 1.0
    
    def test_inc_counter_custom_value(self, fresh_registry):
        """Test counter increment with custom value."""
        fresh_registry.inc_counter("test_counter", value=5.0)
        assert fresh_registry.get_counter("test_counter") == 5.0
    
    def test_inc_counter_multiple_increments(self, fresh_registry):
        """Test multiple counter increments."""
        fresh_registry.inc_counter("test_counter")
        fresh_registry.inc_counter("test_counter")
        fresh_registry.inc_counter("test_counter", value=3.0)
        assert fresh_registry.get_counter("test_counter") == 5.0
    
    def test_inc_counter_with_labels(self, fresh_registry):
        """Test counter with labels."""
        fresh_registry.inc_counter("requests", {"method": "GET", "status": "200"})
        fresh_registry.inc_counter("requests", {"method": "POST", "status": "200"})
        fresh_registry.inc_counter("requests", {"method": "GET", "status": "200"})
        
        assert fresh_registry.get_counter("requests", {"method": "GET", "status": "200"}) == 2.0
        assert fresh_registry.get_counter("requests", {"method": "POST", "status": "200"}) == 1.0
        assert fresh_registry.get_counter("requests", {"method": "DELETE", "status": "200"}) == 0.0
    
    def test_get_counter_nonexistent(self, fresh_registry):
        """Test getting a counter that doesn't exist returns 0."""
        assert fresh_registry.get_counter("nonexistent") == 0.0
    
    def test_observe_histogram(self, fresh_registry):
        """Test histogram observation."""
        fresh_registry.observe_histogram("latency", 0.1)
        fresh_registry.observe_histogram("latency", 0.2)
        fresh_registry.observe_histogram("latency", 0.5)
        
        # Check that values are recorded (via format output)
        output = fresh_registry.format_prometheus()
        assert "latency_count" in output
        assert "latency_sum" in output
    
    def test_observe_histogram_with_labels(self, fresh_registry):
        """Test histogram with labels."""
        fresh_registry.observe_histogram("request_size", 1000, {"endpoint": "/api/upload"})
        fresh_registry.observe_histogram("request_size", 2000, {"endpoint": "/api/upload"})
        
        output = fresh_registry.format_prometheus()
        assert 'endpoint="/api/upload"' in output
    
    def test_reset(self, fresh_registry):
        """Test registry reset clears all metrics."""
        fresh_registry.inc_counter("counter1")
        fresh_registry.inc_counter("counter2", {"label": "value"})
        fresh_registry.observe_histogram("hist1", 1.0)
        
        # Get output before reset to verify metrics exist
        output_before = fresh_registry.format_prometheus()
        assert "counter1" in output_before
        assert "hist1" in output_before
        
        fresh_registry.reset()
        
        # After reset, output should not contain the old metrics
        output_after = fresh_registry.format_prometheus()
        assert "counter1" not in output_after
        assert "counter2" not in output_after
        assert "hist1" not in output_after


class TestPrometheusFormat:
    """Tests for Prometheus text exposition format output."""
    
    def test_format_empty_registry(self, fresh_registry):
        """Test formatting an empty registry."""
        output = fresh_registry.format_prometheus()
        
        # Should have header and uptime
        assert "# Felix Backend Metrics" in output
        assert "process_uptime_seconds" in output
    
    def test_format_counter_without_labels(self, fresh_registry):
        """Test formatting a counter without labels."""
        fresh_registry.inc_counter("simple_counter", value=42.0)
        
        output = fresh_registry.format_prometheus()
        
        assert "# HELP simple_counter Counter metric" in output
        assert "# TYPE simple_counter counter" in output
        assert "simple_counter 42.0" in output
    
    def test_format_counter_with_labels(self, fresh_registry):
        """Test formatting a counter with labels."""
        fresh_registry.inc_counter("labeled_counter", {"method": "GET", "status": "200"}, value=10.0)
        
        output = fresh_registry.format_prometheus()
        
        assert "labeled_counter" in output
        assert 'method="GET"' in output
        assert 'status="200"' in output
        assert "10.0" in output
    
    def test_format_histogram_buckets(self, fresh_registry):
        """Test histogram bucket formatting."""
        # Use a histogram with known buckets
        fresh_registry.observe_histogram("sync_artifacts_uploaded_bytes", 500)
        fresh_registry.observe_histogram("sync_artifacts_uploaded_bytes", 5000)
        fresh_registry.observe_histogram("sync_artifacts_uploaded_bytes", 50000)
        
        output = fresh_registry.format_prometheus()
        
        # Check for bucket lines
        assert "sync_artifacts_uploaded_bytes_bucket" in output
        assert 'le="100"' in output  # First bucket
        assert 'le="+Inf"' in output  # +Inf bucket
        assert "sync_artifacts_uploaded_bytes_sum" in output
        assert "sync_artifacts_uploaded_bytes_count" in output
    
    def test_format_histogram_bucket_counts(self, fresh_registry):
        """Test histogram bucket counts are cumulative."""
        fresh_registry.observe_histogram("sync_upload_duration_seconds", 0.001)  # < 0.005
        fresh_registry.observe_histogram("sync_upload_duration_seconds", 0.01)   # < 0.025
        fresh_registry.observe_histogram("sync_upload_duration_seconds", 1.5)    # < 2.5
        
        output = fresh_registry.format_prometheus()
        
        # Check cumulative counts
        # All 3 should be in +Inf bucket
        assert 'sync_upload_duration_seconds_bucket{le="+Inf"} 3' in output
    
    def test_format_labels_order(self, fresh_registry):
        """Test that labels are sorted alphabetically."""
        fresh_registry.inc_counter("test", {"z_label": "z", "a_label": "a"})
        
        output = fresh_registry.format_prometheus()
        
        # Labels should be in alphabetical order
        assert 'a_label="a",z_label="z"' in output


# ============================================================================
# Convenience Function Tests
# ============================================================================

class TestConvenienceFunctions:
    """Tests for metric recording convenience functions."""
    
    def test_record_sync_request(self):
        """Test recording a sync request."""
        record_sync_request("/api/runs", 200)
        record_sync_request("/api/runs", 200)
        record_sync_request("/api/runs", 500)
        
        registry = get_registry()
        assert registry.get_counter("sync_requests_total", {"endpoint": "/api/runs", "status": "200"}) == 2.0
        assert registry.get_counter("sync_requests_total", {"endpoint": "/api/runs", "status": "500"}) == 1.0
    
    def test_record_run_created(self):
        """Test recording run creation."""
        record_run_created()
        record_run_created()
        
        registry = get_registry()
        assert registry.get_counter("runs_created_total") == 2.0
    
    def test_record_events_inserted(self):
        """Test recording events inserted."""
        record_events_inserted(5)
        record_events_inserted(10)
        
        registry = get_registry()
        assert registry.get_counter("run_events_inserted_total") == 15.0
    
    def test_record_sync_failure(self):
        """Test recording sync failures."""
        record_sync_failure("database_error")
        record_sync_failure("database_error")
        record_sync_failure("storage_error")
        
        registry = get_registry()
        assert registry.get_counter("sync_failures_total", {"error_type": "database_error"}) == 2.0
        assert registry.get_counter("sync_failures_total", {"error_type": "storage_error"}) == 1.0
    
    def test_record_artifact_upload(self):
        """Test recording artifact upload metrics."""
        record_artifact_upload(1024, 0.5)
        record_artifact_upload(2048, 1.0)
        
        output = get_registry().format_prometheus()
        
        # Check histograms are populated
        assert "sync_artifacts_uploaded_bytes" in output
        assert "sync_upload_duration_seconds" in output


# ============================================================================
# API Endpoint Tests
# ============================================================================

class TestMetricsEndpoint:
    """Tests for the /metrics API endpoint."""
    
    def test_metrics_endpoint_returns_200(self, client):
        """Test that /metrics endpoint returns 200."""
        response = client.get("/metrics")
        assert response.status_code == 200
    
    def test_metrics_endpoint_content_type(self, client):
        """Test that /metrics returns plain text."""
        response = client.get("/metrics")
        assert "text/plain" in response.headers["content-type"]
    
    def test_metrics_endpoint_contains_header(self, client):
        """Test that /metrics response contains header."""
        response = client.get("/metrics")
        assert "# Felix Backend Metrics" in response.text
    
    def test_metrics_endpoint_contains_uptime(self, client):
        """Test that /metrics response contains uptime."""
        response = client.get("/metrics")
        assert "process_uptime_seconds" in response.text
    
    def test_metrics_endpoint_includes_recorded_metrics(self, client):
        """Test that recorded metrics appear in endpoint output."""
        # Record some metrics
        record_sync_request("/api/runs", 200)
        record_run_created()
        
        response = client.get("/metrics")
        
        assert "sync_requests_total" in response.text
        assert "runs_created_total" in response.text
    
    def test_metrics_endpoint_prometheus_compatible(self, client):
        """Test that output is Prometheus-compatible format."""
        record_sync_request("/api/test", 200)
        
        response = client.get("/metrics")
        text = response.text
        
        # Check for Prometheus format elements
        # TYPE declaration
        assert re.search(r"# TYPE \w+ (counter|gauge|histogram)", text)
        # HELP declaration
        assert re.search(r"# HELP \w+ .+", text)
        # Metric line with optional labels
        assert re.search(r"\w+(\{[^}]+\})? \d+(\.\d+)?", text)


# ============================================================================
# Thread Safety Tests
# ============================================================================

class TestThreadSafety:
    """Tests for thread safety of metrics operations."""
    
    def test_concurrent_counter_increments(self, fresh_registry):
        """Test that concurrent counter increments are safe."""
        import threading
        
        def increment_counter():
            for _ in range(100):
                fresh_registry.inc_counter("concurrent_test")
        
        threads = [threading.Thread(target=increment_counter) for _ in range(10)]
        
        for t in threads:
            t.start()
        
        for t in threads:
            t.join()
        
        # 10 threads * 100 increments = 1000
        assert fresh_registry.get_counter("concurrent_test") == 1000.0
    
    def test_concurrent_histogram_observations(self, fresh_registry):
        """Test that concurrent histogram observations are safe."""
        import threading
        
        def observe_histogram():
            for i in range(100):
                fresh_registry.observe_histogram("concurrent_hist", float(i))
        
        threads = [threading.Thread(target=observe_histogram) for _ in range(10)]
        
        for t in threads:
            t.start()
        
        for t in threads:
            t.join()
        
        # Should have 1000 observations total
        output = fresh_registry.format_prometheus()
        # Histogram without labels has no braces in the count line
        assert "concurrent_hist_count 1000" in output
