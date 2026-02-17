# Chapter 9: Running Sync in Production

You've learned the theory, seen the code, read about the bugs. Now let's run this system in production.

## Day 1: Deployment

### Step 1: Set Up the Backend

```bash
# 1. Clone the repository
git clone https://github.com/yourorg/felix.git
cd felix

# 2. Create production database
createdb felix_production

# 3. Run all migrations in order
psql -U postgres -d felix_production -f app/backend/migrations/001_initial_schema.sql
psql -U postgres -d felix_production -f app/backend/migrations/015_run_sync_schema.sql
psql -U postgres -d felix_production -f app/backend/migrations/016_api_keys.sql
psql -U postgres -d felix_production -f app/backend/migrations/017_agent_adapter_metadata.sql

# 4. Set production environment variables
export DATABASE_URL="postgresql://felix_user:password@localhost/felix_production"
export STORAGE_PATH="/var/felix/storage"
export FELIX_SYNC_FEATURE_ENABLED="true"

# 5. Create storage directory
mkdir -p /var/felix/storage
chown felix:felix /var/felix/storage

# 6. Start backend
cd app/backend
python main.py
```

**Verify it works:**

```bash
curl http://localhost:8080/health
# Expected: {"status": "healthy", "database": "connected"}
```

### Step 2: Generate API Keys

```bash
python scripts/generate-sync-key.py
# Outputs: fsk_a7b3c9d1e4f6a8b2c5d7e9f1a3b5c7d9

# Store securely (1Password, Vault, etc.)
```

**Why API keys?**

- Identify which team/agent is uploading
- Revoke compromised keys
- Rate limit per key
- Audit trail

### Step 3: Configure CLI Agents

**For each developer machine:**

```powershell
# Add to PowerShell profile or .bashrc
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "https://felix.yourcompany.com"
$env:FELIX_SYNC_KEY = "fsk_your_team_key_here"
```

**Or in `.felix/config.json`:**

```json
{
  "sync": {
    "enabled": true,
    "provider": "fastapi",
    "base_url": "https://felix.yourcompany.com",
    "api_key": "fsk_your_team_key_here"
  }
}
```

**Test it:**

```powershell
felix run S-0000
# Expected: [INFO] [sync] Sync enabled → https://felix.yourcompany.com
#           [INFO] [sync] Agent registered successfully
```

### Step 4: Start Frontend

```bash
cd app/frontend

# Install dependencies
npm install

# Build for production
npm run build

# Serve with nginx/Apache/whatever
cp -r dist/* /var/www/felix/
```

**Access:** https://felix.yourcompany.com

**You should see:**

- Runs list
- Agent registrations
- Artifact viewer

## Monitoring

### Key Metrics

**Backend exports Prometheus metrics:**

```bash
curl http://localhost:8080/metrics
```

**Important metrics:**

```
# Requests
sync_requests_total{status="200"}  # Successful uploads
sync_requests_total{status="429"}  # Rate limited
sync_requests_total{status="500"}  # Server errors

# Artifacts
sync_artifacts_uploaded_total       # Files uploaded
sync_artifacts_uploaded_bytes       # Bandwidth used
sync_artifacts_skipped_total        # Deduplicated files

# Database
run_events_inserted_total           # Events logged
run_files_created_total             # Files stored

# Performance
http_request_duration_seconds       # Request latency
```

### Alerts to Set Up

**Critical: Backend Down**

```yaml
- alert: SyncBackendDown
  expr: up{job="felix-backend"} == 0
  for: 5m
  annotations:
    summary: "Felix sync backend is down"
    description: "Agents can't upload artifacts"
```

**Warning: High Error Rate**

```yaml
- alert: SyncHighErrorRate
  expr: rate(sync_requests_total{status="500"}[5m]) > 0.05
  for: 10m
  annotations:
    summary: "Felix sync error rate > 5%"
```

**Warning: Rate Limit Exceeded**

