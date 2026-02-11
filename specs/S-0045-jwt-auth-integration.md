# S-0045: JWT Authentication Integration

**Phase:** 2 (Supabase Migration)  
**Effort:** 6-8 hours  
**Priority:** High  
**Dependencies:** S-0044

---

## Narrative

This specification covers integrating Supabase JWT authentication into the backend. This replaces the dev identity shim (AUTH_MODE=disabled) with real JWT token validation, extracting user_id from tokens, and enforcing authentication on all endpoints. This is the final step to enable true multi-tenant security.

---

## Acceptance Criteria

### Install JWT Library

- [ ] Add to **app/backend/requirements.txt**: `python-jose[cryptography]>=3.3.0`
- [ ] Install dependencies: `pip install -r requirements.txt`

### Update Authentication Module

- [ ] Update **app/backend/auth.py** to:
  - Decode and validate Supabase JWT tokens
  - Extract `user_id` from token payload (`sub` claim)
  - Raise 401 Unauthorized if token is invalid or missing
  - Support AUTH_MODE environment variable (disabled/enabled)

### Update Configuration

- [ ] Update **app/backend/config.py** to include:
  - `SUPABASE_JWT_SECRET` (from Supabase dashboard)
  - `AUTH_MODE` (default: "enabled")

### Update Environment File

- [ ] Add to **app/backend/.env**:
  - `SUPABASE_JWT_SECRET=<jwt-secret>`
  - `AUTH_MODE=enabled`

### Test with Real JWT Tokens

- [ ] Create test user in Supabase Auth
- [ ] Generate JWT token for test user
- [ ] Call API endpoints with Authorization header
- [ ] Verify RLS policies enforce data isolation

---

## Technical Notes

### Get JWT Secret from Supabase

1. Go to Supabase dashboard → Settings → API
2. Copy "JWT Secret" (under Project API keys section)
3. Add to .env as `SUPABASE_JWT_SECRET`

### Updated auth.py

```python
from fastapi import Depends, HTTPException, Header
from jose import jwt, JWTError
from config import AUTH_MODE, DEV_USER_ID, DEV_ORG_ID, SUPABASE_JWT_SECRET
import logging

logger = logging.getLogger(__name__)

async def get_current_user(authorization: str = Header(None)):
    """
    Get current user from JWT token.

    In AUTH_MODE=disabled: Returns dev user credentials (development only)
    In AUTH_MODE=enabled: Decodes Supabase JWT and extracts user_id
    """
    if AUTH_MODE == "disabled":
        # Development mode - return hardcoded dev user
        logger.info("AUTH_MODE=disabled, using dev user")
        return {
            "user_id": DEV_USER_ID,
            "org_id": DEV_ORG_ID,
            "project_id": "00000000-0000-0000-0000-000000000001",
            "role": "owner"
        }

    # Production mode - validate JWT token
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing Authorization header")

    # Extract token from "Bearer <token>" format
    try:
        scheme, token = authorization.split()
        if scheme.lower() != "bearer":
            raise HTTPException(status_code=401, detail="Invalid authentication scheme")
    except ValueError:
        raise HTTPException(status_code=401, detail="Invalid Authorization header format")

    # Decode and validate JWT
    try:
        payload = jwt.decode(
            token,
            SUPABASE_JWT_SECRET,
            algorithms=["HS256"],
            options={"verify_aud": False}  # Supabase tokens don't have aud claim
        )

        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token: missing sub claim")

        logger.info(f"Authenticated user: {user_id}")

        return {
            "user_id": user_id,
            "email": payload.get("email"),
            "role": payload.get("role", "authenticated")
        }

    except JWTError as e:
        logger.error(f"JWT validation error: {e}")
        raise HTTPException(status_code=401, detail="Invalid or expired token")
```

### Updated config.py

```python
import os
from dotenv import load_dotenv

load_dotenv()

# Database
DATABASE_URL = os.getenv("DATABASE_URL")

# Supabase
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY")
SUPABASE_JWT_SECRET = os.getenv("SUPABASE_JWT_SECRET")

# Authentication
AUTH_MODE = os.getenv("AUTH_MODE", "enabled")  # "enabled" or "disabled"

# Development Identity (only used when AUTH_MODE=disabled)
DEV_ORG_ID = os.getenv("DEV_ORG_ID", "00000000-0000-0000-0000-000000000001")
DEV_PROJECT_ID = os.getenv("DEV_PROJECT_ID", "00000000-0000-0000-0000-000000000001")
DEV_USER_ID = os.getenv("DEV_USER_ID", "dev-user")
```

