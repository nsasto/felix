# S-0036: Backend Database Integration Layer

**Phase:** 0 (Local Postgres Setup)  
**Effort:** 6-8 hours  
**Priority:** Critical  
## Dependencies

- S-0035

---

## Narrative

This specification covers setting up the backend database integration layer using asyncpg and SQLAlchemy. This includes creating database connection management, configuration, and a lightweight authentication shim for development mode (AUTH_MODE=disabled).

The goal is to establish a clean database access pattern that will work seamlessly when we switch to Supabase in Phase 2.

---

## Acceptance Criteria

### Install Dependencies

- [ ] Add to **app/backend/requirements.txt**:
  - `asyncpg>=0.29.0`
  - `sqlalchemy>=2.0.0`
  - `python-dotenv>=1.0.0`
  - `databases>=0.8.0`

- [ ] Install dependencies: `cd app/backend && pip install -r requirements.txt`

### Configuration Setup

- [ ] Create **app/backend/.env** file with:
  - `DATABASE_URL=postgresql://postgres:password@localhost:5432/felix`
  - `AUTH_MODE=disabled`
  - `DEV_ORG_ID=00000000-0000-0000-0000-000000000001`
  - `DEV_PROJECT_ID=00000000-0000-0000-0000-000000000001`
  - `DEV_USER_ID=dev-user`

- [ ] Create **app/backend/config.py** with:
  - `DATABASE_URL` from environment
  - `AUTH_MODE` from environment
  - `DEV_ORG_ID`, `DEV_PROJECT_ID`, `DEV_USER_ID` from environment

### Database Connection Module

