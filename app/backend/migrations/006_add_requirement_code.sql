-- Felix Database Migration 006
-- Adds human-readable requirement code (e.g. S-0031).

ALTER TABLE requirements
  ADD COLUMN IF NOT EXISTS code TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_requirements_project_code
  ON requirements(project_id, code)
  WHERE code IS NOT NULL;

-- Optional format check (commented out until data is fully migrated):
-- ALTER TABLE requirements
--   ADD CONSTRAINT requirements_code_format_check
--   CHECK (code ~ '^S-\d{4}$');
