# S-0057: Run Artifact Sync - Preparation and Foundation

**Priority:** High  
**Tags:** Backend, Infrastructure, Sync, Database

## Description

As a Felix developer, I need to set up the foundational infrastructure for run artifact syncing so that we can implement agent-to-server mirroring incrementally with proper feature flags, database migration scaffolding, and baseline documentation.

## Dependencies

- S-0035 (Database Schema and Migrations Setup) - requires migration infrastructure
- S-0002 (Backend API Server) - requires FastAPI server running

## Acceptance Criteria

### Feature Branch Setup

- [ ] Feature branch `feature/run-artifact-sync` exists (or create from feature/db if needed)
- [ ] Branch pushed to remote repository
- [ ] Development workflow documented

### Configuration Schema

- [ ] `.felix/config.json` accepts sync configuration section
- [ ] Sync config includes: enabled, provider, base_url, api_key fields
- [ ] Config validation accepts sync disabled by default
- [ ] Environment variables override config values (FELIX_SYNC_ENABLED, FELIX_SYNC_URL, FELIX_SYNC_KEY)

### Database Migration Scaffold

- [ ] Migration file `app/backend/migrations/014_run_artifact_mirroring.sql` created
- [ ] Migration includes placeholder INSERT for schema_migrations tracking
- [ ] Database setup script accepts migration without errors
- [ ] Migration file properly formatted and commented

### Backend Configuration

- [ ] `app/backend/.env.example` includes STORAGE_TYPE setting
- [ ] `app/backend/.env.example` includes STORAGE_BASE_PATH setting
- [ ] Storage defaults to filesystem type
- [ ] Storage path defaults to storage/runs

### Baseline Documentation

- [ ] Current run counts documented
- [ ] Existing database schema captured (runs, agents, run_artifacts tables)
- [ ] Baseline metrics file created at `Enhancements/RUNS_BASELINE.md`
- [ ] Implementation plan linked in baseline doc

## Validation Criteria

- [ ] `git branch` shows feature/run-artifact-sync exists
- [ ] `cat .felix/config.json` includes sync section
- [ ] `python -c "import json; c=json.load(open('.felix/config.json')); print(c.get('sync', {}).get('enabled', False))"` outputs False
- [ ] `psql -U postgres -d felix -f app/backend/migrations/014_run_artifact_mirroring.sql` completes without errors
- [ ] `cat app/backend/.env.example` contains STORAGE_TYPE and STORAGE_BASE_PATH

## Technical Notes

**Architecture:** This phase establishes the foundation for incremental implementation. The feature flag pattern allows development without affecting production. All subsequent phases depend on this setup.

**Config Strategy:** Use environment variables for per-machine overrides while maintaining repo config as default. This supports different sync URLs for dev/staging/prod without code changes.

**Don't assume not implemented:** Check if .felix/config.json already has a sync section or similar. Merge rather than replace if config structure exists.

## Non-Goals

- Actual sync functionality (covered in later phases)
- Schema changes to database tables (Phase 1)
- Backend endpoints (Phase 3)
- CLI plugin implementation (Phase 4)
