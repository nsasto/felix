-- Felix Database Migration 008
-- Adds agent_profiles and machines tables, and extends agents for allocation/provenance.

-- ====================================================================
-- TABLE: machines
-- ====================================================================
CREATE TABLE IF NOT EXISTS machines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    hostname TEXT NOT NULL,
    fingerprint TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(org_id, fingerprint)
);

CREATE INDEX IF NOT EXISTS idx_machines_org_id ON machines(org_id);
CREATE INDEX IF NOT EXISTS idx_machines_hostname ON machines(hostname);

-- ====================================================================
-- TABLE: agent_profiles (org-scoped templates)
-- ====================================================================
CREATE TABLE IF NOT EXISTS agent_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    adapter TEXT NOT NULL,
    executable TEXT NOT NULL,
    args JSONB,
    model TEXT,
    working_directory TEXT,
    environment JSONB DEFAULT '{}'::jsonb,
    description TEXT,
    source TEXT NOT NULL DEFAULT 'user',
    created_by_user_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_agent_profiles_org_id ON agent_profiles(org_id);
CREATE INDEX IF NOT EXISTS idx_agent_profiles_adapter ON agent_profiles(adapter);

-- ====================================================================
-- TABLE: agents (extend runtime instances)
-- ====================================================================
ALTER TABLE agents
    ADD COLUMN IF NOT EXISTS profile_id UUID REFERENCES agent_profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS assigned_user_id TEXT,
    ADD COLUMN IF NOT EXISTS machine_id UUID REFERENCES machines(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS registered_at TIMESTAMPTZ DEFAULT NOW(),
    ADD COLUMN IF NOT EXISTS registered_by_user_id TEXT,
    ADD COLUMN IF NOT EXISTS registered_by_machine_id UUID REFERENCES machines(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS override_executable TEXT,
    ADD COLUMN IF NOT EXISTS override_model TEXT;

CREATE INDEX IF NOT EXISTS idx_agents_profile_id ON agents(profile_id);
CREATE INDEX IF NOT EXISTS idx_agents_assigned_user_id ON agents(assigned_user_id);
CREATE INDEX IF NOT EXISTS idx_agents_machine_id ON agents(machine_id);

-- ====================================================================
-- TRIGGERS (updated_at)
-- ====================================================================
DROP TRIGGER IF EXISTS set_updated_at_machines ON machines;
CREATE TRIGGER set_updated_at_machines
BEFORE UPDATE ON machines
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_agent_profiles ON agent_profiles;
CREATE TRIGGER set_updated_at_agent_profiles
BEFORE UPDATE ON agent_profiles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ====================================================================
-- ROLLBACK
-- ====================================================================
-- DROP TRIGGER IF EXISTS set_updated_at_agent_profiles ON agent_profiles;
-- DROP TRIGGER IF EXISTS set_updated_at_machines ON machines;
-- ALTER TABLE agents
--     DROP COLUMN IF EXISTS override_model,
--     DROP COLUMN IF EXISTS override_executable,
--     DROP COLUMN IF EXISTS registered_by_machine_id,
--     DROP COLUMN IF EXISTS registered_by_user_id,
--     DROP COLUMN IF EXISTS registered_at,
--     DROP COLUMN IF EXISTS machine_id,
--     DROP COLUMN IF EXISTS assigned_user_id,
--     DROP COLUMN IF EXISTS profile_id;
-- DROP TABLE IF EXISTS agent_profiles CASCADE;
-- DROP TABLE IF EXISTS machines CASCADE;
