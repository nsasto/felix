"""
Felix Backend - Prometheus-Style Metrics Endpoint
Provides /metrics endpoint with sync operation metrics in Prometheus text format.

Metrics exposed:
- Counters:
  - sync_requests_total{endpoint, status}: Total sync requests by endpoint and HTTP status
  - runs_created_total: Total runs created via sync API
  - run_events_inserted_total: Total events inserted via sync API
  - sync_failures_total{error_type}: Total sync failures by error type
  
- Histograms:
  - sync_artifacts_uploaded_bytes: Distribution of artifact upload sizes
  - sync_upload_duration_seconds: Distribution of upload operation durations

This uses simple in-memory counters - no external dependencies like prometheus_client.
For production use with Prometheus, this format is compatible with Prometheus scraping.
"""

import threading
import time
from collections import defaultdict
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

from fastapi import APIRouter
from fastapi.responses import PlainTextResponse


router = APIRouter(tags=["metrics"])


# ============================================================================
# METRIC STORAGE
# ============================================================================

class MetricsRegistry:
    """
    Thread-safe metrics registry for storing counters and histograms.
    
    All metric operations are thread-safe and can be called from any context.
    """
    
    def __init__(self):
        self._lock = threading.Lock()
        
        # Counters: name -> labels -> value
        # Labels are stored as tuples of (key, value) pairs for hashability
        self._counters: Dict[str, Dict[Tuple[Tuple[str, str], ...], float]] = defaultdict(
            lambda: defaultdict(float)
        )
        
        # Histograms: name -> labels -> list of observed values
        # We keep raw observations for calculating quantiles
        self._histograms: Dict[str, Dict[Tuple[Tuple[str, str], ...], List[float]]] = defaultdict(
            lambda: defaultdict(list)
        )
        
        # Histogram bucket boundaries (Prometheus-style)
        # Default buckets suitable for bytes (artifacts) and seconds (duration)
        self._histogram_buckets: Dict[str, List[float]] = {
            "sync_artifacts_uploaded_bytes": [
                100, 1000, 10000, 100000, 1000000,  # 100B, 1KB, 10KB, 100KB, 1MB
                10000000, 100000000, 500000000,  # 10MB, 100MB, 500MB
            ],
            "sync_upload_duration_seconds": [
                0.005, 0.01, 0.025, 0.05, 0.075, 0.1,  # Fast operations
                0.25, 0.5, 0.75, 1.0,  # Sub-second
                2.5, 5.0, 7.5, 10.0,  # Seconds
            ],
        }
        
        # Track start time for uptime metric
        self._start_time = time.time()
    
    def _labels_to_tuple(self, labels: Optional[Dict[str, str]]) -> Tuple[Tuple[str, str], ...]:
        """Convert labels dict to hashable tuple."""
        if not labels:
            return ()
        return tuple(sorted(labels.items()))
    
    def inc_counter(self, name: str, labels: Optional[Dict[str, str]] = None, value: float = 1.0):
        """Increment a counter by the given value."""
        with self._lock:
            label_tuple = self._labels_to_tuple(labels)
            self._counters[name][label_tuple] += value
    
    def observe_histogram(self, name: str, value: float, labels: Optional[Dict[str, str]] = None):
        """Record an observation in a histogram."""
        with self._lock:
            label_tuple = self._labels_to_tuple(labels)
            self._histograms[name][label_tuple].append(value)
    
    def get_counter(self, name: str, labels: Optional[Dict[str, str]] = None) -> float:
        """Get current counter value."""
        with self._lock:
            label_tuple = self._labels_to_tuple(labels)
            return self._counters[name][label_tuple]
    
    def format_prometheus(self) -> str:
        """
        Format all metrics in Prometheus text exposition format.
        
        https://prometheus.io/docs/instrumenting/exposition_formats/
        """
        lines = []
        
        # Add header comment
        lines.append("# Felix Backend Metrics")
        lines.append(f"# Generated at: {datetime.now(timezone.utc).isoformat()}")
        lines.append("")
        
        with self._lock:
            # Format counters
            for counter_name, label_values in sorted(self._counters.items()):
                lines.append(f"# HELP {counter_name} Counter metric")
                lines.append(f"# TYPE {counter_name} counter")
                
                for labels, value in sorted(label_values.items()):
                    label_str = self._format_labels(labels)
                    lines.append(f"{counter_name}{label_str} {value}")
                lines.append("")
            
            # Format histograms
            for hist_name, label_values in sorted(self._histograms.items()):
                lines.append(f"# HELP {hist_name} Histogram metric")
                lines.append(f"# TYPE {hist_name} histogram")
                
                buckets = self._histogram_buckets.get(hist_name, [1, 5, 10, 50, 100])
                
                for labels, observations in sorted(label_values.items()):
                    label_str = self._format_labels(labels)
                    
                    if not observations:
                        continue
                    
                    # Calculate bucket counts
                    sorted_obs = sorted(observations)
                    obs_sum = sum(observations)
                    obs_count = len(observations)
                    
                    # Output bucket values
                    cumulative = 0
                    for bucket in buckets:
                        # Count observations <= bucket
                        while cumulative < obs_count and sorted_obs[cumulative] <= bucket:
                            cumulative += 1
                        
                        bucket_labels = self._format_labels(labels, {"le": str(bucket)})
                        lines.append(f"{hist_name}_bucket{bucket_labels} {cumulative}")
                    
                    # +Inf bucket (all observations)
                    inf_labels = self._format_labels(labels, {"le": "+Inf"})
                    lines.append(f"{hist_name}_bucket{inf_labels} {obs_count}")
                    
                    # Sum and count
                    lines.append(f"{hist_name}_sum{label_str} {obs_sum}")
                    lines.append(f"{hist_name}_count{label_str} {obs_count}")
                
                lines.append("")
        
        # Add process uptime
        uptime = time.time() - self._start_time
        lines.append("# HELP process_uptime_seconds Time since process started")
        lines.append("# TYPE process_uptime_seconds gauge")
        lines.append(f"process_uptime_seconds {uptime:.2f}")
        
        return "\n".join(lines)
    
    def _format_labels(
        self,
        labels: Tuple[Tuple[str, str], ...],
        extra_labels: Optional[Dict[str, str]] = None
    ) -> str:
        """Format labels as Prometheus label string."""
        all_labels = dict(labels)
        if extra_labels:
            all_labels.update(extra_labels)
        
        if not all_labels:
            return ""
        
        label_parts = [f'{k}="{v}"' for k, v in sorted(all_labels.items())]
        return "{" + ",".join(label_parts) + "}"
    
    def reset(self):
        """Reset all metrics (useful for testing)."""
        with self._lock:
            self._counters.clear()
            self._histograms.clear()
            self._start_time = time.time()