```yaml
- alert: SyncRateLimitExceeded
  expr: rate(sync_requests_total{status="429"}[5m]) > 10
  for: 5m
  annotations:
    summary: "Many agents hitting rate limit"
    description: "Consider increasing limit or investigating runaway agent"
```

### Grafana Dashboard

**Create dashboard with:**

1. **Uploads per hour** (line graph)
2. **Error rate** (line graph)
3. **Storage used** (gauge)
4. **Active agents** (stat panel)
5. **Avg upload size** (stat panel)

**Query examples:**

```promql
# Uploads per hour
rate(sync_artifacts_uploaded_total[1h])

# Error rate
rate(sync_requests_total{status="500"}[5m])
/
rate(sync_requests_total[5m])

# Active agents (in last hour)
count(agent_last_seen{last_seen_seconds < 3600})
```

## Maintenance

### Daily Tasks

**Check for stuck uploads:**

```bash
# CLI will have large outbox directories
# Example script to check agent machines:
for host in $(cat agent_hosts.txt); do
    ssh $host "ls .felix/outbox/*.jsonl | wc -l"
done
```

**Expected:** 0-5 files per agent (retry queue)  
**Problem:** 50+ files (backend down or agent misconfigured)

### Weekly Tasks

**Review logs for warnings:**

```bash
grep "WARN\\|ERROR" /var/felix/logs/app.log | tail -100
```

**Common warnings to investigate:**

- API key authentication failures (compromised key?)
- Repeated network failures (firewall change?)
- Database connection timeouts (needs tuning?)

**Check storage growth:**

```bash
du -sh /var/felix/storage/*
```

**If growing too fast:**

- Implement retention policy (delete runs older than 90 days)
- Compress old artifacts (gzip text files)
- Archive to cold storage (S3 Glacier)

### Monthly Tasks

**Rotate API keys:**

```bash
# Generate new keys
python scripts/generate-sync-key.py > new_keys.txt

# Distribute to teams
# Revoke old keys after grace period
python scripts/revoke-sync-key.py --key fsk_old_key_here
```

**Run database maintenance:**

```sql
-- Vacuum to reclaim space
VACUUM ANALYZE runs;
VACUUM ANALYZE run_events;
VACUUM ANALYZE run_files;

-- Reindex for performance
REINDEX TABLE runs;
REINDEX TABLE run_events;
```

**Review and delete old test data:**

```sql
-- Find test runs
SELECT id, requirement_id, started_at
FROM runs
WHERE requirement_id LIKE 'S-0000%'  -- Test requirement
ORDER BY started_at DESC;

-- Delete after verification
DELETE FROM runs WHERE requirement_id = 'S-0000';
```

## Scaling Considerations

### When to Scale Up

**Signs you need more resources:**

- Backend response time > 1 second (p99)
- CPU usage > 80% consistently
- Rate limit hit frequently (429 errors)
- Database query time > 100ms

### Vertical Scaling

**Easy wins:**

```bash
# More connections to database
export DATABASE_MAX_CONNECTIONS=50  # Default: 10

# More worker processes
uvicorn app.backend.main:app --workers 4  # Default: 1

# Larger storage
# Resize /var/felix/storage partition
```

### Horizontal Scaling

**Backend is stateless** - can run multiple instances:

```nginx
# nginx load balancer
upstream felix_backend {
    server 10.0.1.10:8080;
    server 10.0.1.11:8080;
    server 10.0.1.12:8080;
}

server {
    listen 443 ssl;
    server_name felix.yourcompany.com;

    location / {
        proxy_pass http://felix_backend;
    }
}
```

**Database connection pooling:**

```python
# Use PgBouncer
export DATABASE_URL="postgresql://felix@pgbouncer:6432/felix_production"
```

**Shared storage:**

```bash
# NFS mount on all backend servers
mount 10.0.2.100:/felix_storage /var/felix/storage
```

