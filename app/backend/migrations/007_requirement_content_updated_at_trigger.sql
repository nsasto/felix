-- Felix Database Migration 007
-- Adds updated_at trigger for requirement_content.

-- ====================================================================
-- TRIGGERS
-- ====================================================================
DROP TRIGGER IF EXISTS set_updated_at_requirement_content ON requirement_content;
CREATE TRIGGER set_updated_at_requirement_content
BEFORE UPDATE ON requirement_content
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ====================================================================
-- ROLLBACK
-- ====================================================================
-- DROP TRIGGER IF EXISTS set_updated_at_requirement_content ON requirement_content;
