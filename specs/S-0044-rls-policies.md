# S-0044: Row-Level Security (RLS) Policies

**Phase:** 2 (Supabase Migration)  
**Effort:** 8-10 hours  
**Priority:** Critical  
**Dependencies:** S-0043

---

## Narrative

This specification covers implementing Row-Level Security (RLS) policies on all database tables to enforce multi-tenant data isolation. This ensures users can only access data belonging to organizations they're members of. This is a critical security feature that must be implemented before enabling authentication.

---

## Acceptance Criteria

### Migration File

- [ ] Create **app/backend/migrations/002_enable_rls.sql**

### Helper Functions

- [ ] Create `is_org_member(org_id, user_id)` function
- [ ] Create `has_org_role(org_id, user_id, role)` function

### Enable RLS

- [ ] Enable RLS on all 8 tables:
  - `ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;`
  - `ALTER TABLE projects ENABLE ROW LEVEL SECURITY;`
  - `ALTER TABLE agents ENABLE ROW LEVEL SECURITY;`
  - `ALTER TABLE agent_states ENABLE ROW LEVEL SECURITY;`
  - `ALTER TABLE runs ENABLE ROW LEVEL SECURITY;`
  - `ALTER TABLE run_artifacts ENABLE ROW LEVEL SECURITY;`
  - `ALTER TABLE requirements ENABLE ROW LEVEL SECURITY;`
  - `ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY;`

### Policies for `organizations`

- [ ] `SELECT`: User can see orgs they're a member of
- [ ] `INSERT`: User can create personal org (handled by trigger in S-0046)
- [ ] `UPDATE`: Owner or admin can update org
- [ ] `DELETE`: Owner can delete org

### Policies for `projects`

- [ ] `SELECT`: User is member of org
- [ ] `INSERT`: User is member of org
- [ ] `UPDATE`: User is member of org
- [ ] `DELETE`: Owner or admin of org

### Policies for `agents`, `runs`, `requirements`

- [ ] `SELECT`: User is member of project's org
- [ ] `INSERT`: User is member of project's org
- [ ] `UPDATE`: User is member of project's org
- [ ] `DELETE`: User is member of project's org

### Policies for `agent_states`, `run_artifacts`

- [ ] `SELECT`: User is member of related project's org
- [ ] `INSERT`: User is member of related project's org
- [ ] `UPDATE`: User is member of related project's org
- [ ] `DELETE`: User is member of related project's org

### Policies for `organization_members`

- [ ] `SELECT`: User can see members of orgs they belong to
- [ ] `INSERT`: Owner or admin can add members
- [ ] `UPDATE`: Owner can change roles
- [ ] `DELETE`: Owner can remove members, or member can leave

### Apply Migration

- [ ] Apply migration to Supabase: Run `002_enable_rls.sql` in SQL Editor
- [ ] Verify all policies exist
- [ ] Seed dev user membership if not exists

---

## Technical Notes

### Helper Functions

```sql
-- Check if user is a member of an organization
CREATE OR REPLACE FUNCTION is_org_member(org_id UUID, user_id TEXT)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM organization_members
    WHERE organization_members.org_id = $1
      AND organization_members.user_id = $2
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check if user has specific role in organization
CREATE OR REPLACE FUNCTION has_org_role(org_id UUID, user_id TEXT, required_role TEXT)
RETURNS BOOLEAN AS $$
DECLARE
  user_role TEXT;
  role_hierarchy INTEGER;
BEGIN
  -- Get user's role in org
  SELECT role INTO user_role
  FROM organization_members
  WHERE organization_members.org_id = $1
    AND organization_members.user_id = $2;

  IF user_role IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Role hierarchy: owner > admin > member
  IF user_role = 'owner' THEN
    RETURN TRUE;
  ELSIF user_role = 'admin' AND required_role IN ('admin', 'member') THEN
    RETURN TRUE;
  ELSIF user_role = 'member' AND required_role = 'member' THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### RLS Policies for Organizations

```sql
-- Organizations: SELECT
CREATE POLICY "Users can view orgs they are members of"
ON organizations FOR SELECT
USING (is_org_member(id, auth.jwt() ->> 'sub'));

-- Organizations: INSERT (handled by personal org trigger in S-0046)
CREATE POLICY "Users can create personal organizations"
ON organizations FOR INSERT
WITH CHECK (owner_id = auth.jwt() ->> 'sub');

-- Organizations: UPDATE
CREATE POLICY "Owners and admins can update orgs"
ON organizations FOR UPDATE
USING (has_org_role(id, auth.jwt() ->> 'sub', 'admin'));

-- Organizations: DELETE
CREATE POLICY "Owners can delete orgs"
ON organizations FOR DELETE
USING (has_org_role(id, auth.jwt() ->> 'sub', 'owner'));
```

### RLS Policies for Projects

```sql
-- Projects: SELECT
CREATE POLICY "Users can view projects in their orgs"
ON projects FOR SELECT
USING (is_org_member(org_id, auth.jwt() ->> 'sub'));

