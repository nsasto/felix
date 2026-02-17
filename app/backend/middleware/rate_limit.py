"""
Felix Backend - Rate Limiting Middleware

Provides rate limiting for sync endpoints using a sliding window algorithm.
Rate limit state is stored in memory (no external dependencies).

Configuration:
- Default: 100 requests per minute per agent
- Can be customized via FELIX_SYNC_RATE_LIMIT environment variable

Usage:
    from middleware.rate_limit import rate_limit_dependency, RateLimitExceeded

    @router.post("/api/sync/endpoint")
    async def my_endpoint(
        rate_limit: None = Depends(rate_limit_dependency),
    ):
        ...

The dependency adds rate limit headers to responses:
- X-RateLimit-Limit: Maximum requests allowed in the window
- X-RateLimit-Remaining: Requests remaining in the current window
- X-RateLimit-Reset: Unix timestamp when the window resets
"""

import os
import time
import logging
from typing import Optional, Dict, List, Tuple
from collections import defaultdict
from dataclasses import dataclass, field
from threading import Lock

from fastapi import Request, Response, HTTPException, Depends
from fastapi.responses import JSONResponse


logger = logging.getLogger(__name__)


# ============================================================================
# CONFIGURATION
# ============================================================================

# Default rate limit: 100 requests per minute
DEFAULT_RATE_LIMIT = 100
DEFAULT_WINDOW_SECONDS = 60

def get_rate_limit_config() -> Tuple[int, int]:
    """
    Get rate limit configuration from environment variables.
    
    Environment variables:
    - FELIX_SYNC_RATE_LIMIT: Max requests per window (default: 100)
    - FELIX_SYNC_RATE_WINDOW: Window size in seconds (default: 60)
    
    Returns:
        Tuple of (max_requests, window_seconds)
    """
    max_requests = int(os.environ.get("FELIX_SYNC_RATE_LIMIT", DEFAULT_RATE_LIMIT))
    window_seconds = int(os.environ.get("FELIX_SYNC_RATE_WINDOW", DEFAULT_WINDOW_SECONDS))
    return max_requests, window_seconds


# ============================================================================
# SLIDING WINDOW RATE LIMITER
# ============================================================================

@dataclass
class RateLimitState:
    """
    State for a single rate limit key (e.g., agent_id or IP address).
    
    Uses sliding window algorithm:
    - Stores timestamps of recent requests
    - Removes timestamps older than the window
    - Counts remaining requests within the window
    """
    timestamps: List[float] = field(default_factory=list)
    lock: Lock = field(default_factory=Lock)
    
    def record_request(self, now: float, window_seconds: int, max_requests: int) -> Tuple[bool, int, float]:
        """
        Record a request and check if rate limit is exceeded.
        
        Args:
            now: Current timestamp
            window_seconds: Size of the sliding window
            max_requests: Maximum requests allowed in the window
            
        Returns:
            Tuple of (allowed, remaining, reset_time):
            - allowed: True if request is within rate limit
            - remaining: Number of requests remaining
            - reset_time: Unix timestamp when oldest request exits the window
        """
        with self.lock:
            # Remove timestamps older than the window
            window_start = now - window_seconds
            self.timestamps = [ts for ts in self.timestamps if ts > window_start]
            
            # Check if we've exceeded the limit
            current_count = len(self.timestamps)
            
            if current_count >= max_requests:
                # Rate limit exceeded
                # Calculate when the oldest request will exit the window
                oldest_ts = self.timestamps[0] if self.timestamps else now
                reset_time = oldest_ts + window_seconds
                return False, 0, reset_time
            
            # Record this request
            self.timestamps.append(now)
            remaining = max_requests - len(self.timestamps)
            
            # Reset time is when the oldest request in the window will expire
            oldest_ts = self.timestamps[0] if self.timestamps else now
            reset_time = oldest_ts + window_seconds
            
            return True, remaining, reset_time


