# Release Notes - v0.8.0

## Highlights
- **🔒 Project-scoped API keys** - Secure sync authentication with per-project access control
- **⚠️ BREAKING CHANGE** - API keys now required when sync is enabled
- **✨ API Keys UI** - Generate and manage keys directly in Settings

## Breaking Changes

### API Key Required for Sync

**Before v0.8:** Sync worked without authentication (development only)

**After v0.8:** API key required when `sync.enabled = true`

**Migration Steps:**

1. **Generate API Key via UI:**
   - Open Felix UI (http://localhost:3000)
   - Select your project
   - Go to Settings → API Keys
   - Click "New Key"
   - Copy the generated key (starts with `fsk_`)

2. **Update Configuration:**

   **Option A: Environment Variable**
   ```powershell
   $env:FELIX_SYNC_KEY = "fsk_your_api_key_here"
   ```

   **Option B: Config File (.felix/config.json)**
   ```json
   {
     "sync": {
       "enabled": true,
       "base_url": "http://localhost:8080",
       "api_key": "fsk_your_api_key_here"
     }
   }
   ```

3. **Run Agent:**
   ```powershell
   felix run S-0001
   ```

4. **Expected Output:**
   ```
   [18:51:16.212] INFO [sync] Sync enabled → http://localhost:8080
   [18:51:16.431] INFO [sync] Agent registered successfully
   ```

**If API key is missing when sync is enabled:**
```
ERROR: Sync is enabled but no API key is configured.

API keys are required for syncing run artifacts to the backend.

To generate an API key:
1. Open the Felix UI at http://localhost:3000
2. Select your project
3. Navigate to Settings → API Keys
4. Click 'New Key' to generate an API key
5. Copy the generated key (it starts with 'fsk_')

Then set the API key using one of these methods:

Method 1 - Environment Variable (recommended):
  $env:FELIX_SYNC_KEY = "fsk_your_api_key_here"

Method 2 - Config File (.felix/config.json):
  {
    "sync": {
      "enabled": true,
      "api_key": "fsk_your_api_key_here"
    }
  }

Note: If you don't need sync, set enabled to false in config.json
```

## Security

### Project-Scoped Authorization

- **One key = One project:** API keys grant access to a single project only
- **No cross-project access:** Keys cannot be used to access other projects
- **Secure storage:** Keys hashed with SHA256 before database storage
- **One-time display:** Plain-text key shown only once during generation
- **Expires:** Optional expiration (30/90/180/365 days or never)
- **Revocable:** Keys can be revoked immediately via UI

### Authentication Flow

1. CLI sends API key in `Authorization: Bearer fsk_...` header
2. Backend validates key hash and retrieves project_id
3. All sync endpoints verify request project matches key's project
4. Returns 401 Unauthorized if key invalid
5. Returns 403 Forbidden if key belongs to different project

## New Features

### API Keys Management UI

**Location:** Settings → API Keys (only visible when project selected)

**Key Generation:**
- Name your key for identification
- Set expiration period (30/90/180/365 days or never)
- One-time key display with copy-to-clipboard
- Security warning to save key immediately

**Key Management:**
- List all active keys with metadata:
  - Name and creation date
  - Last used timestamp
  - Expiration date
  - Key ID (last 8 characters)
- Revoke keys with confirmation dialog
- Automatic refresh after create/revoke

**Help Section:**
- CLI setup instructions
- Config.json example
- Environment variable example

### Backend Changes

- **Repository Pattern:** New `IApiKeyRepository` protocol with PostgreSQL implementation
- **Database Migration:** `017_project_scoped_api_keys.sql` migrates from agent-scoped to project-scoped
- **API Endpoints:**
  - `POST /api/projects/{id}/keys` - Generate new key
  - `GET /api/projects/{id}/keys` - List project keys
  - `DELETE /api/projects/{id}/keys/{key_id}` - Revoke key
- **Sync Endpoints Updated:** All 7 sync endpoints now enforce project authorization:
  - `/api/runs` (POST)
  - `/api/runs/{id}/events` (POST/GET)
  - `/api/runs/{id}/finish` (POST)
  - `/api/runs/{id}/files` (POST/GET)

### CLI Changes

- **Validation Layer:** Sync initialization fails fast with clear error if key missing
- **Helpful Errors:** Multi-line error messages direct users to UI for key generation
- **Optional Sync:** Local-only workflow still works (set `sync.enabled = false`)

## Documentation Updates

- **README.md:** Updated sync section to require API keys
- **HOW_TO_USE.md:** 
  - Updated configuration examples
  - Added key generation instructions
  - Updated troubleshooting for 401 errors
  - Removed references to old generate-sync-key.py script
- **AGENTS.md:** Updated with current API key setup flow

## Database Schema

### api_keys Table Changes

**Added:**
- `project_id` (NOT NULL, foreign key to projects.id)

**Removed:**
- `agent_id` (no longer agent-scoped)

**Indexes:**
- `idx_api_keys_project_id` - Fast project key lookups
- `idx_api_keys_key_hash` - Fast authentication lookups
- `idx_api_keys_project_is_active` - Fast active key queries

**Cascade:**
- Deleting a project automatically revokes all its API keys

## Technical Details

### Key Format

- **Prefix:** `fsk_` (Felix Sync Key)
- **Entropy:** 256 bits (43 base64 characters)
- **Example:** `fsk_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789AbCdEfGhIjK`

### Storage Security

- Plain-text keys never stored
- SHA256 hash stored in database
- Timing-safe comparison during verification
- Key generation uses cryptographically secure random bytes

### Rate Limiting

- 100 requests per minute per API key (existing limit, unchanged)
- Applies to all sync endpoints

## Testing

### Manual Test Checklist

- [ ] Generate API key via UI
- [ ] Copy key with clipboard button
- [ ] Configure CLI with valid key
- [ ] Run agent and verify sync works
- [ ] Try with invalid key (should get 401)
- [ ] Try with wrong project's key (should get 403)
- [ ] Revoke key via UI
- [ ] Verify revoked key rejected (401)
- [ ] Test expired key rejection
- [ ] Test key last_used_at updates

### Database Migration

```powershell
# Apply migration
cd app/backend
python -m app.backend.database migrations/017_project_scoped_api_keys.sql

# Verify schema
psql felix -c "\d api_keys"
```

## Known Issues

- Existing API keys invalidated by migration (TRUNCATE in 017 migration)
- Users must regenerate keys after upgrade

## Future Enhancements

- Multi-project keys (enterprise feature)
- API key permissions/scopes (read-only, write-only)
- Audit log for key usage
- Email notifications on key expiration
- Auto-rotation policies

---

**Upgrade Path:** v0.7.x → v0.8.0

**Rollback:** See [docs/SYNC_OPERATIONS.md](docs/SYNC_OPERATIONS.md#rollback-procedures)
