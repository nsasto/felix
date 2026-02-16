# S-0064: Run Artifact Sync - Production Readiness

**Priority:** High  
**Tags:** Production, Operations, Monitoring

## Description

As a Felix operator, I need production-ready error handling, monitoring, documentation, and security measures for run artifact syncing so that the feature can be safely deployed to production with proper observability and failure recovery.

## Dependencies

- S-0063 (Frontend Artifact Viewer) - requires complete feature implementation
- S-0062 (E2E Testing) - requires validated functionality
- S-0061 (CLI Sync Plugin) - requires CLI implementation

## Acceptance Criteria

### Error Handling - Backend

- [ ] All sync endpoints return structured error responses with error codes
- [ ] 404 errors include descriptive messages (e.g., "Run not found: {run_id}")
- [ ] 400 errors include validation details (e.g., "Invalid manifest JSON")
- [ ] 500 errors logged with full stack trace
- [ ] Database errors caught and logged with context
- [ ] Storage errors caught and returned with 503 Service Unavailable
- [ ] Timeout errors handled gracefully (don't hang indefinitely)

### Error Handling - CLI

- [ ] Sync failures don't crash agent execution
- [ ] Network errors caught and logged at warning level
- [ ] Invalid configuration shows helpful error message
- [ ] Missing backend connectivity queues requests silently
- [ ] Corrupted outbox files skipped with warning
- [ ] Agent continues execution if sync disabled mid-run

### Error Handling - Frontend

- [ ] API errors display user-friendly messages
- [ ] Network failures show "Unable to load artifacts" with retry button
- [ ] Missing artifacts show "Artifact not found" instead of blank screen
- [ ] Large file load failures offer download link as fallback
- [ ] Error boundary prevents component crashes from breaking entire UI

### Logging - Backend

- [ ] Structured logging with log levels (DEBUG, INFO, WARN, ERROR)
- [ ] Sync operation logs include run_id, agent_id for correlation
- [ ] Upload operations log file count, total size, duration
- [ ] Error logs include request details for debugging
- [ ] Log rotation configured (max size or daily rotation)

### Logging - CLI

- [ ] Verbose mode enables detailed sync logging
- [ ] Outbox queue operations logged at debug level
- [ ] Sync successes logged at info level with summary
- [ ] Sync failures logged at warning level with error details
- [ ] Logs written to .felix/sync.log file
- [ ] Log file rotation to prevent unlimited growth

### Monitoring Metrics

- [ ] Backend exposes /metrics endpoint (Prometheus format)
- [ ] Metric: sync_requests_total counter by endpoint and status
- [ ] Metric: sync_artifacts_uploaded_bytes histogram
- [ ] Metric: sync_upload_duration_seconds histogram
- [ ] Metric: sync_failures_total counter by error type
- [ ] Metric: runs_created_total counter
- [ ] Metric: run_events_inserted_total counter

### Retry Logic

- [ ] CLI plugin implements exponential backoff for retries
- [ ] Retry delays: 1s, 2s, 4s, 8s, 16s (max 5 attempts)
- [ ] Transient errors (network timeout) trigger retry
- [ ] Permanent errors (404) don't retry
- [ ] Max retry attempts configurable via FELIX_SYNC_MAX_RETRIES
- [ ] Failed requests after max retries remain in outbox

### Documentation

- [ ] AGENTS.md updated with sync troubleshooting section
- [ ] Troubleshooting includes common errors and solutions
- [ ] Documentation shows how to check outbox queue status
- [ ] Documentation explains what to do when outbox grows large
- [ ] Environment variable reference documented
- [ ] Configuration examples provided for dev/staging/prod

### Operations Documentation

- [ ] Created: `docs/SYNC_OPERATIONS.md` operations guide
- [ ] Guide includes: monitoring dashboard setup
- [ ] Guide includes: alert configuration examples
- [ ] Guide includes: backup and recovery procedures
- [ ] Guide includes: scaling considerations
- [ ] Guide includes: performance tuning recommendations

### Security Review

- [ ] Input validation on all endpoint parameters
- [ ] SQL injection prevention (parameterized queries only)
- [ ] Path traversal prevention in storage keys
- [ ] File upload size limits enforced (max 100MB per file)
- [ ] Total upload size limits enforced (max 500MB per run)
- [ ] Rate limiting on sync endpoints (100 req/min per agent)
- [ ] API key authentication properly implemented (not stub)

### API Key Management

- [ ] API keys stored hashed in database
- [ ] Key generation script created: `scripts/generate-sync-key.py`
- [ ] Key rotation procedure documented
- [ ] Keys scoped to specific agents or projects
- [ ] Expired keys rejected with 401 Unauthorized
- [ ] Key usage logged for audit trail

### Health Checks

- [ ] Backend /health endpoint includes storage check
- [ ] Health check verifies database connection
- [ ] Health check verifies storage write capability
- [ ] Health check returns 200 if all systems operational
- [ ] Health check returns 503 if database unreachable
- [ ] Health check returns 503 if storage unavailable

### Performance Tuning

- [ ] Database connection pooling configured
- [ ] Storage operations use async I/O
- [ ] Large file uploads streamed (not buffered in memory)
- [ ] Database indexes verified for query performance
- [ ] N+1 query problems identified and resolved
- [ ] Backend response times under 200ms for GET requests
- [ ] Backend upload times under 5s for typical run (5MB total)

### Rollback Plan

- [ ] Feature flag allows disabling sync globally
- [ ] Rollback procedure documented in `docs/SYNC_OPERATIONS.md`
- [ ] Database migration rollback script created
- [ ] Storage cleanup script for removing orphaned files
- [ ] Backend code rollback tested in staging
- [ ] Emergency disable instructions in AGENTS.md

## Validation Criteria

- [ ] Backend health check - `curl http://localhost:8080/health` returns 200 with storage status
- [ ] Metrics endpoint - `curl http://localhost:8080/metrics` returns Prometheus-formatted metrics
- [ ] Error handling - stop database, verify backend returns 503 errors
- [ ] CLI resilience - stop backend, run agent, verify continues without crashing
- [ ] Security - verify SQL injection attempts blocked (use SQLMap or manual test)
- [ ] Documentation - AGENTS.md troubleshooting section readable and accurate

## Technical Notes

**Architecture:** Production readiness is not just about features working, but about operating reliably at scale. Focus on observability (logs, metrics) and failure recovery.

**Monitoring:** Prometheus metrics allow integration with Grafana for dashboards and alerting. Track both technical metrics (request rate) and business metrics (runs created).

**Security:** API keys prevent unauthorized uploads. Rate limiting prevents abuse. Input validation prevents injection attacks. Defense in depth.

**Don't assume not implemented:** Check existing monitoring, logging, and security infrastructure. May have patterns established from other features.

## Non-Goals

- Distributed tracing (OpenTelemetry)
- Advanced security (OAuth, mTLS)
- Multi-region deployment
- CDN integration for artifact delivery
- Automatic performance optimization
- Machine learning anomaly detection