class RateLimiter:
    """
    In-memory rate limiter using sliding window algorithm.
    
    Thread-safe and suitable for single-process deployments.
    For multi-process deployments, consider using Redis or similar.
    """
    
    def __init__(self, max_requests: int = DEFAULT_RATE_LIMIT, window_seconds: int = DEFAULT_WINDOW_SECONDS):
        """
        Initialize rate limiter.
        
        Args:
            max_requests: Maximum requests allowed per window
            window_seconds: Window size in seconds
        """
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._states: Dict[str, RateLimitState] = defaultdict(RateLimitState)
        self._global_lock = Lock()
    
    def check_rate_limit(self, key: str) -> Tuple[bool, int, float]:
        """
        Check if a request is allowed under the rate limit.
        
        Args:
            key: Rate limit key (e.g., agent_id, IP address)
            
        Returns:
            Tuple of (allowed, remaining, reset_time):
            - allowed: True if request is within rate limit
            - remaining: Number of requests remaining
            - reset_time: Unix timestamp when the window resets
        """
        now = time.time()
        
        # Get or create state for this key
        with self._global_lock:
            state = self._states[key]
        
        return state.record_request(now, self.window_seconds, self.max_requests)
    
    def cleanup_old_entries(self, max_age_seconds: int = 300):
        """
        Remove entries that haven't been used recently.
        
        Call this periodically to prevent memory growth.
        
        Args:
            max_age_seconds: Remove entries with no requests in this time
        """
        now = time.time()
        cutoff = now - max_age_seconds
        
        with self._global_lock:
            keys_to_remove = []
            for key, state in self._states.items():
                with state.lock:
                    if not state.timestamps or max(state.timestamps) < cutoff:
                        keys_to_remove.append(key)
            
            for key in keys_to_remove:
                del self._states[key]
            
            if keys_to_remove:
                logger.debug(f"Rate limiter cleanup: removed {len(keys_to_remove)} stale entries")


# Global rate limiter instance
_rate_limiter: Optional[RateLimiter] = None


def get_rate_limiter() -> RateLimiter:
    """Get or create the global rate limiter instance."""
    global _rate_limiter
    if _rate_limiter is None:
        max_requests, window_seconds = get_rate_limit_config()
        _rate_limiter = RateLimiter(max_requests, window_seconds)
        logger.info(f"Rate limiter initialized: {max_requests} requests per {window_seconds} seconds")
    return _rate_limiter


# ============================================================================
# RATE LIMIT KEY EXTRACTION
# ============================================================================

def extract_rate_limit_key(request: Request) -> str:
    """
    Extract the rate limit key from a request.
    
    Priority:
    1. agent_id from request body (for sync endpoints)
    2. Authorization header (API key)
    3. Client IP address
    
    Args:
        request: FastAPI request object
        
    Returns:
        Rate limit key string
    """
    # Try to get agent_id from Authorization header
    auth_header = request.headers.get("authorization", "")
    if auth_header.startswith("Bearer "):
        # Use the API key as the rate limit key
        return f"api_key:{auth_header[7:][:16]}"  # First 16 chars for privacy
    
    # Fall back to client IP
    client_ip = request.client.host if request.client else "unknown"
    
    # Check for proxy headers
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        # Get the first IP in the chain (original client)
        client_ip = forwarded_for.split(",")[0].strip()
    
    return f"ip:{client_ip}"


# ============================================================================
# FASTAPI DEPENDENCY
# ============================================================================

async def rate_limit_dependency(request: Request, response: Response) -> None:
    """
    FastAPI dependency for rate limiting sync endpoints.
    
    Checks the rate limit and:
    - Adds X-RateLimit-* headers to the response
    - Raises HTTPException(429) if rate limit exceeded
    
    Usage:
        @router.post("/api/sync/endpoint")
        async def my_endpoint(
            rate_limit: None = Depends(rate_limit_dependency),
        ):
            ...
    
    Args:
        request: FastAPI request object
        response: FastAPI response object
        
    Raises:
        HTTPException: 429 Too Many Requests if rate limit exceeded
    """
    limiter = get_rate_limiter()
    key = extract_rate_limit_key(request)
    
    allowed, remaining, reset_time = limiter.check_rate_limit(key)
    
    # Add rate limit headers to response
    response.headers["X-RateLimit-Limit"] = str(limiter.max_requests)
    response.headers["X-RateLimit-Remaining"] = str(max(0, remaining))
    response.headers["X-RateLimit-Reset"] = str(int(reset_time))
    
    if not allowed:
        logger.warning(f"Rate limit exceeded for {key}")
        raise HTTPException(
            status_code=429,
            detail="Rate limit exceeded. Please retry after the reset time.",
            headers={
                "X-RateLimit-Limit": str(limiter.max_requests),
                "X-RateLimit-Remaining": "0",
                "X-RateLimit-Reset": str(int(reset_time)),
                "Retry-After": str(int(reset_time - time.time())),
            }
        )


# ============================================================================
# HELPER FOR TESTING
# ============================================================================

def reset_rate_limiter():
    """Reset the global rate limiter (for testing only)."""
    global _rate_limiter
    _rate_limiter = None
