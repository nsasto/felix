-- Add settings table for scoped configuration storage
-- Scopes: org, user, project

CREATE TABLE IF NOT EXISTS settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scope_type TEXT NOT NULL CHECK (scope_type IN ('org', 'user', 'project')),
    scope_id TEXT NOT NULL,
    config JSONB NOT NULL,
    schema_version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(scope_type, scope_id)
);

CREATE INDEX IF NOT EXISTS idx_settings_scope ON settings(scope_type, scope_id);

DROP TRIGGER IF EXISTS set_updated_at_settings ON settings;
CREATE TRIGGER set_updated_at_settings
BEFORE UPDATE ON settings
FOR EACH ROW EXECUTE FUNCTION set_updated_at();