- [ ] Create **app/backend/database/**init**.py** (empty file)
- [ ] Create **app/backend/database/db.py** with:
  - `Database` instance from databases library
  - `get_db()` async context manager
  - `startup()` function to connect to database
  - `shutdown()` function to disconnect from database

### Authentication Shim

- [ ] Create **app/backend/auth.py** with:
  - `get_current_user()` dependency function
  - When `AUTH_MODE=disabled`: return `{"user_id": DEV_USER_ID, "org_id": DEV_ORG_ID}`
  - When `AUTH_MODE=enabled`: raise NotImplementedError("Supabase Auth not yet integrated")

### Integrate with FastAPI

- [ ] Update **app/backend/main.py**:
  - Import `load_dotenv` and call at top
  - Import `database.startup()` and `database.shutdown()`
  - Add `@app.on_event("startup")` handler calling `database.startup()`
  - Add `@app.on_event("shutdown")` handler calling `database.shutdown()`

---

## Technical Notes

### Configuration (config.py)

```python
import os
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:password@localhost:5432/felix")
AUTH_MODE = os.getenv("AUTH_MODE", "disabled")
DEV_ORG_ID = os.getenv("DEV_ORG_ID", "00000000-0000-0000-0000-000000000001")
DEV_PROJECT_ID = os.getenv("DEV_PROJECT_ID", "00000000-0000-0000-0000-000000000001")
DEV_USER_ID = os.getenv("DEV_USER_ID", "dev-user")
```

### Database Connection (database/db.py)

```python
from databases import Database
from config import DATABASE_URL

database = Database(DATABASE_URL)

async def get_db():
    """Async context manager for database access"""
    return database

async def startup():
    """Connect to database on startup"""
    await database.connect()
    print(f"✅ Connected to database: {DATABASE_URL}")

async def shutdown():
    """Disconnect from database on shutdown"""
    await database.disconnect()
    print("✅ Disconnected from database")
```

### Authentication Shim (auth.py)

```python
from fastapi import Depends, HTTPException, Header
from config import AUTH_MODE, DEV_USER_ID, DEV_ORG_ID

async def get_current_user(authorization: str = Header(None)):
    """
    Get current user from JWT token (Phase 2) or dev shim (Phase 0).

    In AUTH_MODE=disabled: Returns dev user credentials
    In AUTH_MODE=enabled: Decodes JWT and extracts user_id
    """
    if AUTH_MODE == "disabled":
        # Development mode - return hardcoded dev user
        return {
            "user_id": DEV_USER_ID,
            "org_id": DEV_ORG_ID,
            "role": "owner"
        }

    # Phase 2: JWT decoding will be implemented here
    raise NotImplementedError("Supabase Auth integration not yet implemented")
```

### FastAPI Integration (main.py)

```python
from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI
from database.db import startup, shutdown

app = FastAPI(title="Felix API")

@app.on_event("startup")
async def on_startup():
    await startup()

@app.on_event("shutdown")
async def on_shutdown():
    await shutdown()

# ... rest of FastAPI setup
```

### Environment Variables (.env)

```bash
# Database
DATABASE_URL=postgresql://postgres:password@localhost:5432/felix

# Authentication
AUTH_MODE=disabled

# Development Identity
DEV_ORG_ID=00000000-0000-0000-0000-000000000001
DEV_PROJECT_ID=00000000-0000-0000-0000-000000000001
DEV_USER_ID=dev-user
```

---

## Dependencies

**Depends On:**

- S-0035: Database Schema and Migrations Setup

**Blocks:**

- S-0037: Database Writers Implementation

---

## Validation Criteria

### Installation Verification

- [ ] Dependencies installed: `pip list | grep asyncpg` (should show asyncpg>=0.29.0)
- [ ] Dependencies installed: `pip list | grep sqlalchemy` (should show sqlalchemy>=2.0.0)
- [ ] Dependencies installed: `pip list | grep databases` (should show databases>=0.8.0)
- [ ] Dependencies installed: `pip list | grep python-dotenv` (should show python-dotenv>=1.0.0)

### Configuration Verification

- [ ] File exists: **app/backend/.env**
- [ ] File contains DATABASE_URL: `grep "DATABASE_URL" app/backend/.env`
- [ ] File contains AUTH_MODE: `grep "AUTH_MODE" app/backend/.env`
- [ ] File exists: **app/backend/config.py**
- [ ] Config loads without errors: `cd app/backend && python -c "import config; print(config.DATABASE_URL)"`

### Database Connection Verification

- [ ] File exists: **app/backend/database/**init**.py**
- [ ] File exists: **app/backend/database/db.py**
- [ ] Database module imports: `cd app/backend && python -c "from database.db import database, startup, shutdown"`

### Authentication Verification

- [ ] File exists: **app/backend/auth.py**
- [ ] Auth module imports: `cd app/backend && python -c "from auth import get_current_user"`

### Integration Verification

- [ ] Backend starts without errors: `cd app/backend && python main.py`
- [ ] Startup message appears: "✅ Connected to database: postgresql://postgres:..."
- [ ] Health endpoint responds: `curl http://localhost:8080/health` (status 200)
- [ ] Shutdown logs appear when stopping backend (Ctrl+C)

### Functional Test

- [ ] Create test endpoint in main.py:

```python
from auth import get_current_user
from database.db import get_db

@app.get("/test/db")
async def test_db(user: dict = Depends(get_current_user), db = Depends(get_db)):
    result = await db.fetch_one("SELECT COUNT(*) as count FROM organizations")
    return {"user": user, "org_count": result["count"]}
```

- [ ] Call test endpoint: `curl http://localhost:8080/test/db`
- [ ] Expected response: `{"user": {"user_id": "dev-user", "org_id": "00000000-0000-0000-0000-000000000001", "role": "owner"}, "org_count": 1}`

---

## Rollback Strategy

If issues arise:

1. Remove dependencies from requirements.txt
2. Delete database/ directory
3. Delete auth.py
4. Remove startup/shutdown handlers from main.py
5. Delete .env file

**Critical:** Keep .env file out of version control - add to .gitignore

---

## Notes

- .env file should be added to .gitignore (never commit to version control)
- AUTH_MODE=disabled bypasses JWT validation (development only)
- Dev identity (DEV_USER_ID, DEV_ORG_ID) provides fixed user context
- Phase 2 will implement JWT decoding in get_current_user()
- Database connection is established once on startup, reused throughout app lifecycle
- Use `Depends(get_current_user)` on all endpoints that need user context
- Use `Depends(get_db)` on all endpoints that need database access
- asyncpg is chosen for performance, databases library provides nice async interface
- SQLAlchemy 2.0 is installed but not yet used (raw SQL for simplicity in Phase 0)

