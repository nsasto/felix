-- Felix Database Migration 004
-- Adds requirement_dependencies join table for requirement dependency mapping.

-- ====================================================================
-- REQUIREMENT DEPENDENCIES
-- ====================================================================
CREATE TABLE IF NOT EXISTS requirement_dependencies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requirement_id UUID NOT NULL REFERENCES requirements(id) ON DELETE CASCADE,
    depends_on_id UUID NOT NULL REFERENCES requirements(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(requirement_id, depends_on_id),
    CHECK (requirement_id <> depends_on_id)
);

CREATE INDEX IF NOT EXISTS idx_requirement_dependencies_requirement_id
    ON requirement_dependencies(requirement_id);
CREATE INDEX IF NOT EXISTS idx_requirement_dependencies_depends_on_id
    ON requirement_dependencies(depends_on_id);

-- ====================================================================
-- ROLLBACK
-- ====================================================================
-- DROP TABLE IF EXISTS requirement_dependencies CASCADE;
