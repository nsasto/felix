# S-0043: Supabase Project Setup and Schema Migration

**Phase:** 2 (Supabase Migration)  
**Effort:** 4-6 hours  
**Priority:** Critical  
**Dependencies:** S-0042

---

## Narrative

This specification covers creating a Supabase project, applying the existing database schema to Supabase, and updating the backend to connect to Supabase instead of local PostgreSQL. The schema is identical (created in S-0035), so this is a mechanical migration, not an architectural change.

---

## Acceptance Criteria

### Supabase Project Creation

- [ ] Create Supabase project at https://supabase.com (name: `felix-production`)
- [ ] Note project URL, anon key, and service key
- [ ] Verify project is running and accessible

### Schema Migration

- [ ] Apply **app/backend/migrations/001_initial_schema.sql** to Supabase database
- [ ] Verify all 8 tables exist in Supabase
- [ ] Verify indexes exist
- [ ] Verify foreign key constraints exist

### Environment Configuration

- [ ] Update **app/backend/.env** with:
  - `SUPABASE_URL=https://<project-id>.supabase.co`
  - `SUPABASE_ANON_KEY=<anon-key>`
  - `SUPABASE_SERVICE_KEY=<service-key>`
  - `DATABASE_URL=postgresql://postgres:<password>@db.<project-id>.supabase.co:5432/postgres`
  - Keep `AUTH_MODE=disabled` (Phase 2 will change this)

### Test Migration

- [ ] Update backend to connect to Supabase
- [ ] Verify all Phase 1 functionality still works:
  - Agent registration
  - Run creation
  - Console streaming
  - Frontend dashboard

### Seed Development Data

- [ ] Run **app/backend/migrations/001_seed_dev_data.sql** on Supabase
- [ ] Verify dev org, project, and membership exist

---

## Technical Notes

### Supabase Project Settings

- **Project Name:** felix-production
- **Database Password:** (Generate strong password, store securely)
- **Region:** Choose closest to your location
- **Pricing Plan:** Free tier (upgrade for production)

### Apply Schema to Supabase

**Option 1: Using Supabase SQL Editor**

1. Go to Supabase dashboard → SQL Editor
2. Paste contents of `001_initial_schema.sql`
3. Click "Run"
4. Verify tables exist in Table Editor

**Option 2: Using psql**

```bash
psql "postgresql://postgres:<password>@db.<project-id>.supabase.co:5432/postgres" \
  -f app/backend/migrations/001_initial_schema.sql
```

### Update .env File

```bash
# Supabase
SUPABASE_URL=https://xxxxxxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
SUPABASE_SERVICE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

# Database (Supabase PostgreSQL)
DATABASE_URL=postgresql://postgres:your-password@db.xxxxxxxx.supabase.co:5432/postgres

# Authentication (still disabled in Phase 2)
AUTH_MODE=disabled

# Development Identity
DEV_ORG_ID=00000000-0000-0000-0000-000000000001
DEV_PROJECT_ID=00000000-0000-0000-0000-000000000001
DEV_USER_ID=dev-user
```

### Verify Connection

```python
# Test script
import asyncio
from databases import Database

async def test():
    db = Database("postgresql://postgres:password@db.xxxxxxxx.supabase.co:5432/postgres")
    await db.connect()
    result = await db.fetch_one("SELECT COUNT(*) FROM organizations")
    print(f"Organizations: {result['count']}")
    await db.disconnect()

asyncio.run(test())
```

---

## Dependencies

**Depends On:**

- S-0042: Frontend API Client and Dashboard (Phase 1 complete)

**Blocks:**

- S-0044: Row-Level Security (RLS) Policies

---

## Validation Criteria

### Supabase Project Verification

- [ ] Project accessible at `https://<project-id>.supabase.co`
- [ ] Dashboard loads without errors
- [ ] Table Editor shows 8 tables

### Schema Verification

- [ ] All tables exist: organizations, projects, agents, agent_states, runs, run_artifacts, requirements, organization_members
- [ ] Table Editor → organizations → shows correct columns
- [ ] Foreign keys exist: projects.org_id → organizations.id, etc.
- [ ] Indexes exist: idx_projects_org_id, idx_agents_project_id, etc.

### Backend Connection Test

- [ ] Update DATABASE_URL in .env
- [ ] Start backend: `cd app/backend && python main.py`
- [ ] Check logs: "✅ Connected to database: postgresql://postgres:\*\*\*@db.xxxxxxxx.supabase.co..."
- [ ] Health endpoint: `curl http://localhost:8080/health` (status 200)

### Phase 1 Functionality Test

- [ ] Register agent: `curl -X POST http://localhost:8080/api/agents/register ...`
- [ ] Connect agent to control WebSocket
- [ ] Create run via API
- [ ] Verify run in Supabase Table Editor
- [ ] Open frontend dashboard → verify agents and runs display
- [ ] Console streaming still works

### Seed Data Verification

- [ ] Count organizations: Supabase SQL Editor → `SELECT COUNT(*) FROM organizations;` (should be 1)
- [ ] Dev org exists: `SELECT * FROM organizations WHERE slug = 'dev-org';`
- [ ] Dev project exists: `SELECT * FROM projects WHERE slug = 'felix';`

---

## Rollback Strategy

If issues arise:

1. Change DATABASE_URL back to local PostgreSQL
2. Restart backend
3. Verify Phase 1 functionality works locally
4. Debug Supabase connection issues
5. Re-apply migration if schema is incorrect

**Data Safety:** Local PostgreSQL database remains intact as backup.

---

## Notes

- Schema is identical to local PostgreSQL (S-0035) - mechanical migration only
- No RLS policies yet (Phase 2, S-0044) - all data accessible
- AUTH_MODE remains disabled until Phase 2 (S-0045) adds JWT integration
- Supabase free tier includes 500MB database, 2GB bandwidth (sufficient for development)
- Supabase dashboard provides SQL Editor, Table Editor, and real-time monitoring
- Database password should be strong (32+ characters, alphanumeric + symbols)
- Service key has admin privileges - never expose in frontend
- Anon key is safe for frontend - has limited privileges (will be restricted by RLS in S-0044)
- This is the transition point: local development → cloud-backed development
