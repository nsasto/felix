# DB Migration Plan

## Phase 0: Inventory + Decisions
- Confirm target data model:
  - `requirements` uses UUID `id` + human-readable `code` (S-XXXX).
  - Dependencies in `requirement_dependencies`.
  - Spec content in `requirement_content` + `requirement_versions`.
  - Tags + `commit_on_complete` in `requirements.metadata`.
- Confirm source of truth for backfill: `.felix/requirements.json`.

## Phase 1: Schema Migrations (order)
1) `002_enable_pgcrypto_and_status_checks.sql`
   - Enable `pgcrypto`.
   - Align `requirements.status` constraint with app statuses.
   - Expand `agents.status` constraint to cover UI + backend values.
2) `003_updated_at_triggers.sql`
   - Add `updated_at` triggers for tables with `updated_at`.
3) `004_requirement_dependencies.sql`
   - Add join table for dependency mapping.
4) `005_requirement_content_versions.sql`
   - Add current snapshot + version history tables.
5) `006_add_requirement_code.sql`
   - Add `requirements.code` + unique `(project_id, code)`.

## Phase 2: Data Migration / Backfill
- Use `scripts/migrate-requirements.ps1`:
  - Reads `.felix/requirements.json`.
  - Strips `S-XXXX:` from titles.
  - Inserts `requirements` with `code`.
  - Inserts `requirement_versions` + `requirement_content`.
  - Inserts `requirement_dependencies`.
  - Supports `-DryRun`.

Suggested run order:
1) `.\scripts\setup-db.ps1 -Force -Seed`
2) `.\scripts\migrate-requirements.ps1 -ProjectId <uuid> -DryRun`
3) `.\scripts\migrate-requirements.ps1 -ProjectId <uuid>`

## Phase 3: Backend Updates
- Add repository interfaces:
  - `IRequirementRepository`, `IProjectRepository`, `IAgentRepository`, `IRunRepository`.
- Implement Postgres repos:
  - Move SQL out of routers into repos.
- Add service layer:
  - `RequirementService` to orchestrate metadata + content + version + dependencies.
- API contract updates:
  - Responses include `code`.
  - Dependency responses remain `depends_on` array (derived from join table).
- Tests:
  - Repo unit tests (mock DB).
  - Service tests (dependency diff + versioning).

## Phase 4: Frontend Updates
- Use `code` for display and selection (still keep UUID internally).
- Dependency UI:
  - Continue to use `depends_on` array from API.
- Metadata sync:
  - Tags + `commit_on_complete` read from metadata.
- Spec content:
  - Prefer `requirement_content` once backend is live.
  - Keep file-based fallback during transition (feature flag if needed).

## Phase 5: Cutover + Validation
- Validate counts:
  - requirements in DB == requirements.json count.
  - each requirement has content + version.
- Validate dependencies:
  - no self-links, no missing dependency codes.
- Validate status values:
  - DB constraints match UI statuses.
- Keep `.felix/requirements.json` as fallback until stable.

## Rollback Plan
- If issues, drop new tables and revert to file-based:
  - `requirement_content`, `requirement_versions`, `requirement_dependencies`.
- Retain `requirements.json` as source of truth until fully verified.
