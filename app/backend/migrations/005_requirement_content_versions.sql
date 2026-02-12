-- Felix Database Migration 005
-- Adds requirement_content (current snapshot) and requirement_versions (history).

-- ====================================================================
-- CURRENT REQUIREMENT CONTENT
-- ====================================================================
CREATE TABLE IF NOT EXISTS requirement_content (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requirement_id UUID NOT NULL UNIQUE REFERENCES requirements(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    current_version_id UUID NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ====================================================================
-- REQUIREMENT VERSION HISTORY
-- ====================================================================
CREATE TABLE IF NOT EXISTS requirement_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requirement_id UUID NOT NULL REFERENCES requirements(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    author_id TEXT NULL,
    source TEXT NOT NULL DEFAULT 'manual',
    diff_from_id UUID NULL REFERENCES requirement_versions(id) ON DELETE SET NULL
);

ALTER TABLE requirement_content
    DROP CONSTRAINT IF EXISTS requirement_content_current_version_fk;
ALTER TABLE requirement_content
    ADD CONSTRAINT requirement_content_current_version_fk
    FOREIGN KEY (current_version_id) REFERENCES requirement_versions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_requirement_versions_requirement_id
    ON requirement_versions(requirement_id);
CREATE INDEX IF NOT EXISTS idx_requirement_versions_requirement_id_created_at
    ON requirement_versions(requirement_id, created_at DESC);

-- ====================================================================
-- ROLLBACK
-- ====================================================================
-- DROP TABLE IF EXISTS requirement_content CASCADE;
-- DROP TABLE IF EXISTS requirement_versions CASCADE;
