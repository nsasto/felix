-- ===================================================================
-- Migration 017: Project-Scoped API Keys
-- ===================================================================
-- Breaking change: Existing API keys are deleted (pre-production status).
-- All keys must now be scoped to a project (project_id NOT NULL).
-- Removes agent_id FK (deprecated in favor of project scoping).

-- Drop existing keys (pre-production, safe to delete)
TRUNCATE api_keys CASCADE;

-- Add project_id as NOT NULL with FK constraint
ALTER TABLE api_keys 
  ADD COLUMN project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE;

-- Create index for project_id lookups (used on every auth)
CREATE INDEX idx_api_keys_project_id ON api_keys(project_id);

-- Drop agent_id constraint (deprecated - use project_id)
ALTER TABLE api_keys DROP CONSTRAINT IF EXISTS api_keys_agent_id_fkey;
ALTER TABLE api_keys DROP COLUMN IF EXISTS agent_id;

-- Create composite unique constraint (one key per project+name)
CREATE UNIQUE INDEX idx_api_keys_project_name ON api_keys(project_id, name) 
  WHERE name IS NOT NULL;

-- Add comment
COMMENT ON COLUMN api_keys.project_id IS 'Project this key grants access to (NOT NULL - all keys are project-scoped)';
