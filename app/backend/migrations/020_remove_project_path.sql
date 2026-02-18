-- Felix Database Migration 020
-- Remove path column from projects table
-- Path is derived at runtime for dev mode, not stored in DB

-- Drop unique index first
DROP INDEX IF EXISTS idx_projects_org_id_path;

-- Drop path column
ALTER TABLE projects
    DROP COLUMN IF EXISTS path;
