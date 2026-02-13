# DB Migration Detailed Todo

## Phase 1: Schema Validation + DB Hygiene
- Verify migrations 002–006 applied in `schema_migrations`.
- Confirm tables exist: `requirement_dependencies`, `requirement_content`, `requirement_versions`.
- Validate constraints:
  - `requirements.code` unique per project.
  - `requirements.status` check includes UI statuses.
  - `agents.status` check includes UI + backend statuses.
- Validate content/version integrity:
  - Every requirement has a `requirement_content` row.
  - `requirement_content.current_version_id` points to a valid `requirement_versions` row.
- Validate dependencies:
  - No self-dependencies.
  - No missing dependency codes.
- Validate metadata:
  - `requirements.metadata.tags` exists (empty array ok).
  - `requirements.metadata.commit_on_complete` only where present.

## Phase 2: Backend Data Access Layer
- Add repo interfaces:
  - `IRequirementRepository`
  - `IRequirementContentRepository`
  - `IRequirementDependencyRepository`
- Implement Postgres repos using `databases.Database`.
- Add `RequirementService` to orchestrate:
  - requirement updates
  - content + version writes
  - dependency diff + writes
  - metadata updates
- Update requirements endpoints to use service:
  - list returns `code`, `depends_on`, `tags`, `commit_on_complete`
  - PATCH writes version + content + deps
- Add tests:
  - repo CRUD coverage
  - dependency diff logic
  - version insert + content update

## Phase 3: API Contract + Frontend Integration
- Update frontend models to include `code`.
- Display `code` in UI; keep UUID internal if needed.
- Dependency selector uses `code` values; backend resolves to UUID.
- Spec editor loads from `requirement_content`.
- Spec saves create new `requirement_versions` and update `requirement_content`.

## Phase 4: Deprecate File-Based Requirements
- Replace requirements.json read paths with DB queries.
- Keep `.felix/requirements.json` as fallback until verified, then remove.
- Remove file-based update logic in `routers/requirements.py`.

## Phase 5: Validation + Rollout
- Validate counts and referential integrity.
- Validate dependency mapping vs previous JSON.
- Validate content load and save paths.
- Update docs/runbook for new data flow.
