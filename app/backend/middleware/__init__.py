"""
Felix Backend - Middleware Package

This package contains middleware components for the Felix backend.
"""

from .rate_limit import (
    rate_limit_dependency,
    get_rate_limiter,
    RateLimiter,
    reset_rate_limiter,
)

from .request_size import (
    RequestSizeLimitMiddleware,
    add_request_size_limit,
    get_max_request_size_bytes,
)

__all__ = [
    # Rate limiting
    "rate_limit_dependency",
    "get_rate_limiter",
    "RateLimiter",
    "reset_rate_limiter",
    # Request size limiting
    "RequestSizeLimitMiddleware",
    "add_request_size_limit",
    "get_max_request_size_bytes",
]