### Create Test User in Supabase

**Via Supabase Dashboard:**

1. Go to Authentication → Users
2. Click "Add user"
3. Enter email and password
4. Click "Create user"
5. Copy user UUID

**Via Supabase Auth API:**

```bash
curl https://xxxxxxxx.supabase.co/auth/v1/signup \
  -H "apikey: <anon-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "secure-password-123"
  }'
```

Response includes `access_token` (JWT) and `user` object.

### Test API with JWT

```bash
# Get JWT token (sign in)
TOKEN=$(curl -s https://xxxxxxxx.supabase.co/auth/v1/token?grant_type=password \
  -H "apikey: <anon-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "secure-password-123"
  }' | jq -r '.access_token')

# Call API with token
curl http://localhost:8080/api/agents \
  -H "Authorization: Bearer $TOKEN"
```

---

## Dependencies

**Depends On:**

- S-0044: Row-Level Security (RLS) Policies

**Blocks:**

- S-0046: Personal Organization Auto-Creation

---

## Validation Criteria

### Installation Verification

- [ ] python-jose installed: `pip list | grep python-jose`

### Configuration Verification

- [ ] SUPABASE_JWT_SECRET exists in .env
- [ ] AUTH_MODE=enabled in .env
- [ ] Config imports without errors: `cd app/backend && python -c "import config; print(config.SUPABASE_JWT_SECRET[:10])"`

### Backend Verification

- [ ] Backend starts with AUTH_MODE=enabled: `cd app/backend && python main.py`
- [ ] No errors in startup logs

### Authentication Test (No Token)

```bash
curl http://localhost:8080/api/agents
```

Expected: 401 Unauthorized, `{"detail": "Missing Authorization header"}`

### Authentication Test (Invalid Token)

```bash
curl http://localhost:8080/api/agents \
  -H "Authorization: Bearer invalid-token"
```

Expected: 401 Unauthorized, `{"detail": "Invalid or expired token"}`

### Authentication Test (Valid Token)

```bash
# 1. Create test user in Supabase Auth
# 2. Sign in to get JWT token
TOKEN=$(curl -s https://xxxxxxxx.supabase.co/auth/v1/token?grant_type=password \
  -H "apikey: <anon-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "secure-password-123"
  }' | jq -r '.access_token')

# 3. Call API with valid token
curl http://localhost:8080/api/agents \
  -H "Authorization: Bearer $TOKEN"
```

Expected: 200 OK, list of agents (empty if user has no orgs)

### RLS Integration Test

```bash
# 1. User1 creates agent in their org
curl -X POST http://localhost:8080/api/agents/register \
  -H "Authorization: Bearer $TOKEN_USER1" \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "user1-agent", "name": "User 1 Agent"}'

# 2. User2 tries to list agents
curl http://localhost:8080/api/agents \
  -H "Authorization: Bearer $TOKEN_USER2"
```

Expected: User2 should NOT see User1's agent (RLS isolation)

### Development Mode Test

```bash
# Set AUTH_MODE=disabled in .env
# Restart backend
curl http://localhost:8080/api/agents
```

Expected: 200 OK, dev user context used, no token required

---

## Rollback Strategy

If JWT integration breaks functionality:

1. Set `AUTH_MODE=disabled` in .env
2. Restart backend
3. System works in dev mode without JWT
4. Debug JWT validation issues
5. Re-enable when fixed

---

## Notes

- python-jose handles JWT decoding and validation
- Supabase JWT tokens use HS256 algorithm
- `sub` claim contains user_id (UUID)
- `email` claim contains user's email address
- `role` claim contains "authenticated" for signed-in users
- RLS policies use `auth.jwt() ->> 'sub'` to extract user_id
- Backend doesn't need to query auth.users table - user_id from token is sufficient
- Frontend will add Supabase Auth client in Phase 3 (S-0047)
- Service key should ONLY be used for admin operations (migrations, scripts)
- Anon key is safe for frontend - RLS policies enforce access control
- Token expiration is handled by Supabase (default: 1 hour, refreshable)
- After this spec, multi-tenant security is fully functional

