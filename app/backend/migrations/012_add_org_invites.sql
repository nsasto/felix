-- Felix Database Migration 012
-- Adds organization_invites and updates organization_members timestamps.

-- Add updated_at to organization_members
ALTER TABLE organization_members
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Organization invites table
CREATE TABLE IF NOT EXISTS organization_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'member',
    status TEXT NOT NULL DEFAULT 'pending',
    invited_by_user_id TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (role IN ('owner', 'admin', 'member')),
    CHECK (status IN ('pending', 'accepted', 'revoked'))
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_org_invites_org_id ON organization_invites(org_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_org_invites_org_email_pending
    ON organization_invites(org_id, email)
    WHERE status = 'pending';

-- Updated_at triggers
DROP TRIGGER IF EXISTS set_updated_at_organization_members ON organization_members;
CREATE TRIGGER set_updated_at_organization_members
BEFORE UPDATE ON organization_members
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_org_invites ON organization_invites;
CREATE TRIGGER set_updated_at_org_invites
BEFORE UPDATE ON organization_invites
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

