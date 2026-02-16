-- Felix Database Migration 015
-- Run Artifact Mirroring - Database Schema Extensions
-- 
-- Extends the database schema for run artifact mirroring (S-0058).
-- Adds new columns to runs and agents tables, creates run_events and run_files tables.
--
-- Related specs:
-- - S-0057: Run Artifact Sync - Preparation and Foundation
-- - S-0058: Run Artifact Sync - Database Schema Extensions (this migration)
-- - S-0059: Run Artifact Sync - Local Write Module
-- - S-0060: Run Artifact Sync - Sync Client Plugin
--
-- IDEMPOTENCY: This migration uses ADD COLUMN IF NOT EXISTS and CREATE TABLE IF NOT EXISTS
-- so it can be run multiple times safely.

-- ============================================================================
-- RUNS TABLE EXTENSIONS
-- ============================================================================

-- Add created_at if missing (needed for indexes)
ALTER TABLE runs ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

-- Add org_id reference (nullable for backward compatibility)
ALTER TABLE runs ADD COLUMN IF NOT EXISTS org_id UUID REFERENCES organizations(id) ON DELETE SET NULL;

-- Add run metadata columns
ALTER TABLE runs ADD COLUMN IF NOT EXISTS phase TEXT;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS scenario TEXT;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS branch TEXT;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS commit_sha TEXT;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS error_summary TEXT;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS summary_json JSONB DEFAULT '{}'::jsonb;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS duration_sec INTEGER;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS exit_code INTEGER;
ALTER TABLE runs ADD COLUMN IF NOT EXISTS finished_at TIMESTAMPTZ;

-- ============================================================================
-- RUNS STATUS ENUM EXTENSION
-- ============================================================================
-- Drop existing constraint and recreate with extended values
-- Preserves: pending, running, completed, failed, cancelled
-- Adds: succeeded, stopped, queued, rejected, blocked

ALTER TABLE runs DROP CONSTRAINT IF EXISTS runs_status_check;
ALTER TABLE runs ADD CONSTRAINT runs_status_check CHECK (
    status IN (
        'pending', 'running', 'completed', 'failed', 'cancelled',
        'succeeded', 'stopped', 'queued', 'rejected', 'blocked'
    )
);

