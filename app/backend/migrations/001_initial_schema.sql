-- Felix Database Schema Migration 001
-- Creates the initial 9-table schema for Felix Phase 0
-- Tables: schema_migrations, organizations, organization_members, projects, requirements, agents, agent_states, runs, run_artifacts

-- ============================================================================
-- TABLE 0: schema_migrations (Migration Tracking)
-- ============================================================================
CREATE TABLE IF NOT EXISTS schema_migrations (
    id SERIAL PRIMARY KEY,
    version TEXT NOT NULL UNIQUE,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- TABLE 1: organizations
-- ============================================================================
CREATE TABLE IF NOT EXISTS organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE,
    owner_id TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- TABLE 2: organization_members
-- Depends on: organizations
-- ============================================================================
CREATE TABLE IF NOT EXISTS organization_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'member',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (role IN ('owner', 'admin', 'member')),
    UNIQUE(org_id, user_id)
);

-- ============================================================================
-- TABLE 3: projects
-- Depends on: organizations
-- ============================================================================
CREATE TABLE IF NOT EXISTS projects (
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

-- ============================================================================
-- TABLE 4: requirements
-- Depends on: projects
-- ============================================================================
CREATE TABLE IF NOT EXISTS requirements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    spec_path TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'planned',
    priority TEXT NOT NULL DEFAULT 'medium',
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (status IN ('planned', 'in-progress', 'completed', 'blocked')),
    CHECK (priority IN ('critical', 'high', 'medium', 'low'))
);

-- ============================================================================
-- TABLE 5: agents
-- Depends on: projects
-- ============================================================================
CREATE TABLE IF NOT EXISTS agents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'idle',
    heartbeat_at TIMESTAMPTZ,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (status IN ('idle', 'running', 'stopped', 'error'))
);

-- ============================================================================
-- TABLE 6: agent_states
-- Depends on: agents
-- ============================================================================
CREATE TABLE IF NOT EXISTS agent_states (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id UUID NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    state_key TEXT NOT NULL,
    state_value JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(agent_id, state_key)
);

-- ============================================================================
-- TABLE 7: runs
-- Depends on: projects, agents, requirements
-- ============================================================================
CREATE TABLE IF NOT EXISTS runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    agent_id UUID NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    requirement_id UUID REFERENCES requirements(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    error TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled'))
);

-- ============================================================================
-- TABLE 8: run_artifacts
-- Depends on: runs
-- ============================================================================
CREATE TABLE IF NOT EXISTS run_artifacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    artifact_type TEXT NOT NULL,
    file_path TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Projects indexes
CREATE INDEX IF NOT EXISTS idx_projects_org_id ON projects(org_id);

-- Agents indexes
CREATE INDEX IF NOT EXISTS idx_agents_project_id ON agents(project_id);
CREATE INDEX IF NOT EXISTS idx_agents_status ON agents(status);

-- Runs indexes
CREATE INDEX IF NOT EXISTS idx_runs_project_id ON runs(project_id);
CREATE INDEX IF NOT EXISTS idx_runs_agent_id ON runs(agent_id);
CREATE INDEX IF NOT EXISTS idx_runs_status ON runs(status);

-- Run artifacts indexes
CREATE INDEX IF NOT EXISTS idx_run_artifacts_run_id ON run_artifacts(run_id);

-- Requirements indexes
CREATE INDEX IF NOT EXISTS idx_requirements_project_id ON requirements(project_id);

-- Organization members indexes
CREATE INDEX IF NOT EXISTS idx_organization_members_org_id ON organization_members(org_id);
CREATE INDEX IF NOT EXISTS idx_organization_members_user_id ON organization_members(user_id);

-- ============================================================================
-- ROLLBACK
-- To rollback this migration, run the following commands in reverse order:
-- ============================================================================
-- DROP TABLE IF EXISTS run_artifacts CASCADE;
-- DROP TABLE IF EXISTS runs CASCADE;
-- DROP TABLE IF EXISTS agent_states CASCADE;
-- DROP TABLE IF EXISTS agents CASCADE;
-- DROP TABLE IF EXISTS requirements CASCADE;
-- DROP TABLE IF EXISTS projects CASCADE;
-- DROP TABLE IF EXISTS organization_members CASCADE;
-- DROP TABLE IF EXISTS organizations CASCADE;
