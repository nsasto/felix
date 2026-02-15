-- Felix Database Migration 009
-- Add path column to projects for DB-backed project registry

ALTER TABLE projects
    ADD COLUMN IF NOT EXISTS path TEXT;

-- Ensure project paths are unique within an org when present.
CREATE UNIQUE INDEX IF NOT EXISTS idx_projects_org_id_path
    ON projects(org_id, path)
    WHERE path IS NOT NULL;