-- ============================================================================
-- RUNS TABLE INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_runs_org_project_created 
    ON runs(org_id, project_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_runs_project_requirement_created 
    ON runs(project_id, requirement_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_runs_agent_created 
    ON runs(agent_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_runs_status_created 
    ON runs(status, created_at DESC);

-- ============================================================================
-- AGENTS TABLE EXTENSIONS
-- ============================================================================

-- Add agent metadata columns
ALTER TABLE agents ADD COLUMN IF NOT EXISTS hostname TEXT;
ALTER TABLE agents ADD COLUMN IF NOT EXISTS platform TEXT;
ALTER TABLE agents ADD COLUMN IF NOT EXISTS version TEXT;
ALTER TABLE agents ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ DEFAULT NOW();

-- Make project_id nullable (agents can register before project assignment)
-- This requires dropping and recreating the constraint
ALTER TABLE agents ALTER COLUMN project_id DROP NOT NULL;

-- Note: profile_id already exists from migration 008_agent_profiles_and_machines.sql

-- ============================================================================
-- RUN EVENTS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS run_events (
    id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    level TEXT NOT NULL CHECK (level IN ('info', 'warn', 'error', 'debug')),
    type TEXT NOT NULL CHECK (type IN (
        'started', 'plan_loaded', 'task_started', 'task_completed',
        'validation_started', 'validation_passed', 'validation_failed',
        'completed', 'failed', 'cancelled', 'heartbeat'
    )),
    message TEXT,
    payload JSONB
);

-- Run events indexes
CREATE INDEX IF NOT EXISTS idx_run_events_run_ts 
    ON run_events(run_id, ts DESC);

CREATE INDEX IF NOT EXISTS idx_run_events_type_ts 
    ON run_events(type, ts DESC);

-- Partial index for error/warn levels (high-priority filtering)
CREATE INDEX IF NOT EXISTS idx_run_events_level_ts 
    ON run_events(level, ts DESC) 
    WHERE level IN ('error', 'warn');

-- ============================================================================
-- RUN FILES TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS run_files (
    id BIGSERIAL PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    path TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('artifact', 'log')),
    storage_key TEXT NOT NULL,
    size_bytes BIGINT NOT NULL,
    sha256 TEXT,
    content_type TEXT NOT NULL DEFAULT 'application/octet-stream',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(run_id, path)
);

-- Run files indexes
CREATE INDEX IF NOT EXISTS idx_run_files_run_id 
    ON run_files(run_id);

CREATE INDEX IF NOT EXISTS idx_run_files_run_kind 
    ON run_files(run_id, kind);

-- Partial index for sha256 lookups (deduplication)
CREATE INDEX IF NOT EXISTS idx_run_files_sha256 
    ON run_files(sha256) 
    WHERE sha256 IS NOT NULL;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- updated_at trigger for run_files (reuses existing set_updated_at function from migration 003)
DROP TRIGGER IF EXISTS set_updated_at_run_files ON run_files;
CREATE TRIGGER set_updated_at_run_files
BEFORE UPDATE ON run_files
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- COMPLETION
-- ============================================================================

SELECT 'Migration 015: Run artifact mirroring schema extensions applied' AS status;

-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- To rollback this migration, run the following commands in order:
--
-- -- Drop triggers
-- DROP TRIGGER IF EXISTS set_updated_at_run_files ON run_files;
--
-- -- Drop new tables
-- DROP TABLE IF EXISTS run_files CASCADE;
-- DROP TABLE IF EXISTS run_events CASCADE;
--
-- -- Drop new indexes on runs
-- DROP INDEX IF EXISTS idx_runs_org_project_created;
-- DROP INDEX IF EXISTS idx_runs_project_requirement_created;
-- DROP INDEX IF EXISTS idx_runs_agent_created;
-- DROP INDEX IF EXISTS idx_runs_status_created;
--
-- -- Restore original runs status constraint
-- ALTER TABLE runs DROP CONSTRAINT IF EXISTS runs_status_check;
-- ALTER TABLE runs ADD CONSTRAINT runs_status_check CHECK (
--     status IN ('pending', 'running', 'completed', 'failed', 'cancelled')
-- );
--
-- -- Drop new columns from runs (in reverse order)
-- ALTER TABLE runs DROP COLUMN IF EXISTS finished_at;
-- ALTER TABLE runs DROP COLUMN IF EXISTS exit_code;
-- ALTER TABLE runs DROP COLUMN IF EXISTS duration_sec;
-- ALTER TABLE runs DROP COLUMN IF EXISTS summary_json;
-- ALTER TABLE runs DROP COLUMN IF EXISTS error_summary;
-- ALTER TABLE runs DROP COLUMN IF EXISTS commit_sha;
-- ALTER TABLE runs DROP COLUMN IF EXISTS branch;
-- ALTER TABLE runs DROP COLUMN IF EXISTS scenario;
-- ALTER TABLE runs DROP COLUMN IF EXISTS phase;
-- ALTER TABLE runs DROP COLUMN IF EXISTS org_id;
-- ALTER TABLE runs DROP COLUMN IF EXISTS created_at;
--
-- -- Drop new columns from agents
-- ALTER TABLE agents DROP COLUMN IF EXISTS last_seen_at;
-- ALTER TABLE agents DROP COLUMN IF EXISTS version;
-- ALTER TABLE agents DROP COLUMN IF EXISTS platform;
-- ALTER TABLE agents DROP COLUMN IF EXISTS hostname;
--
-- -- Restore project_id NOT NULL on agents (only if all rows have project_id)
-- -- ALTER TABLE agents ALTER COLUMN project_id SET NOT NULL;
