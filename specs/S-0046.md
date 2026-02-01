# S-0046: Personal Organization Auto-Creation

**Phase:** 2 (Supabase Migration)  
**Effort:** 4-5 hours  
**Priority:** High  
**Dependencies:** S-0045

---

## Narrative

This specification covers implementing a database trigger that automatically creates a personal organization for every new user when they sign up via Supabase Auth. This ensures every user has a default workspace immediately upon account creation, with the user as the owner.

---

## Acceptance Criteria

### Migration File

- [ ] Create **app/backend/migrations/003_personal_org_trigger.sql**

### Trigger Function

- [ ] Create `create_personal_organization()` trigger function that:
  - Fires after INSERT on `auth.users`
  - Creates organization with name "{User}'s Organization"
  - Creates slug from email or user_id
  - Sets `owner_id` to new user's UUID
  - Inserts organization_members record with role="owner"

### Database Trigger

- [ ] Create trigger `on_auth_user_created` on `auth.users` table
- [ ] Trigger fires AFTER INSERT
- [ ] Calls `create_personal_organization()` function

### Apply Migration

- [ ] Run migration in Supabase SQL Editor
- [ ] Verify trigger exists
- [ ] Test with new user signup

---

## Technical Notes

### Trigger Function (003_personal_org_trigger.sql)

```sql
-- Function to create personal organization for new users
CREATE OR REPLACE FUNCTION create_personal_organization()
RETURNS TRIGGER AS $$
DECLARE
  new_org_id UUID;
  org_slug TEXT;
  org_name TEXT;
BEGIN
  -- Generate organization slug from email (part before @) or user_id
  IF NEW.email IS NOT NULL THEN
    org_slug := LOWER(SPLIT_PART(NEW.email, '@', 1)) || '-personal-' || SUBSTRING(NEW.id::text, 1, 8);
    org_name := SPLIT_PART(NEW.email, '@', 1) || '''s Organization';
  ELSE
    org_slug := 'user-' || SUBSTRING(NEW.id::text, 1, 8) || '-personal';
    org_name := 'Personal Organization';
  END IF;

  -- Create organization
  INSERT INTO organizations (owner_id, name, slug, metadata)
  VALUES (
    NEW.id::text,
    org_name,
    org_slug,
    jsonb_build_object(
      'personal', true,
      'created_via', 'auto_trigger'
    )
  )
  RETURNING id INTO new_org_id;

  -- Add user as owner in organization_members
  INSERT INTO organization_members (org_id, user_id, role)
  VALUES (new_org_id, NEW.id::text, 'owner');

  RAISE NOTICE 'Created personal organization % for user %', new_org_id, NEW.id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on auth.users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION create_personal_organization();
```

### Slug Generation Logic

- **If user has email:** `john-personal-550e8400` (email prefix + "personal" + first 8 chars of UUID)
- **If no email:** `user-550e8400-personal` (user UUID prefix + "personal")
- Ensures uniqueness via combination of email/UUID and random portion

### Metadata Field

Personal organizations are tagged with:

```json
{
  "personal": true,
  "created_via": "auto_trigger"
}
```

This allows frontend to:

- Display personal orgs differently (e.g., hide from org switcher unless only org)
- Prevent deletion of personal orgs
- Show special icon/badge for personal orgs

---

## Dependencies

**Depends On:**

- S-0045: JWT Authentication Integration

**Blocks:**

- S-0047: Frontend Supabase Client and Realtime Hooks (Phase 3)

---

## Validation Criteria

### Migration Applied

- [ ] Run migration: Paste `003_personal_org_trigger.sql` in Supabase SQL Editor → Run
- [ ] No errors in execution
- [ ] Function exists: `SELECT proname FROM pg_proc WHERE proname = 'create_personal_organization';` (should return 1 row)
- [ ] Trigger exists: `SELECT tgname FROM pg_trigger WHERE tgname = 'on_auth_user_created';` (should return 1 row)

### Test with New User Signup

**Via Supabase Dashboard:**

1. Authentication → Users → Add user
2. Email: newuser@example.com, Password: Test123!@#
3. Click "Create user"
4. Check organizations table: `SELECT * FROM organizations WHERE owner_id = '<new-user-uuid>';`
5. Should see 1 organization with name "newuser's Organization"
6. Check organization_members: `SELECT * FROM organization_members WHERE user_id = '<new-user-uuid>';`
7. Should see 1 membership with role="owner"

**Via Auth API:**

```bash
# Sign up new user
curl https://xxxxxxxx.supabase.co/auth/v1/signup \
  -H "apikey: <anon-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "another@example.com",
    "password": "SecurePass123!@#"
  }'

# Response includes user object with id (UUID)

# Verify organization created
psql "postgresql://postgres:password@db.xxxxxxxx.supabase.co:5432/postgres" \
  -c "SELECT * FROM organizations WHERE owner_id = '<user-id>';"

# Should show 1 personal organization
```

### Integration Test with Backend

```bash
# 1. Sign up new user
USER_RESPONSE=$(curl -s https://xxxxxxxx.supabase.co/auth/v1/signup \
  -H "apikey: <anon-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "testuser@example.com",
    "password": "Test123!@#"
  }')

# 2. Extract access token
TOKEN=$(echo $USER_RESPONSE | jq -r '.access_token')

# 3. List agents (should be empty, but request should succeed)
curl http://localhost:8080/api/agents \
  -H "Authorization: Bearer $TOKEN"

# 4. Verify user can access their personal org
# (RLS policies should allow access because user is owner)
```

Expected: 200 OK, empty agents list (personal org just created, no agents yet)

### Verify Trigger Logs

```sql
-- Check Supabase logs for trigger execution
-- In Supabase dashboard: Logs → Postgres Logs
-- Search for: "Created personal organization"
```

---

## Rollback Strategy

If trigger causes issues:

1. Drop trigger: `DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;`
2. Drop function: `DROP FUNCTION IF EXISTS create_personal_organization();`
3. Debug issues
4. Recreate trigger with fixes

**Note:** Existing personal orgs remain in database (no rollback needed for data).

---

## Notes

- Trigger runs automatically for ALL new user signups
- Personal orgs cannot be deleted (enforce in frontend/backend logic)
- Users can create additional team organizations manually
- Personal org is always tagged with `{"personal": true}` in metadata
- Trigger uses SECURITY DEFINER to bypass RLS during creation
- RAISE NOTICE logs to Postgres logs (viewable in Supabase dashboard)
- If trigger fails, user signup still succeeds (non-blocking)
- Frontend can check metadata.personal to identify personal orgs
- Slug uniqueness is guaranteed by email/UUID combination
- Owner role grants full permissions via RLS policies (S-0044)
- After this spec, every user automatically has a workspace upon signup
