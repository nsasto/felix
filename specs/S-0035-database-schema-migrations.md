# S-0035: Database Schema and Migrations Setup

**Phase:** 0 (Local Postgres Setup)  
**Effort:** 6-8 hours  
**Priority:** Critical  
**Dependencies:** S-0034

---

## Narrative

This specification covers setting up local PostgreSQL database with a complete schema that matches Supabase conventions from day one. This includes creating the `felix` database, setting up a migrations directory, writing the initial schema migration, and seeding a development organization and project.

The schema will include 8 core tables with UUID primary keys, timestamptz timestamps, and JSONB metadata columns - all matching Supabase conventions so Phase 2 migration is mechanical, not architectural.

---

## Acceptance Criteria

### Database Creation

- [ ] Create PostgreSQL database named `felix`
- [ ] Verify PostgreSQL is running: `psql -U postgres -c "SELECT version();"`
- [ ] Create database: `psql -U postgres -c "CREATE DATABASE felix;"`
- [ ] Verify database exists: `psql -U postgres -c "\l"` (should list felix)

### Migrations Directory Setup

- [ ] Create directory: **app/backend/migrations/**
- [ ] Create file: **app/backend/migrations/README.md** with migration instructions
- [ ] Create file: **app/backend/migrations/001_initial_schema.sql**

### Schema Migration (001_initial_schema.sql)

- [ ] Define `organizations` table (id, name, slug, owner_id, metadata, created_at, updated_at)
- [ ] Define `projects` table (id, org_id, name, slug, description, metadata, created_at, updated_at)
- [ ] Define `agents` table (id, project_id, name, type, status, heartbeat_at, metadata, created_at, updated_at)
- [ ] Define `agent_states` table (id, agent_id, state_key, state_value, created_at, updated_at)
- [ ] Define `runs` table (id, project_id, agent_id, requirement_id, status, started_at, completed_at, error, metadata)
- [ ] Define `run_artifacts` table (id, run_id, artifact_type, file_path, metadata, created_at)
- [ ] Define `requirements` table (id, project_id, title, spec_path, status, priority, metadata, created_at, updated_at)
- [ ] Define `organization_members` table (id, org_id, user_id, role, created_at)
- [ ] Add foreign key constraints between tables
- [ ] Add indexes on frequently queried columns (org_id, project_id, agent_id, status)
- [ ] Add CHECK constraints for status enums

### Apply Migration

- [ ] Run migration: `psql -U postgres -d felix -f app/backend/migrations/001_initial_schema.sql`
- [ ] Verify tables exist: `psql -U postgres -d felix -c "\dt"` (should list 8 tables)
- [ ] Verify schema matches expected structure: `psql -U postgres -d felix -c "\d organizations"`

### Seed Development Data

- [ ] Create **app/backend/migrations/001_seed_dev_data.sql**
- [ ] Insert dev organization: `{"id": "00000000-0000-0000-0000-000000000001", "name": "Dev Org", "slug": "dev-org"}`
- [ ] Insert dev project: `{"id": "00000000-0000-0000-0000-000000000001", "name": "Felix", "slug": "felix"}`
- [ ] Insert dev user membership: `{"user_id": "dev-user", "role": "owner"}`
- [ ] Run seed script: `psql -U postgres -d felix -f app/backend/migrations/001_seed_dev_data.sql`

---

## Technical Notes

### Database Connection

**Connection String Format:**

```
postgresql://postgres:password@localhost:5432/felix
```

### Schema Details

**organizations table:**

```sql
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE,
    owner_id TEXT NOT NULL,  -- Will become UUID in Phase 2 (Supabase Auth)
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**projects table:**

```sql
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    slug TEXT NOT NULL,
    description TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(org_id, slug)
);
```

**agents table:**

```sql
CREATE TABLE agents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    type TEXT NOT NULL,  -- 'ralph', 'custom', etc.
    status TEXT NOT NULL DEFAULT 'idle',  -- 'idle', 'running', 'stopped', 'error'
    heartbeat_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (status IN ('idle', 'running', 'stopped', 'error'))
);
```

**agent_states table:**

```sql
CREATE TABLE agent_states (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id UUID NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    state_key TEXT NOT NULL,
    state_value JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(agent_id, state_key)
);
```

**runs table:**

```sql
CREATE TABLE runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    agent_id UUID NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    requirement_id UUID REFERENCES requirements(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'pending',  -- 'pending', 'running', 'completed', 'failed', 'cancelled'
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    error TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled'))
);
```

**run_artifacts table:**

```sql
CREATE TABLE run_artifacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    artifact_type TEXT NOT NULL,  -- 'log', 'output', 'screenshot', 'file'
    file_path TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**requirements table:**

```sql
CREATE TABLE requirements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    spec_path TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'planned',  -- 'planned', 'in-progress', 'completed', 'blocked'
    priority TEXT NOT NULL DEFAULT 'medium',  -- 'critical', 'high', 'medium', 'low'
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (status IN ('planned', 'in-progress', 'completed', 'blocked')),
    CHECK (priority IN ('critical', 'high', 'medium', 'low'))
);
```

**organization_members table:**

```sql
CREATE TABLE organization_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,  -- Will become UUID in Phase 2 (Supabase Auth)
    role TEXT NOT NULL DEFAULT 'member',  -- 'owner', 'admin', 'member'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (role IN ('owner', 'admin', 'member')),
    UNIQUE(org_id, user_id)
);
```

### Indexes

```sql
CREATE INDEX idx_projects_org_id ON projects(org_id);
CREATE INDEX idx_agents_project_id ON agents(project_id);
CREATE INDEX idx_agents_status ON agents(status);
CREATE INDEX idx_runs_project_id ON runs(project_id);
CREATE INDEX idx_runs_agent_id ON runs(agent_id);
CREATE INDEX idx_runs_status ON runs(status);
CREATE INDEX idx_run_artifacts_run_id ON run_artifacts(run_id);
CREATE INDEX idx_requirements_project_id ON requirements(project_id);
CREATE INDEX idx_organization_members_org_id ON organization_members(org_id);
CREATE INDEX idx_organization_members_user_id ON organization_members(user_id);
```

---

## Dependencies

**Depends On:**

- S-0034: Cleanup Verification and Documentation (Phase -1 complete)

**Blocks:**

- S-0036: Backend Database Integration Layer

---

## Validation Criteria

### PostgreSQL Running

- [ ] Check PostgreSQL status: `pg_ctl.exe -D C:\dev\postgres\pgsql\data status`
- [ ] Should output: `server is running`

### Database Exists

- [ ] List databases: `psql -U postgres -c "\l"`
- [ ] Verify `felix` database exists in list

### Tables Created

- [ ] List tables: `psql -U postgres -d felix -c "\dt"`
- [ ] Verify 8 tables exist: organizations, projects, agents, agent_states, runs, run_artifacts, requirements, organization_members

### Schema Verification

- [ ] Check organizations table: `psql -U postgres -d felix -c "\d organizations"`
- [ ] Verify columns: id (uuid), name (text), slug (text), owner_id (text), metadata (jsonb), created_at (timestamptz), updated_at (timestamptz)
- [ ] Check foreign keys: `psql -U postgres -d felix -c "\d projects"` (should show FOREIGN KEY to organizations)

### Seed Data Verification

- [ ] Count organizations: `psql -U postgres -d felix -c "SELECT COUNT(*) FROM organizations;"` (should be 1)
- [ ] Count projects: `psql -U postgres -d felix -c "SELECT COUNT(*) FROM projects;"` (should be 1)
- [ ] Count members: `psql -U postgres -d felix -c "SELECT COUNT(*) FROM organization_members;"` (should be 1)
- [ ] Verify dev org: `psql -U postgres -d felix -c "SELECT name, slug FROM organizations WHERE slug = 'dev-org';"`
- [ ] Verify dev project: `psql -U postgres -d felix -c "SELECT name, slug FROM projects WHERE slug = 'felix';"`

### Indexes Exist

- [ ] List indexes: `psql -U postgres -d felix -c "\di"`
- [ ] Verify indexes exist: idx_projects_org_id, idx_agents_project_id, idx_runs_status, etc.

---

## Rollback Strategy

If issues arise:

1. Drop database: `psql -U postgres -c "DROP DATABASE felix;"`
2. Re-create database: `psql -U postgres -c "CREATE DATABASE felix;"`
3. Re-run migration with fixes

**Backup Before Schema Changes:**

```bash
pg_dump -U postgres felix > backup_felix_$(date +%Y%m%d_%H%M%S).sql
```

---

## Notes

- PostgreSQL must be running on localhost:5432
- Default PostgreSQL user is `postgres` (update connection string if different)
- Password is stored in .pgpass file or PGPASSWORD environment variable
- Migration files are idempotent (can be run multiple times with DROP IF EXISTS)
- Schema is designed for Supabase compatibility from day one
- No RLS policies yet (Phase 2) - in Phase 0, AUTH_MODE=disabled
- Dev org and project use fixed UUIDs for consistency across environments
- Total schema: 8 tables, ~50 columns, 10 indexes, 7 foreign keys
