"""
Felix Backend - Request Size Limit Middleware

Provides middleware to limit the size of incoming HTTP requests.
This is a defense-in-depth measure to prevent denial-of-service attacks
and protect against unexpectedly large payloads.

Configuration:
- Default: 512 MB for general requests (to accommodate file uploads)
- FELIX_MAX_REQUEST_SIZE_MB environment variable to customize

Note: The sync endpoint upload_files has additional per-file limits
(100MB per file, 500MB total) that are enforced in the endpoint handler.
This middleware provides a global safety net at the application level.
"""

import os
import logging
from typing import Callable

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response, JSONResponse


logger = logging.getLogger(__name__)


# ============================================================================
# CONFIGURATION
# ============================================================================

# Default max request size: 512 MB (to accommodate large file uploads)
# This is a global safety limit; individual endpoints may have stricter limits
DEFAULT_MAX_REQUEST_SIZE_MB = 512


def get_max_request_size_bytes() -> int:
    """
    Get the maximum allowed request size in bytes from environment.
    
    Environment variables:
    - FELIX_MAX_REQUEST_SIZE_MB: Max request size in megabytes (default: 512)
    
    Returns:
        Maximum request size in bytes
    """
    max_size_mb = int(os.environ.get("FELIX_MAX_REQUEST_SIZE_MB", DEFAULT_MAX_REQUEST_SIZE_MB))
    return max_size_mb * 1024 * 1024


# ============================================================================
# MIDDLEWARE
# ============================================================================

class RequestSizeLimitMiddleware(BaseHTTPMiddleware):
    """
    Middleware to limit the size of incoming HTTP requests.
    
    Checks the Content-Length header and rejects requests that exceed
    the configured maximum size with a 413 Request Entity Too Large response.
    
    Note: This middleware relies on the Content-Length header being present.
    For chunked transfer encoding where Content-Length may be absent,
    the underlying ASGI server (uvicorn) has its own limits.
    
    Usage:
        from middleware.request_size import RequestSizeLimitMiddleware
        
        app.add_middleware(RequestSizeLimitMiddleware)
        
        # Or with custom max size:
        app.add_middleware(RequestSizeLimitMiddleware, max_size_bytes=100 * 1024 * 1024)
    """
    
    def __init__(self, app, max_size_bytes: int = None):
        """
        Initialize the middleware.
        
        Args:
            app: ASGI application
            max_size_bytes: Maximum request size in bytes (default from env var)
        """
        super().__init__(app)
        self.max_size_bytes = max_size_bytes or get_max_request_size_bytes()
        logger.info(f"Request size limit middleware initialized: max_size={self.max_size_bytes // (1024 * 1024)}MB")
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """
        Check request size before processing.
        
        Args:
            request: Incoming HTTP request
            call_next: Next handler in the chain
            
        Returns:
            Response from handler or 413 error response
        """
        # Get Content-Length header (may be missing for chunked requests)
        content_length_str = request.headers.get("content-length")
        
        if content_length_str:
            try:
                content_length = int(content_length_str)
                
                if content_length > self.max_size_bytes:
                    max_size_mb = self.max_size_bytes // (1024 * 1024)
                    actual_size_mb = content_length // (1024 * 1024)
                    
                    logger.warning(
                        f"Request rejected: size {actual_size_mb}MB exceeds limit {max_size_mb}MB "
                        f"(path={request.url.path}, method={request.method})"
                    )
                    
                    return JSONResponse(
                        status_code=413,
                        content={
                            "detail": f"Request body too large. Maximum allowed size is {max_size_mb}MB, "
                                      f"but request is {actual_size_mb}MB.",
                            "max_size_bytes": self.max_size_bytes,
                            "actual_size_bytes": content_length,
                        },
                        headers={
                            "X-Max-Request-Size": str(self.max_size_bytes),
                        }
                    )
            except ValueError:
                # Invalid Content-Length header, let the request through
                # The underlying framework will handle malformed headers
                logger.warning(f"Invalid Content-Length header: {content_length_str}")
        
        # Process the request
        return await call_next(request)


# ============================================================================
# CONVENIENCE FUNCTION
# ============================================================================

def add_request_size_limit(app, max_size_mb: int = None):
    """
    Add request size limit middleware to a FastAPI app.
    
    Convenience function for adding the middleware with logging.
    
    Args:
        app: FastAPI application instance
        max_size_mb: Optional max size in MB (default from environment)
    """
    if max_size_mb is not None:
        max_size_bytes = max_size_mb * 1024 * 1024
    else:
        max_size_bytes = get_max_request_size_bytes()
    
    app.add_middleware(RequestSizeLimitMiddleware, max_size_bytes=max_size_bytes)
