# Run Artifact Sync - Operations Guide

This guide covers operational procedures for the Felix Run Artifact Sync feature, including monitoring setup, alerting, backup/recovery, scaling, and performance tuning.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Authentication & Security](#authentication--security)
- [Monitoring Dashboard Setup](#monitoring-dashboard-setup)
- [Alert Configuration](#alert-configuration)
- [Backup and Recovery](#backup-and-recovery)
- [Scaling Considerations](#scaling-considerations)
- [Performance Tuning](#performance-tuning)
- [Rollback Procedures](#rollback-procedures)
- [Troubleshooting](#troubleshooting)

---

## Architecture Overview

### Data Flow

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Felix CLI      │────>│  Backend API     │────>│  PostgreSQL     │
│  (.felix/)      │     │  (FastAPI)       │     │  (runs, events) │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │
                               │
                               ▼
                        ┌─────────────────┐
                        │  Artifact Store │
                        │  (local/cloud)  │
                        └─────────────────┘
```

### Components

| Component        | Description                  | Port |
| ---------------- | ---------------------------- | ---- |
| Backend API      | FastAPI sync endpoints       | 8080 |
| CLI Plugin       | PowerShell sync-fastapi.ps1  | N/A  |
| PostgreSQL       | Run metadata and events      | 5432 |
| Artifact Storage | File system or cloud storage | N/A  |
| Frontend         | React artifact viewer        | 3000 |

### Key Endpoints

| Endpoint              | Method   | Description                 |
| --------------------- | -------- | --------------------------- |
| /health               | GET      | Health check (DB + storage) |
| /metrics              | GET      | Prometheus metrics          |
| /api/agents/register  | POST     | Register CLI agent          |
| /api/runs             | POST     | Create new run              |
| /api/runs/{id}/events | POST/GET | Append/query events         |
| /api/runs/{id}/files  | POST/GET | Upload/list files           |
| /api/runs/{id}/finish | POST     | Complete run                |

---

## Authentication & Security

### Project-Scoped API Keys

Felix sync endpoints require project-scoped API keys for authentication. Each API key grants access to a single project's artifacts and data.

**Key Properties:**

- **Format:** `fsk_` prefix + 32 hex characters (256-bit entropy)
- **Scoping:** One key = one project (no multi-project keys)
- **Storage:** SHA256 hashed in database, plain-text shown only once
- **Expiration:** Optional (30, 90, 180, 365 days, or never)
- **Revocation:** Immediate via UI or API endpoint

### Generating API Keys

**Via UI (Recommended):**

1. Log in to Felix at http://localhost:3000 (or your deployment URL)
2. Select your project from the sidebar
3. Navigate to **Settings → API Keys**
4. Click **"New Key"** button
5. Enter a descriptive name (e.g., "CI Pipeline", "Developer Laptop")
6. Select expiration period or "Never"
7. Click **Generate**
8. **Copy the key immediately** - it won't be shown again

**Via API:**

```bash
# Requires user authentication token
curl -X POST "http://localhost:8080/api/projects/{project_id}/keys" \
  -H "Authorization: Bearer {user_token}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "CI Pipeline Key",
    "expires_days": 365
  }'

# Response includes plain-text key (only time it's returned)
{
  "id": "key-uuid",
  "name": "CI Pipeline Key",
  "key": "fsk_abc123...",  // Save this immediately
  "created_at": "2026-02-17T12:00:00Z",
  "expires_at": "2027-02-17T12:00:00Z"
}
```

### CLI Configuration

**Environment Variables (Recommended for CI/CD):**

```powershell
# Windows PowerShell
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "https://felix.example.com"
$env:FELIX_SYNC_KEY = "fsk_your_api_key_here"

# Linux/macOS Bash
export FELIX_SYNC_ENABLED=true
export FELIX_SYNC_URL=https://felix.example.com
export FELIX_SYNC_KEY=fsk_your_api_key_here
```

**Config File (for persistent local setup):**

```json
// .felix/config.json
{
  "sync": {
    "enabled": true,
    "provider": "fastapi",
    "base_url": "https://felix.example.com",
    "api_key": "fsk_your_api_key_here"
  }
}
```

**⚠️ Security Best Practices:**

- **Never commit API keys to version control**
- Add `.felix/config.json` to `.gitignore` (already configured)
- Use environment variables in CI/CD pipelines
- Rotate keys quarterly or on team member departure
- Use descriptive names to track key usage
- Set reasonable expiration periods (90-365 days)
- Revoke keys immediately if compromised

### Authentication Flow

```
┌──────────────┐                           ┌──────────────────┐
│  Felix CLI   │                           │  Backend API     │
│              │    POST /api/runs         │                  │
│              │  Authorization: Bearer    │                  │
│              │  fsk_abc123...            │                  │
│              │──────────────────────────>│                  │
│              │                           │  1. Hash API key │
│              │                           │  2. Lookup in DB │
│              │                           │  3. Get project  │
│              │                           │  4. Validate     │
│              │                           │                  │
│              │<──────────────────────────│  200 OK          │
│              │                           │  (or 401/403)    │
└──────────────┘                           └──────────────────┘
```

**Status Codes:**

- `200 OK` - Valid key, authorized for project
- `401 Unauthorized` - Missing, invalid, or expired key
- `403 Forbidden` - Valid key, but wrong project (key is project-scoped)
- `429 Too Many Requests` - Rate limit exceeded (100 requests/minute per key)

### Key Management API

**List Project Keys** (metadata only, no plain-text keys):

```bash
GET /api/projects/{project_id}/keys
Authorization: Bearer {user_token}

# Response
{
  "keys": [
    {
      "id": "key-uuid",
      "name": "Developer Laptop",
      "created_at": "2026-02-01T10:00:00Z",
      "last_used_at": "2026-02-17T09:30:00Z",
      "expires_at": null,
      "is_revoked": false
    }
  ],
  "count": 1
}
```

**Revoke Key** (immediate effect):

```bash
DELETE /api/projects/{project_id}/keys/{key_id}
Authorization: Bearer {user_token}

# Response: 204 No Content
```

### Security Auditing

**Track Key Usage:**

```sql
-- View recent API key activity
SELECT
  ak.name,
  ak.last_used_at,
  COUNT(r.id) as run_count
FROM api_keys ak
LEFT JOIN runs r ON r.project_id = ak.project_id
WHERE ak.project_id = {project_id}
  AND ak.is_revoked = false
  AND r.created_at > NOW() - INTERVAL '7 days'
GROUP BY ak.id, ak.name, ak.last_used_at
ORDER BY ak.last_used_at DESC;
```

**Monitor Failed Auth Attempts:**

```promql
# Prometheus query for 401/403 errors
rate(http_requests_total{endpoint="/api/runs", status=~"401|403"}[5m])
```

**Alert on Suspicious Activity:**

```yaml
# Prometheus alert rule
- alert: HighAuthFailureRate
  expr: |
    rate(http_requests_total{status=~"401|403"}[5m]) > 10
  for: 5m
  annotations:
    summary: "High rate of auth failures detected"
    description: "More than 10 failed auth attempts/sec for 5 minutes"
```

---

## Monitoring Dashboard Setup

### Prometheus Configuration

Add the Felix backend as a scrape target in your **prometheus.yml**:

```yaml
scrape_configs:
  - job_name: "felix-backend"
    scrape_interval: 15s
    scrape_timeout: 10s
    static_configs:
      - targets: ["localhost:8080"]
    metrics_path: "/metrics"
```

For multiple instances (load-balanced deployment):

```yaml
scrape_configs:
  - job_name: "felix-backend"
    scrape_interval: 15s
    static_configs:
      - targets:
          - "felix-backend-1:8080"
          - "felix-backend-2:8080"
          - "felix-backend-3:8080"
```

### Grafana Dashboard

Import the following dashboard JSON or create panels manually.

#### Key Panels to Create

**1. Sync Request Rate (requests/sec)**

```promql
rate(sync_requests_total[5m])
```

**2. Sync Success Rate (%)**

```promql
sum(rate(sync_requests_total{status="200"}[5m])) / sum(rate(sync_requests_total[5m])) * 100
```

**3. Upload Size Distribution**

```promql
histogram_quantile(0.95, sum(rate(sync_artifacts_uploaded_bytes_bucket[5m])) by (le))
```

**4. Upload Duration P95**

```promql
histogram_quantile(0.95, sum(rate(sync_upload_duration_seconds_bucket[5m])) by (le))
```

**5. Error Rate by Type**

```promql
rate(sync_failures_total[5m])
```

**6. Runs Created (daily)**

```promql
increase(runs_created_total[24h])
```

**7. Events Inserted (hourly)**

```promql
increase(run_events_inserted_total[1h])
```

**8. Process Uptime**

```promql
process_uptime_seconds
```

### Sample Dashboard JSON

Save as **felix-sync-dashboard.json** and import into Grafana:

```json
{
  "title": "Felix Run Artifact Sync",
  "uid": "felix-sync",
  "version": 1,
  "panels": [
    {
      "title": "Request Rate",
      "type": "graph",
      "targets": [
        {
          "expr": "sum(rate(sync_requests_total[5m])) by (endpoint)",
          "legendFormat": "{{endpoint}}"
        }
      ],
      "gridPos": { "x": 0, "y": 0, "w": 12, "h": 8 }
    },
    {
      "title": "Error Rate",
      "type": "graph",
      "targets": [
        {
          "expr": "sum(rate(sync_failures_total[5m])) by (error_type)",
          "legendFormat": "{{error_type}}"
        }
      ],
      "gridPos": { "x": 12, "y": 0, "w": 12, "h": 8 }
    },
    {
      "title": "Upload Duration P95",
      "type": "stat",
      "targets": [
        {
          "expr": "histogram_quantile(0.95, sum(rate(sync_upload_duration_seconds_bucket[5m])) by (le))"
        }
      ],
      "gridPos": { "x": 0, "y": 8, "w": 6, "h": 4 }
    },
    {
      "title": "Runs Created Today",
      "type": "stat",
      "targets": [
        {
          "expr": "increase(runs_created_total[24h])"
        }
      ],
      "gridPos": { "x": 6, "y": 8, "w": 6, "h": 4 }
    }
  ]
}
```

---

## Alert Configuration

### Prometheus Alerting Rules

Create **felix-alerts.yml** in your Prometheus rules directory:

```yaml
groups:
  - name: felix-sync
    rules:
      # High error rate alert
      - alert: FelixSyncHighErrorRate
        expr: |
          sum(rate(sync_failures_total[5m])) / sum(rate(sync_requests_total[5m])) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High sync error rate detected"
          description: "Error rate is {{ $value | humanizePercentage }} over the last 5 minutes"

      # Backend down alert
      - alert: FelixBackendDown
        expr: up{job="felix-backend"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Felix backend is down"
          description: "Backend instance {{ $labels.instance }} is unreachable"

      # Database unhealthy alert
      - alert: FelixDatabaseUnhealthy
        expr: felix_health_database == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Felix database health check failing"
          description: "Database connectivity check has been failing for 2 minutes"

      # Storage unhealthy alert
      - alert: FelixStorageUnhealthy
        expr: felix_health_storage == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Felix storage health check failing"
          description: "Storage write capability check has been failing for 2 minutes"

      # Slow uploads alert
      - alert: FelixSlowUploads
        expr: |
          histogram_quantile(0.95, sum(rate(sync_upload_duration_seconds_bucket[5m])) by (le)) > 10
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Slow artifact uploads detected"
          description: "P95 upload duration is {{ $value }}s (target: <5s)"

      # High upload volume alert
      - alert: FelixHighUploadVolume
        expr: rate(sync_artifacts_uploaded_bytes_sum[5m]) > 104857600 # 100MB/min
        for: 5m
        labels:
          severity: info
        annotations:
          summary: "High upload volume detected"
          description: "Upload rate is {{ $value | humanize1024 }}B/min"

      # Rate limiting triggered
      - alert: FelixRateLimitTriggered
        expr: sum(rate(sync_requests_total{status="429"}[5m])) > 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Rate limiting is being triggered"
          description: "Some agents are being rate limited"
```

### Alertmanager Configuration

Example **alertmanager.yml** for routing alerts:

```yaml
route:
  group_by: ["alertname"]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: "default"
  routes:
    - match:
        severity: critical
      receiver: "pagerduty"
    - match:
        severity: warning
      receiver: "slack"

receivers:
  - name: "default"
    email_configs:
      - to: "felix-alerts@example.com"

  - name: "pagerduty"
    pagerduty_configs:
      - service_key: "<your-pagerduty-key>"

  - name: "slack"
    slack_configs:
      - api_url: "https://hooks.slack.com/services/xxx/yyy/zzz"
        channel: "#felix-alerts"
        text: "{{ .CommonAnnotations.description }}"
```

---

## Backup and Recovery

### Database Backup

**Regular Backups (Daily)**

```bash
# PostgreSQL dump of Felix tables
pg_dump -h localhost -U felix -d felix \
  -t runs -t run_events -t run_files -t agents -t api_keys \
  -F c -f felix_backup_$(date +%Y%m%d).dump
```

**Point-in-Time Recovery (PITR)**

For production, enable PostgreSQL WAL archiving for point-in-time recovery:

```sql
-- postgresql.conf
archive_mode = on
archive_command = 'cp %p /backup/wal/%f'
```

### Artifact Storage Backup

**Local Filesystem**

```bash
# Sync artifacts to backup location
rsync -avz /data/felix/artifacts/ /backup/felix/artifacts/
```

**Cloud Storage (S3/GCS)**

```bash
# AWS S3
aws s3 sync s3://felix-artifacts/ s3://felix-artifacts-backup/

# Google Cloud Storage
gsutil rsync -r gs://felix-artifacts/ gs://felix-artifacts-backup/
```

### Recovery Procedures

**Database Recovery**

```bash
# Restore from dump file
pg_restore -h localhost -U felix -d felix \
  -c --if-exists felix_backup_20260217.dump
```

**Artifact Recovery**

```bash
# Restore artifacts from backup
rsync -avz /backup/felix/artifacts/ /data/felix/artifacts/
```

**Full System Recovery Checklist**

1. [ ] Restore PostgreSQL database from backup
2. [ ] Restore artifact storage files
3. [ ] Verify database connectivity: `curl http://localhost:8080/health`
4. [ ] Verify storage connectivity: health check should show `"storage": true`
5. [ ] Run test sync from CLI agent to verify end-to-end flow
6. [ ] Check metrics endpoint returns data: `curl http://localhost:8080/metrics`
7. [ ] Monitor logs for errors after recovery

### Disaster Recovery

For disaster recovery across regions:

1. **Database Replication**: Use PostgreSQL streaming replication to a standby in another region
2. **Storage Replication**: Enable cross-region replication for cloud storage buckets
3. **DNS Failover**: Configure DNS failover to redirect traffic to DR site
4. **Recovery Time Objective (RTO)**: Target 30 minutes for full failover
5. **Recovery Point Objective (RPO)**: Target 5 minutes of data loss maximum

---

## Scaling Considerations

### Horizontal Scaling

**Backend API**

The Felix backend is stateless and can be horizontally scaled:

```yaml
# docker-compose.yml example
services:
  felix-backend:
    image: felix-backend:latest
    deploy:
      replicas: 3
    environment:
      DATABASE_URL: postgresql://...
      STORAGE_BACKEND: s3
```

Load balancer configuration (nginx example):

```nginx
upstream felix_backend {
    least_conn;
    server felix-backend-1:8080;
    server felix-backend-2:8080;
    server felix-backend-3:8080;
}

server {
    listen 80;
    location / {
        proxy_pass http://felix_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### Vertical Scaling

**Database**

- Increase `shared_buffers` to 25% of RAM
- Increase `work_mem` for complex queries
- Use SSD storage for better I/O

**Backend**

- Increase uvicorn workers: `uvicorn main:app --workers 4`
- Allocate more memory for large file uploads

### Storage Scaling

**Local Filesystem**

- Use LVM for easy volume expansion
- Consider NFS/CIFS for shared storage across instances

**Cloud Storage**

- S3/GCS scale automatically
- Use multipart uploads for files >100MB
- Enable lifecycle rules for old artifact cleanup

### Database Scaling

**Connection Pooling**

The `databases` library uses connection pooling by default. Tune with:

```python
# Increase pool size for high concurrency
DATABASE_URL = "postgresql://user:pass@host/db?min_size=5&max_size=20"
```

**Read Replicas**

For read-heavy workloads, use PostgreSQL read replicas:

```python
# Primary for writes
WRITE_DATABASE_URL = "postgresql://primary:5432/felix"
# Replica for reads
READ_DATABASE_URL = "postgresql://replica:5432/felix"
```

### Capacity Planning

| Load Level | Agents | Runs/Day | Storage/Day | Recommended Setup             |
| ---------- | ------ | -------- | ----------- | ----------------------------- |
| Small      | 1-5    | <100     | <1GB        | Single instance               |
| Medium     | 5-20   | 100-500  | 1-10GB      | 2 instances + RDS             |
| Large      | 20-100 | 500-2000 | 10-50GB     | 3+ instances + RDS + S3       |
| Enterprise | 100+   | 2000+    | 50GB+       | Kubernetes + managed services |

---

## Performance Tuning

### Backend Tuning

**Uvicorn Configuration**

```bash
# Production settings
uvicorn main:app \
  --host 0.0.0.0 \
  --port 8080 \
  --workers 4 \
  --loop uvloop \
  --http httptools \
  --timeout-keep-alive 30
```

**Request Body Limits**

Set in **main.py** or uvicorn config:

```python
# Already configured: 600MB request body limit
# Adjust if needed for your use case
```

**Response Time Targets**

| Operation                       | Target | Typical  |
| ------------------------------- | ------ | -------- |
| GET /health                     | <50ms  | 10-20ms  |
| GET /metrics                    | <100ms | 20-50ms  |
| POST /api/runs                  | <200ms | 50-100ms |
| POST /api/runs/{id}/events      | <200ms | 50-150ms |
| POST /api/runs/{id}/files (5MB) | <5s    | 1-3s     |
| GET /api/runs/{id}/files        | <200ms | 50-100ms |

### Database Tuning

**Index Verification**

Ensure all indexes are present (from migration 015):

```sql
-- Check indexes exist
SELECT indexname FROM pg_indexes
WHERE tablename IN ('runs', 'run_events', 'run_files');

-- Expected indexes:
-- idx_runs_org_project_created
-- idx_runs_project_requirement_created
-- idx_runs_agent_created
-- idx_runs_status_created
-- idx_run_events_run_ts
-- idx_run_events_type_ts
-- idx_run_events_level_ts
-- idx_run_files_run_id
-- idx_run_files_run_kind
-- idx_run_files_sha256
```

**Query Performance**

Monitor slow queries:

```sql
-- Enable slow query logging
ALTER SYSTEM SET log_min_duration_statement = '100ms';
SELECT pg_reload_conf();
```

**Connection Pool Settings**

```ini
# postgresql.conf
max_connections = 100
shared_buffers = 256MB
work_mem = 16MB
effective_cache_size = 512MB
```

### Storage Tuning

**Filesystem**

```bash
# Use noatime for better write performance
mount -o noatime,nodiratime /dev/sdb1 /data/felix/artifacts
```

**S3 Configuration**

```python
# Use multipart uploads for large files
# Transfer acceleration for geo-distributed agents
s3_client = boto3.client('s3', config=Config(
    s3={'use_accelerate_endpoint': True}
))
```

### CLI Tuning

**Batch Size**

The CLI plugin batches uploads per run. Adjust outbox processing frequency:

```powershell
# Environment variable to control retry attempts
$env:FELIX_SYNC_MAX_RETRIES = "5"  # Default
```

**Network Optimization**

For slow networks, increase timeouts in the CLI plugin configuration.

### Caching Recommendations

**Frontend Caching**

```nginx
# Cache artifact downloads
location /api/runs/ {
    proxy_cache felix_cache;
    proxy_cache_valid 200 1h;
    proxy_cache_use_stale error timeout;
}
```

**Backend Response Caching**

For frequently accessed artifacts, consider adding Redis caching layer.

---

## Rollback Procedures

### Emergency Disable

To immediately disable sync without code changes:

**CLI Side (per-agent)**

```powershell
$env:FELIX_SYNC_ENABLED = "false"
```

Or edit **.felix/config.json**:

```json
{
  "sync": {
    "enabled": false
  }
}
```

**Server Side (global)**

Set the environment variable on the backend:

```bash
export FELIX_SYNC_FEATURE_ENABLED=false
```

Or in production deployment config (e.g., Kubernetes ConfigMap):

```yaml
data:
  FELIX_SYNC_FEATURE_ENABLED: "false"
```

### Database Rollback

Migration 015 includes rollback instructions. To rollback:

```sql
-- 1. Drop triggers
DROP TRIGGER IF EXISTS set_updated_at_run_files ON run_files;

-- 2. Drop new tables
DROP TABLE IF EXISTS run_files CASCADE;
DROP TABLE IF EXISTS run_events CASCADE;

-- 3. Drop new indexes on runs
DROP INDEX IF EXISTS idx_runs_org_project_created;
DROP INDEX IF EXISTS idx_runs_project_requirement_created;
DROP INDEX IF EXISTS idx_runs_agent_created;
DROP INDEX IF EXISTS idx_runs_status_created;

-- 4. Restore original runs status constraint
ALTER TABLE runs DROP CONSTRAINT IF EXISTS runs_status_check;
ALTER TABLE runs ADD CONSTRAINT runs_status_check CHECK (
    status IN ('pending', 'running', 'completed', 'failed', 'cancelled')
);

-- 5. Drop new columns from runs
ALTER TABLE runs DROP COLUMN IF EXISTS finished_at;
ALTER TABLE runs DROP COLUMN IF EXISTS exit_code;
ALTER TABLE runs DROP COLUMN IF EXISTS duration_sec;
ALTER TABLE runs DROP COLUMN IF EXISTS summary_json;
ALTER TABLE runs DROP COLUMN IF EXISTS error_summary;
ALTER TABLE runs DROP COLUMN IF EXISTS commit_sha;
ALTER TABLE runs DROP COLUMN IF EXISTS branch;
ALTER TABLE runs DROP COLUMN IF EXISTS scenario;
ALTER TABLE runs DROP COLUMN IF EXISTS phase;
ALTER TABLE runs DROP COLUMN IF EXISTS org_id;

-- 6. Drop new columns from agents
ALTER TABLE agents DROP COLUMN IF EXISTS last_seen_at;
ALTER TABLE agents DROP COLUMN IF EXISTS version;
ALTER TABLE agents DROP COLUMN IF EXISTS platform;
ALTER TABLE agents DROP COLUMN IF EXISTS hostname;
```

### Storage Cleanup

To remove orphaned artifacts after rollback:

```powershell
# Run the cleanup script
.\scripts\cleanup-orphan-artifacts.ps1 -DryRun  # Preview only
.\scripts\cleanup-orphan-artifacts.ps1          # Actually delete
```

The cleanup script (once created) will:

1. List all storage keys under `runs/`
2. Query database for valid run_files records
3. Delete any storage objects not referenced in the database

### Code Rollback

For backend code rollback:

```bash
# Identify the last good commit
git log --oneline -10

# Revert to previous version
git checkout <commit-hash> -- app/backend/routers/sync.py

# Or use git revert for a clean history
git revert <bad-commit-hash>
```

### Rollback Checklist

1. [ ] Disable sync on CLI agents (environment variable or config)
2. [ ] Verify no new uploads are being sent
3. [ ] Backup current database state
4. [ ] Run database rollback SQL
5. [ ] Deploy previous backend version (if needed)
6. [ ] Clear frontend cache
7. [ ] Run storage cleanup (optional - orphaned files don't cause harm)
8. [ ] Verify health check returns 200
9. [ ] Monitor for errors
10. [ ] Communicate status to users

---

## Troubleshooting

### Common Issues

See **AGENTS.md** for CLI-specific troubleshooting. This section covers backend and operational issues.

#### Backend Won't Start

**Symptom:** Backend fails to start, logs show database connection errors.

**Solution:**

```bash
# Check PostgreSQL is running
pg_isready -h localhost -p 5432

# Check connection string
echo $DATABASE_URL

# Test connection manually
psql $DATABASE_URL -c "SELECT 1"
```

#### 401 Unauthorized - API Key Issues

**Symptom:** CLI agent fails with 401 Unauthorized error.

**Causes:**

1. Missing API key (sync enabled but no key configured)
2. Invalid API key (typo, truncated, or malformed)
3. Expired API key
4. Revoked API key

**Solution:**

```powershell
# 1. Generate new API key via UI
# - Open Felix UI → Settings → API Keys
# - Click "New Key"
# - Copy the key (starts with fsk_)

# 2. Set the key
$env:FELIX_SYNC_KEY = "fsk_your_new_key_here"

# 3. Run agent again
felix run S-0001

# Verify key format is correct:
# - Must start with "fsk_"
# - Followed by 32 hexadecimal characters
# - Total length: 36 characters
```

#### 403 Forbidden - Wrong Project

**Symptom:** Valid API key but sync fails with 403 Forbidden.

**Cause:** API key belongs to different project than the one you're trying to sync to.

**Solution:**

```powershell
# Check which project the key belongs to:
# 1. Go to Felix UI → Settings → API Keys
# 2. Find your key in the list
# 3. Note the project name

# Option 1: Generate new key for correct project
# - Select correct project in UI
# - Go to Settings → API Keys
# - Generate new key

# Option 2: Use existing key for its project
# - Switch to the project that matches your API key
```

#### Health Check Returns 503

**Symptom:** `/health` returns 503 with `"status": "unhealthy"`.

**Diagnose:**

```bash
# Check response
curl -s http://localhost:8080/health | jq

# Example unhealthy response:
# {"status": "unhealthy", "database": false, "storage": true}
```

**Solution:**

- If `"database": false` - check PostgreSQL connectivity
- If `"storage": false` - check filesystem permissions or cloud storage credentials

#### Metrics Not Showing in Prometheus

**Symptom:** Prometheus shows no data for Felix metrics.

**Diagnose:**

```bash
# Check metrics endpoint works
curl http://localhost:8080/metrics

# Check Prometheus targets
# Visit: http://prometheus:9090/targets
```

**Solution:**

- Verify Prometheus scrape config has correct host/port
- Check firewall allows Prometheus to reach backend
- Ensure backend is running and healthy

#### Slow Upload Performance

**Symptom:** File uploads taking >5s for small files.

**Diagnose:**

```bash
# Check upload duration histogram
curl -s http://localhost:8080/metrics | grep sync_upload_duration
```

**Solution:**

- Check storage backend performance (disk I/O, network latency)
- Verify database is not overloaded
- Consider increasing backend workers

#### Rate Limiting Issues

**Symptom:** Agents receiving 429 Too Many Requests.

**Diagnose:**

```bash
# Check rate limit headers in response
curl -I http://localhost:8080/api/runs

# Look for:
# X-RateLimit-Remaining: 95
# X-RateLimit-Reset: 1708185600
```

**Solution:**

- Default limit is 100 requests/minute per agent
- Spread uploads over time if limit is reached
- Contact admin to adjust rate limits if legitimate high volume

### Log Analysis

**Backend Logs**

```bash
# View recent errors
grep -E "ERROR|WARN" /var/log/felix/backend.log | tail -50

# Search for specific run
grep "run_id=abc123" /var/log/felix/backend.log
```

**CLI Sync Logs**

```powershell
# View recent CLI sync logs
Get-Content .felix\sync.log -Tail 50

# Search for errors
Select-String -Path .felix\sync.log -Pattern "ERROR|WARN"
```

### Getting Help

1. Check this operations guide
2. Review **AGENTS.md** troubleshooting section
3. Search logs for specific error messages
4. Check GitHub issues for known problems
5. Contact the Felix team with:
   - Full error message
   - Steps to reproduce
   - Relevant log excerpts
   - Environment details (OS, Python version, etc.)

---

## Appendix

### Environment Variables Reference

| Variable                   | Description                              | Default     |
| -------------------------- | ---------------------------------------- | ----------- |
| DATABASE_URL               | PostgreSQL connection string             | Required    |
| STORAGE_BACKEND            | Storage type (filesystem, s3)            | filesystem  |
| STORAGE_PATH               | Local storage path                       | ./artifacts |
| FELIX_SYNC_FEATURE_ENABLED | Global feature flag                      | true        |
| LOG_LEVEL                  | Logging level (DEBUG, INFO, WARN, ERROR) | INFO        |
| RATE_LIMIT_REQUESTS        | Requests per minute per agent            | 100         |

### API Rate Limits

| Endpoint              | Limit   | Window  |
| --------------------- | ------- | ------- |
| /api/agents/register  | 100/min | Sliding |
| /api/runs             | 100/min | Sliding |
| /api/runs/{id}/events | 100/min | Sliding |
| /api/runs/{id}/files  | 100/min | Sliding |
| /api/runs/{id}/finish | 100/min | Sliding |

### File Size Limits

| Limit                    | Value  |
| ------------------------ | ------ |
| Single file max          | 100 MB |
| Total upload per request | 500 MB |
| Request body max         | 600 MB |

### Metric Names Reference

| Metric                        | Type      | Labels           | Description             |
| ----------------------------- | --------- | ---------------- | ----------------------- |
| sync_requests_total           | counter   | endpoint, status | Total sync API requests |
| runs_created_total            | counter   | -                | Total runs created      |
| run_events_inserted_total     | counter   | -                | Total events inserted   |
| sync_failures_total           | counter   | error_type       | Total sync failures     |
| sync_artifacts_uploaded_bytes | histogram | -                | Upload sizes            |
| sync_upload_duration_seconds  | histogram | -                | Upload durations        |
| process_uptime_seconds        | gauge     | -                | Backend uptime          |