### Database Optimization

**Add indexes for common queries:**

```sql
-- Query: Recent runs by agent
CREATE INDEX idx_runs_agent_started
ON runs(agent_id, started_at DESC);

-- Query: Files by SHA256 (deduplication)
CREATE INDEX idx_run_files_sha256
ON run_files(sha256);

-- Query: Events by run (timeline)
CREATE INDEX idx_run_events_run_ts
ON run_events(run_id, ts);
```

**Partition large tables:**

```sql
-- Partition runs by month
CREATE TABLE runs_2026_02 PARTITION OF runs
FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

CREATE TABLE runs_2026_03 PARTITION OF runs
FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
```

## Security

### Best Practices

**1. Use HTTPS in production:**

```nginx
server {
    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/felix.yourcompany.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/felix.yourcompany.com/privkey.pem;
}
```

**2. Rotate API keys regularly:**

```bash
# Monthly rotation
python scripts/generate-sync-key.py  # New key
python scripts/revoke-sync-key.py --key old_key  # Revoke old
```

**3. Limit API key permissions:**

```sql
-- Read-only API key for dashboards
INSERT INTO api_keys (key_id, key_secret, permissions)
VALUES ('dashboard', 'fsk_read_only', ARRAY['reads:runs', 'reads:agents']);
```

**4. Rate limit aggressively:**

```python
# Per-key rate limits
rate_limits = {
    "fsk_team_dev": 100,      # 100/min
    "fsk_team_qa": 200,       # 200/min
    "fsk_ci_pipeline": 500,   # 500/min
}
```

**5. Audit all API key usage:**

```sql
-- Review API key usage
SELECT
    key_id,
    COUNT(*) as request_count,
    MAX(last_used_at) as last_used
FROM api_key_usage
WHERE last_used_at > NOW() - INTERVAL '7 days'
GROUP BY key_id
ORDER BY request_count DESC;
```

## Disaster Recovery

### Backup Strategy

**Database backups:**

```bash
# Daily full backup
pg_dump felix_production > /backup/felix_$(date +%Y%m%d).sql

# Continuous WAL archiving
archive_command = 'cp %p /backup/wal/%f'
```

**Storage backups:**

```bash
# Weekly sync to S3
aws s3 sync /var/felix/storage s3://felix-backup/storage/
```

### Recovery Procedures

**Scenario 1: Backend crashed, database intact**

```bash
# Restart backend
systemctl restart felix-backend

# Agents will retry queued uploads automatically
# Check outbox directories if concerned
```

**Scenario 2: Database corrupted**

```bash
# Restore from backup
dropdb felix_production
createdb felix_production
psql felix_production < /backup/felix_20260217.sql

# Restart backend
systemctl restart felix-backend

# Re-sync from CLI agents
# Run this on all agent machines:
felix run S-0000 --resync  # Uploads local runs/ directory
```

**Scenario 3: Storage lost**

```bash
# Restore from S3
aws s3 sync s3://felix-backup/storage/ /var/felix/storage/

# Verify files
find /var/felix/storage -type f | wc -l

# Restart backend
systemctl restart felix-backend
```

## Troubleshooting Production Issues

### Issue: Uploads suddenly stopped working

**Check:**

1. **Backend health:**

   ```bash
   curl http://localhost:8080/health
   ```

2. **Database connectivity:**

   ```bash
   psql -U felix -d felix_production -c "SELECT 1"
   ```

3. **Storage writeable:**

   ```bash
   touch /var/felix/storage/test
   rm /var/felix/storage/test
   ```

4. **API keys valid:**

   ```sql
   SELECT key_id, revoked_at FROM api_keys WHERE key_id = 'your_key';
   ```

5. **Rate limits:**
   ```bash
   curl -H "X-API-Key: your_key" http://localhost:8080/api/runs -v | grep X-RateLimit
   ```

### Issue: Outbox growing on agent machines

**Diagnose:**

