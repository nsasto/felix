# DB Migration Detailed Todo

## Phase 1: Schema Validation + DB Hygiene
- [x] Verify migrations 002-007 applied in `schema_migrations`.
- [x] Confirm tables exist: `requirement_dependencies`, `requirement_content`, `requirement_versions`.
- [x] Validate constraints:
  - [x] `requirements.code` unique per project.
  - [x] `requirements.status` check includes UI statuses.
  - [x] `agents.status` check includes UI + backend statuses.
- [x] Validate content/version integrity:
  - [x] Every requirement has a `requirement_content` row.
  - [x] `requirement_content.current_version_id` points to a valid `requirement_versions` row.
- [x] Validate dependencies:
  - [x] No self-dependencies.
  - [x] No missing dependency codes.
- [x] Validate metadata:
  - [x] `requirements.metadata.tags` exists (empty array ok).
  - [x] `requirements.metadata.commit_on_complete` only where present.

## Phase 2: Backend Data Access Layer
- [x] Add repo interfaces:
  - `IRequirementRepository`
  - `IRequirementContentRepository`
  - `IRequirementDependencyRepository`
- [x] Implement Postgres repos using `databases.Database`.
- [x] Add `RequirementService` to orchestrate:
  - requirement updates
  - content + version writes
  - dependency diff + writes
  - metadata updates
- [x] Update requirements endpoints to use service:
  - list returns `code`, `depends_on`, `tags`, `commit_on_complete`
  - PATCH writes version + content + deps
- [x] Add tests:
  - repo CRUD coverage
  - dependency diff logic
  - version insert + content update
- [x] Wire spec updates to write content + version history.
- [x] Implement requirement status endpoints.

## Phase 3: API Contract + Frontend Integration
- [x] Update frontend models to include `code`.
- [x] Display `code` in UI; keep UUID internal if needed.
- [x] Dependency selector uses `code` values; backend resolves to UUID.
- [x] Spec editor loads from `requirement_content`.
- [x] Spec saves create new `requirement_versions` and update `requirement_content`.

## Phase 4: Deprecate File-Based Requirements
- [x] Replace requirements.json read paths with DB queries.
- [x] Keep `.felix/requirements.json` as fallback until verified, then remove.
- [x] Remove file-based update logic in `routers/requirements.py`.

## Phase 5: Validation + Rollout
- [x] Validate counts and referential integrity.
- [x] Validate dependency mapping vs previous JSON. (Done: no mismatches)
- [x] Validate content load and save paths. (Done: DB transaction insert/update/rollback check)
- Note: frontend test runs can emit expected stderr logs (simulated error paths, act warnings) even when green.
- [x] Update docs/runbook for new data flow.