-- Projects: INSERT
CREATE POLICY "Org members can create projects"
ON projects FOR INSERT
WITH CHECK (is_org_member(org_id, auth.jwt() ->> 'sub'));

-- Projects: UPDATE
CREATE POLICY "Org members can update projects"
ON projects FOR UPDATE
USING (is_org_member(org_id, auth.jwt() ->> 'sub'));

-- Projects: DELETE
CREATE POLICY "Org owners and admins can delete projects"
ON projects FOR DELETE
USING (
  is_org_member(org_id, auth.jwt() ->> 'sub')
  AND has_org_role(org_id, auth.jwt() ->> 'sub', 'admin')
);
```

### RLS Policies for Agents

```sql
-- Agents: SELECT
CREATE POLICY "Users can view agents in their org's projects"
ON agents FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM projects
    WHERE projects.id = agents.project_id
      AND is_org_member(projects.org_id, auth.jwt() ->> 'sub')
  )
);

-- Agents: INSERT
CREATE POLICY "Users can create agents in their org's projects"
ON agents FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM projects
    WHERE projects.id = agents.project_id
      AND is_org_member(projects.org_id, auth.jwt() ->> 'sub')
  )
);

-- Agents: UPDATE
CREATE POLICY "Users can update agents in their org's projects"
ON agents FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM projects
    WHERE projects.id = agents.project_id
      AND is_org_member(projects.org_id, auth.jwt() ->> 'sub')
  )
);

-- Agents: DELETE
CREATE POLICY "Users can delete agents in their org's projects"
ON agents FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM projects
    WHERE projects.id = agents.project_id
      AND is_org_member(projects.org_id, auth.jwt() ->> 'sub')
  )
);
```

### Similar Policies for Other Tables

Apply similar patterns to:

- **runs**: Check project_id → projects.org_id → organization_members
- **run_artifacts**: Check run_id → runs.project_id → projects.org_id → organization_members
- **requirements**: Check project_id → projects.org_id → organization_members
- **agent_states**: Check agent_id → agents.project_id → projects.org_id → organization_members
- **organization_members**: Can view members of own orgs, owners can manage

---

## Dependencies

**Depends On:**

- S-0043: Supabase Project Setup and Schema Migration

**Blocks:**

- S-0045: JWT Authentication Integration

---

## Validation Criteria

### RLS Enabled Verification

```sql
-- Check RLS status for all tables
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    'organizations', 'projects', 'agents', 'agent_states',
    'runs', 'run_artifacts', 'requirements', 'organization_members'
  );
```

All should show `rowsecurity = true`.

### Policy Verification

```sql
-- List all policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;
```

Should show ~30-40 policies across 8 tables.

### Functional Test (with AUTH_MODE=disabled)

- [ ] Start backend (still using dev user)
- [ ] Create agent → should succeed (dev user is member of dev org)
- [ ] List agents → should see agent
- [ ] Create run → should succeed

### Security Test (with service key vs anon key)

**Using service key (bypasses RLS):**

```bash
curl https://xxxxxxxx.supabase.co/rest/v1/organizations \
  -H "apikey: <service-key>" \
  -H "Authorization: Bearer <service-key>"
```

Should return all orgs.

**Using anon key (RLS enforced):**

```bash
curl https://xxxxxxxx.supabase.co/rest/v1/organizations \
  -H "apikey: <anon-key>" \
  -H "Authorization: Bearer <anon-key>"
```

Should return empty array (no authenticated user).

### Seed Dev User Membership

```sql
-- Ensure dev user is member of dev org
INSERT INTO organization_members (org_id, user_id, role)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'dev-user',
  'owner'
)
ON CONFLICT (org_id, user_id) DO NOTHING;
```

---

## Rollback Strategy

If RLS breaks functionality:

1. Disable RLS temporarily: `ALTER TABLE <table> DISABLE ROW LEVEL SECURITY;`
2. Debug policy issues using Supabase logs
3. Fix policies and re-enable RLS

**Critical:** Do NOT deploy to production without RLS enabled and tested.

---

## Notes

- RLS is PostgreSQL's built-in security feature for multi-tenant isolation
- `auth.jwt() ->> 'sub'` extracts user_id from Supabase JWT token
- SECURITY DEFINER functions run with elevated privileges (needed to check membership)
- Helper functions (is_org_member, has_org_role) are reused across all policies
- Phase 2 still uses AUTH_MODE=disabled, but RLS is ready for Phase 2 (S-0045)
- Service key bypasses RLS (admin access) - never expose in frontend
- Anon key respects RLS (user access) - safe for frontend
- Policies use USING for row filtering and WITH CHECK for insert/update validation
- Personal organizations (Phase 2, S-0046) auto-grant owner role to creator
- Total policies: ~4 per table × 8 tables = ~32 policies

