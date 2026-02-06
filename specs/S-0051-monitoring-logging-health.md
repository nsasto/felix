# S-0051: Monitoring, Logging, and Health Checks

**Phase:** 4 (Production Hardening)  
**Effort:** 4-6 hours  
**Priority:** Medium  
**Dependencies:** S-0050

---

## Narrative

This specification covers implementing comprehensive logging, monitoring, and health check endpoints to ensure production reliability. This includes structured logging, database connectivity checks, performance metrics, and observability for debugging production issues.

---

## Acceptance Criteria

### Logging Configuration

- [ ] Create **app/backend/logging_config.py** with:
  - Structured logging (JSON format)
  - Log levels (DEBUG, INFO, WARNING, ERROR)
  - Request ID tracking
  - Performance timing logs

### Health Check Endpoint

- [ ] Update **app/backend/main.py** with enhanced `/health` endpoint:
  - Check database connectivity
  - Check Supabase connection
  - Return system uptime
  - Return component statuses

### Metrics Endpoint

- [ ] Create `/metrics` endpoint with:
  - Active agent count
  - Active run count
  - Total organizations
  - Database pool stats
  - Response time statistics

### Error Handling Middleware

- [ ] Add global exception handler
  - Log all errors with stack traces
  - Return consistent error format
  - Hide sensitive data in production

---

## Technical Notes

### Logging Configuration (logging_config.py)

```python
import logging
import sys
import json
from datetime import datetime
from typing import Any, Dict

class JSONFormatter(logging.Formatter):
    """Format log records as JSON"""

    def format(self, record: logging.LogRecord) -> str:
        log_data: Dict[str, Any] = {
            "timestamp": datetime.utcnow().isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno
        }

        # Add exception info if present
        if record.exc_info:
            log_data["exception"] = self.formatException(record.exc_info)

        # Add custom fields if present
        if hasattr(record, "request_id"):
            log_data["request_id"] = record.request_id

        if hasattr(record, "duration_ms"):
            log_data["duration_ms"] = record.duration_ms

        return json.dumps(log_data)

def setup_logging(log_level: str = "INFO"):
    """Configure structured logging"""

    # Create JSON formatter
    formatter = JSONFormatter()

    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(log_level)

    # Console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(formatter)
    root_logger.addHandler(console_handler)

    # Reduce noise from external libraries
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("databases").setLevel(logging.WARNING)

    logging.info("Logging configured", extra={"log_level": log_level})
```

### Enhanced Health Check (main.py)

```python
from datetime import datetime
import time

# Store startup time
startup_time = time.time()

@app.get("/health")
async def health_check():
    """Comprehensive health check endpoint"""

    health_status = {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "uptime_seconds": time.time() - startup_time,
        "components": {}
    }

    # Check database connectivity
    try:
        result = await database.fetch_one("SELECT 1 as alive")
        health_status["components"]["database"] = {
            "status": "healthy",
            "connected": True
        }
    except Exception as e:
        health_status["components"]["database"] = {
            "status": "unhealthy",
            "connected": False,
            "error": str(e)
        }
        health_status["status"] = "degraded"

    # Check Supabase connectivity
    try:
        # Simple query to verify Supabase connection
        result = await database.fetch_one("SELECT COUNT(*) FROM organizations")
        health_status["components"]["supabase"] = {
            "status": "healthy",
            "org_count": result["count"]
        }
    except Exception as e:
        health_status["components"]["supabase"] = {
            "status": "unhealthy",
            "error": str(e)
        }
        health_status["status"] = "degraded"

    # WebSocket connection manager status
    from websocket.control import control_manager
    health_status["components"]["websocket"] = {
        "status": "healthy",
        "active_connections": len(control_manager.active_connections)
    }

    return health_status

@app.get("/metrics")
async def metrics():
    """System metrics endpoint"""

    try:
        # Gather metrics from database
        stats = await database.fetch_one("""
            SELECT
                (SELECT COUNT(*) FROM agents) as agent_count,
                (SELECT COUNT(*) FROM agents WHERE status = 'running') as active_agents,
                (SELECT COUNT(*) FROM runs) as total_runs,
                (SELECT COUNT(*) FROM runs WHERE status = 'running') as active_runs,
                (SELECT COUNT(*) FROM organizations) as org_count,
                (SELECT COUNT(*) FROM projects) as project_count
        """)

        return {
            "agents": {
                "total": stats["agent_count"],
                "active": stats["active_agents"]
            },
            "runs": {
                "total": stats["total_runs"],
                "active": stats["active_runs"]
            },
            "organizations": stats["org_count"],
            "projects": stats["project_count"],
            "uptime_seconds": time.time() - startup_time,
            "timestamp": datetime.utcnow().isoformat()
        }
    except Exception as e:
        logging.error(f"Failed to collect metrics: {e}")
        raise HTTPException(status_code=500, detail="Failed to collect metrics")
```