# Global metrics registry
_registry = MetricsRegistry()


def get_registry() -> MetricsRegistry:
    """Get the global metrics registry."""
    return _registry


# ============================================================================
# CONVENIENCE FUNCTIONS
# ============================================================================

def record_sync_request(endpoint: str, status: int):
    """Record a sync API request."""
    _registry.inc_counter(
        "sync_requests_total",
        {"endpoint": endpoint, "status": str(status)}
    )


def record_run_created():
    """Record a run creation."""
    _registry.inc_counter("runs_created_total")


def record_events_inserted(count: int):
    """Record events inserted."""
    _registry.inc_counter("run_events_inserted_total", value=float(count))


def record_sync_failure(error_type: str):
    """Record a sync failure."""
    _registry.inc_counter("sync_failures_total", {"error_type": error_type})


def record_artifact_upload(size_bytes: int, duration_seconds: float):
    """Record an artifact upload with size and duration."""
    _registry.observe_histogram("sync_artifacts_uploaded_bytes", float(size_bytes))
    _registry.observe_histogram("sync_upload_duration_seconds", duration_seconds)


# ============================================================================
# API ENDPOINT
# ============================================================================

@router.get("/metrics", response_class=PlainTextResponse)
async def get_metrics():
    """
    Prometheus-compatible metrics endpoint.
    
    Returns metrics in Prometheus text exposition format for scraping.
    
    Metrics include:
    - sync_requests_total: Counter of sync API requests
    - runs_created_total: Counter of runs created
    - run_events_inserted_total: Counter of events inserted
    - sync_failures_total: Counter of sync failures by error type
    - sync_artifacts_uploaded_bytes: Histogram of artifact sizes
    - sync_upload_duration_seconds: Histogram of upload durations
    - process_uptime_seconds: Gauge of process uptime
    
    Returns:
        Plain text response in Prometheus exposition format
    """
    return _registry.format_prometheus()