```powershell
# Check queue size
ls .felix\outbox\*.jsonl | Measure-Object | Select-Object Count

# Examine queued requests
Get-Content .felix\outbox\*.jsonl | ConvertFrom-Json | Select-Object endpoint, body

# Check sync logs
Get-Content .felix\sync.log -Tail 50
```

**Common causes:**

1. **Backend URL wrong:** Check `FELIX_SYNC_URL`
2. **API key wrong:** Check `FELIX_SYNC_KEY`
3. **Backend down:** Check backend health
4. **Network blocked:** Check firewall/proxy

**Fix:**

```powershell
# Correct the config
$env:FELIX_SYNC_URL = "https://correct-url.com"
$env:FELIX_SYNC_KEY = "correct_key"

# Trigger retry
felix run S-0001  # Any run will flush queue
```

### Issue: Rate limit errors

**Investigate:**

```bash
# Check which agent is hammering
tail -f /var/felix/logs/app.log | grep "429"

# Rate limit stats by API key
grep "429" /var/felix/logs/app.log | awk '{print $5}' | sort | uniq -c | sort -rn
```

**Solutions:**

1. **Increase limit** (if legitimate traffic):

   ```python
   RATE_LIMIT_PER_MINUTE = 200  # Was 100
   ```

2. **Investigate runaway agent:**

   ```bash
   # Find agent with > 200 req/min
   # Check if stuck in loop
   # Review agent logs
   ```

3. **Implement per-key limits:**
   ```python
   # CI gets higher limit than dev machines
   rate_limits["fsk_ci"] = 500
   rate_limits["fsk_dev"] = 100
   ```

## Cost Optimization

### Storage Costs

**Compress old artifacts:**

```bash
# Compress runs older than 30 days
find /var/felix/storage -type f -mtime +30 -name "*.md" -exec gzip {} \;
find /var/felix/storage -type f -mtime +30 -name "*.log" -exec gzip {} \;
```

**Archive to cold storage:**

```bash
# Move runs older than 90 days to S3 Glacier
aws s3 sync /var/felix/storage/ s3://felix-archive/ \
    --storage-class GLACIER \
    --exclude "*" \
    --include "*/runs/*/2025-*"
```

### Database Costs

**Delete old events:**

```sql
-- Keep detailed events for 90 days, summary after that
DELETE FROM run_events
WHERE ts < NOW() - INTERVAL '90 days'
AND type NOT IN ('run_started', 'run_completed');
```

## The Operations Checklist

**Daily:**

- [ ] Check backend health
- [ ] Review error logs
- [ ] Monitor storage usage

**Weekly:**

- [ ] Review stuck uploads
- [ ] Check rate limit patterns
- [ ] Verify backups ran

**Monthly:**

- [ ] Rotate API keys
- [ ] Database maintenance (VACUUM)
- [ ] Clean up old test data
- [ ] Review and archive old runs

**Quarterly:**

- [ ] Review scaling needs
- [ ] Audit security practices
- [ ] Test disaster recovery
- [ ] Update documentation

---

## Conclusion: You've Learned Distributed Systems

If you've read this entire tutorial series, you now understand:

✅ **Why** the outbox pattern is superior to webhooks/message queues  
✅ **How** to build resilient distributed systems that work offline  
✅ **What** bugs to expect when crossing language/type boundaries  
✅ **When** to scale up vs when simple solutions suffice  
✅ **How** to test distributed systems end-to-end  
✅ **How** to run this in production confidently

These lessons apply to **any distributed system:**

- Mobile app syncing to cloud
- Microservices communicating
- Data pipelines moving data
- IoT devices reporting telemetry

**The patterns are universal. The bugs are predictable. The solutions are proven.**

You now have the knowledge that comes from building, debugging, and operating a real distributed system.

**Go build something resilient.**

---

[Back to README](README.md) | [View on GitHub](https://github.com/yourorg/felix)
