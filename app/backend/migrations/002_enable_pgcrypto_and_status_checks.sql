-- Felix Database Migration 002
-- Enables pgcrypto for gen_random_uuid() and aligns status constraints.

-- ====================================================================
-- EXTENSIONS
-- ====================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ====================================================================
-- REQUIREMENTS STATUS NORMALIZATION + CONSTRAINT
-- ====================================================================
UPDATE requirements SET status = 'in_progress' WHERE status = 'in-progress';
UPDATE requirements SET status = 'complete' WHERE status = 'completed';

ALTER TABLE requirements
  DROP CONSTRAINT IF EXISTS requirements_status_check;
ALTER TABLE requirements
  ADD CONSTRAINT requirements_status_check
  CHECK (status IN ('draft', 'planned', 'in_progress', 'complete', 'blocked', 'done'));

-- ====================================================================
-- AGENTS STATUS CONSTRAINT
-- ====================================================================
ALTER TABLE agents
  DROP CONSTRAINT IF EXISTS agents_status_check;
ALTER TABLE agents
  ADD CONSTRAINT agents_status_check
  CHECK (status IN (
    'idle', 'running', 'stopped', 'error',
    'active', 'inactive', 'stale', 'not-started'
  ));

-- ====================================================================
-- ROLLBACK
-- ====================================================================
-- No automatic rollback. Restore previous constraints manually if needed.
