-- Felix Database Migration 013
-- Add git_repo column to projects table for tracking remote repository URLs

ALTER TABLE projects
    ADD COLUMN IF NOT EXISTS git_repo TEXT;

-- Index for searching by git repo
CREATE INDEX IF NOT EXISTS idx_projects_git_repo
    ON projects(git_repo)
    WHERE git_repo IS NOT NULL;

-- ROLLBACK:
-- DROP INDEX IF EXISTS idx_projects_git_repo;
-- ALTER TABLE projects DROP COLUMN IF EXISTS git_repo;
