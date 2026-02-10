-- Felix Database Seed Data 001
-- Creates development organization, project, and user membership for local development
-- Uses fixed UUIDs for consistency across environments

-- ============================================================================
-- DEV ORGANIZATION (untruaxioms)
-- Fixed UUID: 00000000-0000-0000-0000-000000000001
-- ============================================================================
INSERT INTO organizations (id, name, slug, owner_id, metadata)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'untruaxioms',
    'untruaxioms',
    'nsasto',
    '{"email": "nsasto@gmail.com"}'::jsonb
)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- DEV PROJECT
-- Fixed UUID: 00000000-0000-0000-0000-000000000001
-- Belongs to untruaxioms organization
-- ============================================================================
INSERT INTO projects (id, org_id, name, slug, description, metadata)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
    'Felix',
    'felix',
    'Felix AI agent orchestration system',
    '{}'::jsonb
)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- DEV USER MEMBERSHIP (nsasto)
-- User 'nsasto' is the owner of the untruaxioms organization
-- ============================================================================
INSERT INTO organization_members (org_id, user_id, role)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'nsasto',
    'owner'
)
ON CONFLICT (org_id, user_id) DO NOTHING;

-- ============================================================================
-- VERIFICATION QUERIES (uncomment to verify data)
-- ============================================================================
-- SELECT name, slug FROM organizations WHERE slug = 'dev-org';
-- SELECT name, slug FROM projects WHERE slug = 'felix';
-- SELECT user_id, role FROM organization_members WHERE user_id = 'dev-user';
