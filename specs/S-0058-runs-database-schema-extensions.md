# S-0058: Run Artifact Sync - Database Schema Extensions

**Priority:** High  
**Tags:** Database, Schema, Migration

## Description

As a Felix developer, I need to extend the database schema to support run artifact mirroring so that the system can track run lifecycle events, file storage, and agent registration metadata with full backward compatibility.

## Dependencies

- S-0057 (Run Artifact Sync Preparation) - requires migration scaffold and feature branch
- S-0035 (Database Schema and Migrations Setup) - requires migration infrastructure

## Acceptance Criteria

### Runs Table Extensions

- [ ] `runs` table has `org_id` column (UUID, references organizations)
- [ ] `runs` table has `phase` column (TEXT, nullable)
- [ ] `runs` table has `scenario` column (TEXT, nullable)
- [ ] `runs` table has `branch` column (TEXT, nullable for git branch)
- [ ] `runs` table has `commit_sha` column (TEXT, nullable for git commit)
- [ ] `runs` table has `error_summary` column (TEXT, nullable)
- [ ] `runs` table has `summary_json` column (JSONB, defaults to empty object)
- [ ] `runs` table has `duration_sec` column (INTEGER, nullable)
- [ ] `runs` table has `exit_code` column (INTEGER, nullable)
- [ ] `runs` table has `finished_at` column (TIMESTAMPTZ, nullable)

### Runs Table Indexes

- [ ] Index on (org_id, project_id, created_at DESC) exists
- [ ] Index on (project_id, requirement_id, created_at DESC) exists
- [ ] Index on (agent_id, created_at DESC) exists
- [ ] Index on (status, created_at DESC) exists

### Runs Status Enum Extension

- [ ] Status constraint allows 'succeeded' value
- [ ] Status constraint allows 'stopped' value
- [ ] Status constraint allows 'queued' value
- [ ] Status constraint allows 'rejected' value
- [ ] Status constraint allows 'blocked' value
- [ ] Existing status values preserved (pending, running, completed, failed, cancelled)

### Agents Table Extensions

- [ ] `agents` table has `hostname` column (TEXT, nullable)
- [ ] `agents` table has `platform` column (TEXT, nullable for OS platform)
- [ ] `agents` table has `version` column (TEXT, nullable for Felix CLI version)
- [ ] `agents` table has `profile_id` column (UUID, nullable)
- [ ] `agents` table has `last_seen_at` column (TIMESTAMPTZ, defaults to NOW())
- [ ] `agents.project_id` column is nullable (agents register before project assignment)

### Run Events Table

- [ ] `run_events` table created with id (BIGSERIAL PRIMARY KEY)
- [ ] `run_events` has run_id (UUID, references runs with CASCADE delete)
- [ ] `run_events` has ts (TIMESTAMPTZ, defaults to NOW())
- [ ] `run_events` has level (TEXT, CHECK constraint for info/warn/error/debug)
- [ ] `run_events` has type (TEXT, CHECK constraint for valid event types)
- [ ] `run_events` has message (TEXT, nullable)
- [ ] `run_events` has payload (JSONB, nullable)
- [ ] Index on (run_id, ts DESC) exists
- [ ] Index on (type, ts DESC) exists
- [ ] Index on (level, ts DESC) for error/warn exists

### Run Files Table

- [ ] `run_files` table created with id (BIGSERIAL PRIMARY KEY)
- [ ] `run_files` has run_id (UUID, references runs with CASCADE delete)
- [ ] `run_files` has path (TEXT, relative path in run folder)
- [ ] `run_files` has kind (TEXT, CHECK for artifact/log)
- [ ] `run_files` has storage_key (TEXT, full storage path)
- [ ] `run_files` has size_bytes (BIGINT)
- [ ] `run_files` has sha256 (TEXT, nullable)
- [ ] `run_files` has content_type (TEXT, defaults to application/octet-stream)
- [ ] `run_files` has created_at (TIMESTAMPTZ, defaults to NOW())
- [ ] `run_files` has updated_at (TIMESTAMPTZ, defaults to NOW())
- [ ] UNIQUE constraint on (run_id, path)
- [ ] Index on run_id exists
- [ ] Index on (run_id, kind) exists
- [ ] Index on sha256 exists (WHERE sha256 IS NOT NULL)

### Data Integrity

- [ ] All existing data preserved after migration
- [ ] Record counts unchanged (SELECT COUNT(\*) FROM runs matches pre-migration)
- [ ] Foreign key constraints maintained
- [ ] No NULL constraint violations on existing data

## Validation Criteria

- [ ] `psql -U postgres -d felix -f app/backend/migrations/014_run_artifact_mirroring.sql` completes successfully (exit code 0)
- [ ] `psql -U postgres -d felix -c "\d runs"` shows new columns (phase, scenario, branch, duration_sec, exit_code)
- [ ] `psql -U postgres -d felix -c "\d agents"` shows new columns (hostname, platform, version, last_seen_at)
- [ ] `psql -U postgres -d felix -c "\d+ run_events"` shows table exists with all columns
- [ ] `psql -U postgres -d felix -c "\d+ run_files"` shows table exists with UNIQUE constraint on (run_id, path)
- [ ] `psql -U postgres -d felix -c "SELECT COUNT(*) FROM runs"` returns same count as baseline

## Technical Notes

**Architecture:** All new columns are nullable to maintain backward compatibility. Existing code continues to work without modification. New sync features will populate these columns when enabled.

**Migration Strategy:** Use `ALTER TABLE ADD COLUMN IF NOT EXISTS` for idempotency. Migration can be run multiple times safely. Create indexes CONCURRENTLY in production to avoid table locks.

**Don't assume not implemented:** Check if any columns already exist before adding. The backend may have partial schema extensions from earlier experiments.

## Non-Goals

- Populating new columns with data (handled by sync plugin in Phase 4)
- Backend code changes to use new columns (Phase 3)
- Storage abstraction implementation (Phase 2)
- Frontend display of new fields (Phase 6)
