-- Felix Database Migration 017
-- Agent Adapter Metadata
-- 
-- Adds LLM adapter metadata to agents table to track which LLM
-- adapter/executable/model was used for each agent execution.
--
-- Related: Run artifact sync (S-0057 through S-0064)

-- ============================================================================
-- AGENTS TABLE EXTENSIONS
-- ============================================================================

-- Add LLM adapter metadata columns
ALTER TABLE agents ADD COLUMN IF NOT EXISTS adapter TEXT;
ALTER TABLE agents ADD COLUMN IF NOT EXISTS executable TEXT;
ALTER TABLE agents ADD COLUMN IF NOT EXISTS model TEXT;

-- Add comments for clarity
COMMENT ON COLUMN agents.adapter IS 'LLM adapter type (droid, claude, codex, gemini)';
COMMENT ON COLUMN agents.executable IS 'Executable command used to invoke the adapter';
COMMENT ON COLUMN agents.model IS 'LLM model name used by the adapter';

-- ============================================================================
-- VALIDATION
-- ============================================================================

SELECT 'Migration 017: Agent adapter metadata columns added' AS status;

-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- To rollback:
-- ALTER TABLE agents DROP COLUMN IF EXISTS adapter;
-- ALTER TABLE agents DROP COLUMN IF EXISTS executable;
-- ALTER TABLE agents DROP COLUMN IF EXISTS model;
