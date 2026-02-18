-- Felix Database Migration 019
-- Remove path column (meaningless for remote) and make git_url mandatory
-- Rename git_repo → git_url for consistency with RunCreate model

-- Step 1: Rename git_repo to git_url
ALTER TABLE projects
    RENAME COLUMN git_repo TO git_url;

-- Step 2: Make git_url NOT NULL
-- First, set a default for any NULL values (shouldn't exist in real use)
UPDATE projects
SET git_url = 'https://github.com/placeholder/placeholder'
WHERE git_url IS NULL;

ALTER TABLE projects
    ALTER COLUMN git_url SET NOT NULL;

-- Step 3: Drop path column and its index
DROP INDEX IF EXISTS idx_projects_org_id_path;
ALTER TABLE projects
    DROP COLUMN IF EXISTS path;

-- Step 4: Update git_url index (was idx_projects_git_repo)
DROP INDEX IF EXISTS idx_projects_git_repo;
CREATE INDEX IF NOT EXISTS idx_projects_git_url
    ON projects(git_url);

-- ============================================================================
-- ROLLBACK:
-- ============================================================================
-- DROP INDEX IF EXISTS idx_projects_git_url;
-- ALTER TABLE projects ADD COLUMN IF NOT EXISTS path TEXT;
-- CREATE UNIQUE INDEX IF NOT EXISTS idx_projects_org_id_path
--     ON projects(org_id, path) WHERE path IS NOT NULL;
-- ALTER TABLE projects ALTER COLUMN git_url DROP NOT NULL;
-- ALTER TABLE projects RENAME COLUMN git_url TO git_repo;
-- CREATE INDEX IF NOT EXISTS idx_projects_git_repo
--     ON projects(git_repo) WHERE git_repo IS NOT NULL;