### Request Logging Middleware

```python
import time
import uuid
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """Log all requests with timing and request ID"""

    async def dispatch(self, request: Request, call_next):
        # Generate request ID
        request_id = str(uuid.uuid4())
        request.state.request_id = request_id

        # Start timer
        start_time = time.time()

        # Log request
        logging.info(
            f"{request.method} {request.url.path}",
            extra={
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "client": request.client.host if request.client else None
            }
        )

        # Process request
        response = await call_next(request)

        # Calculate duration
        duration_ms = (time.time() - start_time) * 1000

        # Log response
        logging.info(
            f"{request.method} {request.url.path} - {response.status_code}",
            extra={
                "request_id": request_id,
                "status_code": response.status_code,
                "duration_ms": duration_ms
            }
        )

        # Add request ID to response headers
        response.headers["X-Request-ID"] = request_id

        return response

# Add middleware to app
app.add_middleware(RequestLoggingMiddleware)
```

### Global Exception Handler

```python
from fastapi import Request, status
from fastapi.responses import JSONResponse

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Catch all unhandled exceptions"""

    request_id = getattr(request.state, "request_id", "unknown")

    # Log error
    logging.error(
        f"Unhandled exception: {exc}",
        extra={
            "request_id": request_id,
            "path": request.url.path,
            "method": request.method
        },
        exc_info=True
    )

    # Return generic error response (hide details in production)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "error": "Internal server error",
            "request_id": request_id,
            "message": str(exc) if os.getenv("ENV") == "development" else "An error occurred"
        }
    )
```

### Update main.py Startup

```python
from logging_config import setup_logging
from config import LOG_LEVEL

# Setup logging
setup_logging(LOG_LEVEL)

logger = logging.getLogger(__name__)

@app.on_event("startup")
async def on_startup():
    logger.info("Starting Felix backend...")
    await database.startup()
    logger.info("Backend started successfully")

@app.on_event("shutdown")
async def on_shutdown():
    logger.info("Shutting down Felix backend...")
    await database.shutdown()
    logger.info("Backend shut down successfully")
```

---

## Dependencies

**Depends On:**

- S-0050: Data Migration Script

**Blocks:**

- S-0052: Docker Containerization and Deployment

---

## Validation Criteria

### Logging Verification

- [ ] Backend starts with structured JSON logs
- [ ] Logs include timestamp, level, logger, message
- [ ] Request logs include request_id and duration_ms
- [ ] Error logs include stack traces

### Health Check Test

```bash
curl http://localhost:8080/health | jq
```

Expected output:

```json
{
  "status": "healthy",
  "timestamp": "2026-01-26T15:42:19.123456",
  "uptime_seconds": 3600.5,
  "components": {
    "database": {
      "status": "healthy",
      "connected": true
    },
    "supabase": {
      "status": "healthy",
      "org_count": 2
    },
    "websocket": {
      "status": "healthy",
      "active_connections": 1
    }
  }
}
```

### Metrics Test

```bash
curl http://localhost:8080/metrics | jq
```

Expected output:

```json
{
  "agents": {
    "total": 3,
    "active": 1
  },
  "runs": {
    "total": 147,
    "active": 0
  },
  "organizations": 2,
  "projects": 2,
  "uptime_seconds": 3600.5,
  "timestamp": "2026-01-26T15:42:19.123456"
}
```

### Request Logging Test

```bash
# Make API request
curl http://localhost:8080/api/agents

# Check logs
# Should see:
# {"timestamp": "...", "level": "INFO", "message": "GET /api/agents", "request_id": "...", ...}
# {"timestamp": "...", "level": "INFO", "message": "GET /api/agents - 200", "duration_ms": 45.2, ...}
```

### Error Handling Test

```bash
# Trigger error (e.g., invalid agent ID)
curl http://localhost:8080/api/agents/invalid-uuid

# Should return:
# {"error": "Internal server error", "request_id": "...", "message": "..."}

# Check logs for error with stack trace
```

---

## Rollback Strategy

If logging causes issues:

1. Remove RequestLoggingMiddleware
2. Remove global exception handler
3. Use default FastAPI logging
4. Debug logging configuration

---

## Notes

- JSON logging is machine-readable for log aggregation tools
- Request IDs enable tracing requests across services
- Health check supports load balancer health probes
- Metrics endpoint useful for monitoring dashboards (Grafana, Datadog)
- LOG_LEVEL environment variable controls verbosity
- Production should use INFO level (not DEBUG)
- Middleware adds ~1-2ms overhead per request (negligible)
- Exception handler prevents sensitive data leaks
- Uptime metric helps identify restart frequency
- WebSocket connection count tracks active agents
