# Felix Cloud Migration Plan

## Overview

This document outlines the migration strategy for transforming Felix from a file-based system to a cloud-native SaaS platform using Supabase. The migration follows the architectural principles defined in [CLOUD_ORCHESTRATION.md](CLOUD_ORCHESTRATION.md) and addresses the production readiness requirements in [PRODUCTION-TODO.md](../PRODUCTION-TODO.md).

**Note**: This is a full migration to cloud-native architecture. File-based storage is being completely replaced with Supabase PostgreSQL database.

## Current WebSocket Implementation

### 1. Project State WebSocket (`/ws/projects/{project_id}`)

**File**: `app/backend/routers/websocket.py`

**Purpose**: Real-time project state updates via filesystem watching

**Current Implementation**:

- `ConnectionManager` class manages per-project WebSocket connections
- Watches `.felix/state.json`, `.felix/requirements.json`, and `runs/` directory using `watchfiles` library
- Broadcasts events: `mode_change`, `status_update`, `iteration_start`, `iteration_complete`, `run_complete`, `requirements_update`, `run_artifact_created`
- 600+ lines of code handling connection pooling, event broadcasting, filesystem monitoring

**Migration Strategy**: Replace with Supabase Realtime database subscriptions

### 2. Agent Console Streaming (`/api/agents/{agent_id}/console`)

**File**: `app/backend/routers/agents.py` (line 858+)

**Purpose**: Real-time streaming of agent console output

**Current Implementation**:

- `agent_console_stream()` WebSocket endpoint tails `output.log` files
- Polls files every 500ms, streams new content
- Handles run transitions and file watching
- ~200 lines of code for log streaming

**Migration Strategy**: MUST REMAIN as custom WebSocket per CLOUD_ORCHESTRATION.md principles

- High-frequency log streaming not suitable for database subscriptions
- Control plane functionality (start/stop signals) requires direct WebSocket
- This is an exception to the "database-first" rule

### 3. Frontend WebSocket Hook

**File**: `app/frontend/hooks/useProjectWebSocket.ts`

**Current Implementation**:

- React hook managing WebSocket connection to `ws://localhost:8080`
- Auto-reconnect logic with exponential backoff
- Event handling for all state update types
- Maintains state/requirements cache
- 289 lines of TypeScript

**Migration Strategy**: Hybrid implementation supporting both Supabase Realtime and custom WebSocket

## Hybrid Architecture

Per CLOUD_ORCHESTRATION.md guidance:

> **WebSockets are used for**: Server → agent control signals (start, stop) and optional real-time streaming (logs, console output).
>
> **NOT required for**: Status updates, heartbeats, metrics (those flow via standard requests or realtime DB sync).

### What Migrates to Supabase Realtime

✅ **Agent state updates** (status, heartbeats, metadata)
✅ **Run lifecycle events** (start, complete, iteration updates)
✅ **Requirements changes** (status transitions, validation results)
✅ **Artifact creation** (files, screenshots, outputs)
✅ **Project metadata** (mode changes, configuration updates)

### What Stays as Custom WebSocket

🔒 **Agent console streaming** (high-frequency log output)
🔒 **Agent control signals** (start, stop, pause commands)
🔒 **Direct agent communication** (command/response patterns)

## Database Schema

### Core Tables

```sql
-- Organizations table (teams/workspaces)
CREATE TABLE organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL, -- URL-friendly identifier

  -- Personal vs team organizations
  is_personal BOOLEAN DEFAULT FALSE, -- TRUE for auto-created personal workspaces

  -- Billing & limits
  plan TEXT NOT NULL DEFAULT 'free', -- 'free', 'pro', 'enterprise'
  agent_limit INTEGER DEFAULT 1,
  storage_limit_gb INTEGER DEFAULT 5,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_organizations_slug ON organizations(slug);
CREATE INDEX idx_organizations_personal ON organizations(is_personal) WHERE is_personal = TRUE;

-- Organization members (team access control)
CREATE TABLE organization_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Role-based access
  role TEXT NOT NULL DEFAULT 'member', -- 'owner', 'admin', 'member', 'viewer'

  -- Timestamps
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  invited_by UUID REFERENCES auth.users(id),

  UNIQUE(organization_id, user_id)
);

CREATE INDEX idx_org_members_user ON organization_members(user_id);
CREATE INDEX idx_org_members_org ON organization_members(organization_id);

-- Projects table (belongs to organizations)
CREATE TABLE projects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

  -- Project identity
  name TEXT NOT NULL,
  slug TEXT NOT NULL,
  description TEXT,

  -- Paths & configuration
  root_path TEXT NOT NULL,
  config JSONB,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID REFERENCES auth.users(id),

  UNIQUE(organization_id, slug)
);

CREATE INDEX idx_projects_org ON projects(organization_id);

-- Agents table (replaces file-based agent registry)
CREATE TABLE agents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Agent identity
  agent_id TEXT NOT NULL, -- PowerShell process ID or container ID
  agent_type TEXT NOT NULL, -- 'local', 'cloud'
  display_name TEXT,

  -- Current state
  status TEXT NOT NULL DEFAULT 'idle', -- 'idle', 'running', 'paused', 'stopped', 'error'
  mode TEXT, -- 'auto', 'ask', 'demo'
  current_requirement_id TEXT,

  -- Timestamps
  registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_heartbeat TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at TIMESTAMPTZ,
  stopped_at TIMESTAMPTZ,

  -- Metadata
  version TEXT,
  host TEXT,
  environment JSONB, -- Python version, OS, etc.

  UNIQUE(project_id, agent_id)
);

CREATE INDEX idx_agents_project ON agents(project_id);
CREATE INDEX idx_agents_status ON agents(status);
CREATE INDEX idx_agents_heartbeat ON agents(last_heartbeat);

-- Agent states table (historical state tracking)
CREATE TABLE agent_states (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id UUID NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- State snapshot
  status TEXT NOT NULL,
  mode TEXT,
  current_requirement_id TEXT,
  iteration_count INTEGER DEFAULT 0,
  backpressure_count INTEGER DEFAULT 0,

  -- Error tracking
  error_message TEXT,
  error_type TEXT,

  -- Timing
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  duration_ms INTEGER, -- Time in this state

  -- Metadata
  metadata JSONB -- Additional context
);

CREATE INDEX idx_agent_states_agent ON agent_states(agent_id, timestamp DESC);
CREATE INDEX idx_agent_states_project ON agent_states(project_id, timestamp DESC);

-- Runs table (replaces runs/ directory structure)
CREATE TABLE runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  agent_id UUID REFERENCES agents(id) ON DELETE SET NULL,

  -- Run identity
  run_id TEXT NOT NULL, -- Timestamp-based ID (e.g., "2026-01-30T14-30-00")
  requirement_id TEXT NOT NULL,

  -- Status
  status TEXT NOT NULL DEFAULT 'running', -- 'running', 'completed', 'failed', 'blocked'
  mode TEXT NOT NULL, -- 'auto', 'ask', 'demo'

  -- Metrics
  iteration_count INTEGER DEFAULT 0,
  backpressure_count INTEGER DEFAULT 0,
  validation_failures INTEGER DEFAULT 0,

  -- Timestamps
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  duration_ms INTEGER,

  -- Results
  exit_code INTEGER,
  error_message TEXT,

  -- Metadata
  metadata JSONB, -- Config, environment, etc.

  UNIQUE(project_id, run_id)
);

CREATE INDEX idx_runs_project ON runs(project_id, started_at DESC);
CREATE INDEX idx_runs_requirement ON runs(requirement_id);
CREATE INDEX idx_runs_agent ON runs(agent_id);
CREATE INDEX idx_runs_status ON runs(status);

-- Run artifacts table (files, screenshots, outputs)
CREATE TABLE run_artifacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Artifact identity
  artifact_type TEXT NOT NULL, -- 'file', 'screenshot', 'log', 'output'
  file_name TEXT NOT NULL,
  file_path TEXT NOT NULL, -- Relative to run directory

  -- Storage
  storage_path TEXT, -- Supabase Storage path
  storage_bucket TEXT DEFAULT 'run-artifacts',
  content_type TEXT,
  size_bytes BIGINT,

  -- Metadata
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  metadata JSONB -- Additional context
);

CREATE INDEX idx_artifacts_run ON run_artifacts(run_id, created_at DESC);
CREATE INDEX idx_artifacts_project ON run_artifacts(project_id, created_at DESC);
CREATE INDEX idx_artifacts_type ON run_artifacts(artifact_type);

-- Requirements table (synced from specs/)
CREATE TABLE requirements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Requirement identity
  requirement_id TEXT NOT NULL, -- e.g., "S-0001"
  title TEXT NOT NULL,
  description TEXT,

  -- Status
  status TEXT NOT NULL DEFAULT 'planned', -- 'planned', 'in_progress', 'completed', 'blocked'
  priority INTEGER DEFAULT 0,

  -- Relationships
  depends_on TEXT[], -- Array of requirement IDs
  blocks TEXT[], -- Array of requirement IDs

  -- Validation
  acceptance_criteria JSONB,
  validation_status TEXT, -- 'pending', 'passed', 'failed'
  last_validated_at TIMESTAMPTZ,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,

  -- Metadata
  tags TEXT[],
  metadata JSONB,

  UNIQUE(project_id, requirement_id)
);

CREATE INDEX idx_requirements_project ON requirements(project_id, priority DESC);
CREATE INDEX idx_requirements_status ON requirements(status);
CREATE INDEX idx_requirements_tags ON requirements USING GIN(tags);
```

### Row Level Security (RLS) Policies

```sql
-- Enable RLS on all tables
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_states ENABLE ROW LEVEL SECURITY;
ALTER TABLE runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE run_artifacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE requirements ENABLE ROW LEVEL SECURITY;

-- Helper function to check organization membership
CREATE OR REPLACE FUNCTION is_org_member(org_id UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM organization_members
    WHERE organization_id = org_id
    AND user_id = auth.uid()
  );
$$ LANGUAGE sql SECURITY DEFINER;

-- Helper function to check organization role
CREATE OR REPLACE FUNCTION has_org_role(org_id UUID, required_role TEXT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM organization_members
    WHERE organization_id = org_id
    AND user_id = auth.uid()
    AND (
      CASE required_role
        WHEN 'viewer' THEN role IN ('viewer', 'member', 'admin', 'owner')
        WHEN 'member' THEN role IN ('member', 'admin', 'owner')
        WHEN 'admin' THEN role IN ('admin', 'owner')
        WHEN 'owner' THEN role = 'owner'
      END
    )
  );
$$ LANGUAGE sql SECURITY DEFINER;

-- Organizations policies
CREATE POLICY "Users can view organizations they belong to"
  ON organizations FOR SELECT
  USING (is_org_member(id));

CREATE POLICY "Only owners can update organizations"
  ON organizations FOR UPDATE
  USING (has_org_role(id, 'owner'))
  WITH CHECK (has_org_role(id, 'owner'));

CREATE POLICY "Only owners can delete organizations"
  ON organizations FOR DELETE
  USING (has_org_role(id, 'owner'));

-- Organization members policies
CREATE POLICY "Users can view members of their organizations"
  ON organization_members FOR SELECT
  USING (is_org_member(organization_id));

CREATE POLICY "Admins can add members"
  ON organization_members FOR INSERT
  WITH CHECK (has_org_role(organization_id, 'admin'));

CREATE POLICY "Admins can update members"
  ON organization_members FOR UPDATE
  USING (has_org_role(organization_id, 'admin'))
  WITH CHECK (has_org_role(organization_id, 'admin'));

CREATE POLICY "Admins can remove members"
  ON organization_members FOR DELETE
  USING (has_org_role(organization_id, 'admin'));

-- Projects policies
CREATE POLICY "Users can view projects in their organizations"
  ON projects FOR SELECT
  USING (is_org_member(organization_id));

CREATE POLICY "Members can create projects"
  ON projects FOR INSERT
  WITH CHECK (has_org_role(organization_id, 'member'));

CREATE POLICY "Members can update projects"
  ON projects FOR UPDATE
  USING (is_org_member(organization_id))
  WITH CHECK (is_org_member(organization_id));

CREATE POLICY "Admins can delete projects"
  ON projects FOR DELETE
  USING (has_org_role(organization_id, 'admin'));

-- Agents policies (access via project -> organization membership)
CREATE POLICY "Users can view agents in their organization's projects"
  ON agents FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = agents.project_id
      AND is_org_member(projects.organization_id)
    )
  );

CREATE POLICY "Users can insert agents in their organization's projects"
  ON agents FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = project_id
      AND is_org_member(projects.organization_id)
    )
  );

CREATE POLICY "Users can update agents in their organization's projects"
  ON agents FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = agents.project_id
      AND is_org_member(projects.organization_id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = agents.project_id
      AND is_org_member(projects.organization_id)
    )
  );

CREATE POLICY "Users can delete agents in their organization's projects"
  ON agents FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = agents.project_id
      AND is_org_member(projects.organization_id)
    )
  );

-- Agent states policies
CREATE POLICY "Users can view agent states in their organization's projects"
  ON agent_states FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = agent_states.project_id
      AND is_org_member(projects.organization_id)
    )
  );

CREATE POLICY "Users can insert agent states in their organization's projects"
  ON agent_states FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = project_id
      AND is_org_member(projects.organization_id)
    )
  );

-- Runs policies
CREATE POLICY "Users can view runs in their organization's projects"
  ON runs FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = runs.project_id
      AND is_org_member(projects.organization_id)
    )
  );

CREATE POLICY "Users can insert runs in their organization's projects"
  ON runs FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = project_id
      AND is_org_member(projects.organization_id)
    )
  );

CREATE POLICY "Users can update runs in their organization's projects"
  ON runs FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = runs.project_id
      AND is_org_member(projects.organization_id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = runs.project_id
      AND is_org_member(projects.organization_id)
    )
  );

-- Run artifacts policies
CREATE POLICY "Users can view run artifacts in their organization's projects"
  ON run_artifacts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = run_artifacts.project_id
      AND is_org_member(projects.organization_id)
    )
  );

CREATE POLICY "Users can insert run artifacts in their organization's projects"
  ON run_artifacts FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = project_id
      AND is_org_member(projects.organization_id)
    )
  );

-- Requirements policies
CREATE POLICY "Users can view requirements in their organization's projects"
  ON requirements FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = requirements.project_id
      AND is_org_member(projects.organization_id)
    )
  );

CREATE POLICY "Users can manage requirements in their organization's projects"
  ON requirements FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = requirements.project_id
      AND is_org_member(projects.organization_id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM projects
      WHERE projects.id = requirements.project_id
      AND is_org_member(projects.organization_id)
    )
  );
```

### User Signup & Personal Organizations

Every user automatically gets a personal organization when they sign up. This provides:

- **Private workspace** for individual projects
- **Consistent data model** - all projects belong to organizations
- **Easy upgrade path** - invite members to convert personal → team
- **Simple billing** - each organization has its own plan

**Automatic Personal Organization Creation**:

```sql
-- Trigger function to create personal organization on user signup
CREATE OR REPLACE FUNCTION create_personal_organization()
RETURNS TRIGGER AS $$
DECLARE
  new_org_id UUID;
BEGIN
  -- Create personal organization with user's email as base name
  INSERT INTO organizations (name, slug, is_personal, plan)
  VALUES (
    COALESCE(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)) || '''s Workspace',
    'personal-' || NEW.id,
    TRUE,
    'free'
  )
  RETURNING id INTO new_org_id;

  -- Make user the owner of their personal organization
  INSERT INTO organization_members (organization_id, user_id, role)
  VALUES (new_org_id, NEW.id, 'owner');

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on auth.users table
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION create_personal_organization();
```

**Organization Model**:

- **Personal Organizations** (`is_personal = TRUE`):
  - One per user (auto-created)
  - Named "{User}'s Workspace"
  - Slug: `personal-{user_id}`
  - Cannot invite members (or can with upgrade prompt)
  - Default free plan

- **Team Organizations** (`is_personal = FALSE`):
  - Manually created by users
  - Can invite multiple members
  - Role-based access (owner, admin, member, viewer)
  - Custom billing per organization

**User Flow**:

1. **User signs up** → Personal organization auto-created → User is owner
2. **User creates project** → Project belongs to personal organization
3. **User creates team** → New organization created → User is owner → Invite team members
4. **User joins team** → Added to organization_members → Gains access to team's projects
5. **User switches contexts** → UI dropdown to select active organization

**Benefits**:

- ✅ Users can have private projects AND collaborate on team projects
- ✅ No special "personal account" vs "organization" logic - everything is an org
- ✅ Billing is per-organization (personal free tier, team paid plans)
- ✅ Easy to convert personal project to team project (just change organization_id)
- ✅ Matches familiar patterns (GitHub, Vercel, Linear, etc.)

## Migration Phases

### Phase 1: Database Schema Setup (2-3 days)

**Goal**: Establish Supabase database structure without breaking existing functionality

**Tasks**:

1. Create Supabase project and configure connection
2. Run SQL migrations to create all tables
3. Set up RLS policies for multi-tenancy
4. Create database indexes for performance
5. Configure Supabase Storage bucket for run artifacts
6. Test database connectivity from FastAPI backend

**Deliverables**:

- Supabase project configured
- All tables created with RLS enabled
- Storage bucket created
- Connection credentials in environment variables

**Testing**:

- Verify RLS policies block unauthorized access
- Test CRUD operations via SQL console
- Validate indexes with EXPLAIN ANALYZE
- Test personal organization auto-creation on signup
- Verify users can create and join team organizations
- Test organization switching and access isolation

### Phase 2: Backend Database Integration (4-5 days)

**Goal**: Replace file-based storage with Supabase database operations

**Tasks**:

1. **Create Supabase Client Module** (`app/backend/database/supabase_client.py`):

```python
from supabase import create_client, Client
from app.backend.config import settings

class SupabaseClient:
    _instance: Client = None

    @classmethod
    def get_client(cls) -> Client:
        if cls._instance is None:
            cls._instance = create_client(
                settings.SUPABASE_URL,
                settings.SUPABASE_KEY
            )
        return cls._instance
```

2. **Create Database Writer Module** (`app/backend/database/writers.py`):

```python
from supabase import Client
from typing import Dict, Any, Optional
from datetime import datetime
from app.backend.database.supabase_client import SupabaseClient

class AgentWriter:
    def __init__(self, supabase: Client = None):
        self.supabase = supabase or SupabaseClient.get_client()

    async def upsert_agent(
        self,
        project_id: str,
        agent_id: str,
        status: str,
        mode: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Upsert agent record in database"""
        data = {
            "project_id": project_id,
            "agent_id": agent_id,
            "status": status,
            "mode": mode,
            "last_heartbeat": datetime.utcnow().isoformat(),
            "metadata": metadata or {}
        }

        result = self.supabase.table("agents").upsert(
            data,
            on_conflict="project_id,agent_id"
        ).execute()

        return result.data[0] if result.data else None

    async def update_agent_heartbeat(self, agent_id: str) -> None:
        """Update agent last_heartbeat timestamp"""
        self.supabase.table("agents").update({
            "last_heartbeat": datetime.utcnow().isoformat()
        }).eq("agent_id", agent_id).execute()

    async def create_agent_state(
        self,
        agent_id: str,
        project_id: str,
        status: str,
        mode: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Create agent state snapshot"""
        data = {
            "agent_id": agent_id,
            "project_id": project_id,
            "status": status,
            "mode": mode,
            "metadata": metadata or {}
        }

        result = self.supabase.table("agent_states").insert(data).execute()
        return result.data[0] if result.data else None

class RunWriter:
    def __init__(self, supabase: Client = None):
        self.supabase = supabase or SupabaseClient.get_client()

    async def create_run(
        self,
        project_id: str,
        run_id: str,
        requirement_id: str,
        mode: str,
        agent_id: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Create new run record"""
        data = {
            "project_id": project_id,
            "run_id": run_id,
            "requirement_id": requirement_id,
            "mode": mode,
            "agent_id": agent_id,
            "status": "running",
            "metadata": metadata or {}
        }

        result = self.supabase.table("runs").insert(data).execute()
        return result.data[0] if result.data else None

    async def update_run_status(
        self,
        run_id: str,
        status: str,
        exit_code: Optional[int] = None,
        error_message: Optional[str] = None
    ) -> None:
        """Update run status and completion data"""
        data = {"status": status}

        if status in ["completed", "failed", "blocked"]:
            data["completed_at"] = datetime.utcnow().isoformat()

        if exit_code is not None:
            data["exit_code"] = exit_code

        if error_message:
            data["error_message"] = error_message

        self.supabase.table("runs").update(data).eq("run_id", run_id).execute()

    async def create_artifact(
        self,
        run_id: str,
        project_id: str,
        artifact_type: str,
        file_name: str,
        file_path: str,
        storage_path: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Create run artifact record"""
        data = {
            "run_id": run_id,
            "project_id": project_id,
            "artifact_type": artifact_type,
            "file_name": file_name,
            "file_path": file_path,
            "storage_path": storage_path,
            "metadata": metadata or {}
        }

        result = self.supabase.table("run_artifacts").insert(data).execute()
        return result.data[0] if result.data else None
```

3. **Add Organization Management Module** (`app/backend/database/organizations.py`):

```python
from supabase import Client
from typing import Dict, Any, List, Optional
from app.backend.database.supabase_client import SupabaseClient

class OrganizationManager:
    def __init__(self, supabase: Client = None):
        self.supabase = supabase or SupabaseClient.get_client()

    async def get_user_organizations(self, user_id: str) -> List[Dict[str, Any]]:
        """Get all organizations a user is a member of"""
        result = self.supabase.table("organization_members").select(
            "*, organizations(*)"
        ).eq("user_id", user_id).execute()

        return [member["organizations"] for member in result.data]

    async def get_personal_organization(self, user_id: str) -> Optional[Dict[str, Any]]:
        """Get user's personal organization"""
        result = self.supabase.table("organization_members").select(
            "*, organizations!inner(*)"
        ).eq("user_id", user_id).eq("organizations.is_personal", True).execute()

        return result.data[0]["organizations"] if result.data else None

    async def create_team_organization(
        self,
        user_id: str,
        name: str,
        slug: str
    ) -> Dict[str, Any]:
        """Create a new team organization"""
        # Create organization
        org_result = self.supabase.table("organizations").insert({
            "name": name,
            "slug": slug,
            "is_personal": False
        }).execute()

        org_id = org_result.data[0]["id"]

        # Add creator as owner
        self.supabase.table("organization_members").insert({
            "organization_id": org_id,
            "user_id": user_id,
            "role": "owner"
        }).execute()

        return org_result.data[0]

    async def invite_member(
        self,
        organization_id: str,
        user_email: str,
        role: str,
        invited_by: str
    ) -> Dict[str, Any]:
        """Invite a user to an organization"""
        # Look up user by email
        user_result = self.supabase.table("auth.users").select(
            "id"
        ).eq("email", user_email).execute()

        if not user_result.data:
            raise ValueError(f"User not found: {user_email}")

        user_id = user_result.data[0]["id"]

        # Add to organization
        result = self.supabase.table("organization_members").insert({
            "organization_id": organization_id,
            "user_id": user_id,
            "role": role,
            "invited_by": invited_by
        }).execute()

        return result.data[0]
```

4. **Modify Agent Registration** (`app/backend/routers/agents.py`):

```python
from app.backend.database.writers import AgentWriter, RunWriter

agent_writer = AgentWriter()
run_writer = RunWriter()

@router.post("/register")
async def register_agent(
    project_id: str,
    agent_id: str,
    metadata: Optional[Dict[str, Any]] = None
):
    # Write to database
    await agent_writer.upsert_agent(
        project_id=project_id,
        agent_id=agent_id,
        status="registered",
        metadata=metadata
    )

    return {"status": "registered"}

@router.post("/{agent_id}/heartbeat")
async def agent_heartbeat(agent_id: str, project_id: str):
    # Update database heartbeat
    await agent_writer.update_agent_heartbeat(agent_id)

    return {"status": "ok"}
```

5. **Add Organization Endpoints** (`app/backend/routers/organizations.py`):

```python
from fastapi import APIRouter, Depends, HTTPException
from app.backend.database.organizations import OrganizationManager
from app.backend.auth import get_current_user

router = APIRouter(prefix="/api/organizations", tags=["organizations"])
org_manager = OrganizationManager()

@router.get("/")
async def list_organizations(user_id: str = Depends(get_current_user)):
    """List all organizations the user is a member of"""
    return await org_manager.get_user_organizations(user_id)

@router.get("/personal")
async def get_personal_organization(user_id: str = Depends(get_current_user)):
    """Get user's personal organization"""
    org = await org_manager.get_personal_organization(user_id)
    if not org:
        raise HTTPException(404, "Personal organization not found")
    return org

@router.post("/")
async def create_organization(
    name: str,
    slug: str,
    user_id: str = Depends(get_current_user)
):
    """Create a new team organization"""
    return await org_manager.create_team_organization(user_id, name, slug)

@router.post("/{org_id}/members")
async def invite_member(
    org_id: str,
    email: str,
    role: str,
    user_id: str = Depends(get_current_user)
):
    """Invite a user to the organization"""
    return await org_manager.invite_member(org_id, email, role, user_id)
```

6. **Deprecate State WebSocket** (`app/backend/routers/websocket.py`):

```python
# Note: /ws/projects/{project_id} endpoint will be removed
# State updates now come from Supabase Realtime subscriptions
# Only console streaming WebSocket remains at /api/agents/{agent_id}/console
```

**Deliverables**:

- Supabase client module with connection management
- Database writer modules for agents, runs, artifacts, requirements
- Organization management module with team/personal org support
- Organization API endpoints (list, create, invite members)
- Updated agent registration/heartbeat endpoints to use database
- Removed file-based state WebSocket endpoint
- Environment variables for Supabase configuration

**Testing**:

- Test database writes for agent registration and heartbeats
- Verify RLS policies work with real JWT tokens
- Test organization creation and member invitations
- Verify personal organization is auto-created on signup
- Test access isolation between organizations
- Load test database writes with multiple concurrent agents
- Verify agent state transitions persist correctly

### Phase 3: Frontend Migration (3-4 days)

**Goal**: Replace WebSocket state updates with Supabase Realtime subscriptions

**Tasks**:

1. **Create Supabase Realtime Hook** (`app/frontend/hooks/useSupabaseRealtime.ts`):

```typescript
import { useEffect, useState } from "react";
import { createClient, RealtimeChannel } from "@supabase/supabase-js";

interface UseSupabaseRealtimeOptions {
  projectId: string;
  table: "agents" | "runs" | "requirements";
  onInsert?: (record: any) => void;
  onUpdate?: (record: any) => void;
  onDelete?: (record: any) => void;
}

export function useSupabaseRealtime({
  projectId,
  table,
  onInsert,
  onUpdate,
  onDelete,
}: UseSupabaseRealtimeOptions) {
  const [channel, setChannel] = useState<RealtimeChannel | null>(null);
  const [status, setStatus] = useState<
    "connecting" | "connected" | "disconnected"
  >("connecting");

  useEffect(() => {
    const supabase = createClient(
      process.env.REACT_APP_SUPABASE_URL!,
      process.env.REACT_APP_SUPABASE_ANON_KEY!,
    );

    const realtimeChannel = supabase
      .channel(`${table}:${projectId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: table,
          filter: `project_id=eq.${projectId}`,
        },
        (payload) => {
          console.log(`[${table}] INSERT:`, payload.new);
          onInsert?.(payload.new);
        },
      )
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: table,
          filter: `project_id=eq.${projectId}`,
        },
        (payload) => {
          console.log(`[${table}] UPDATE:`, payload.new);
          onUpdate?.(payload.new);
        },
      )
      .on(
        "postgres_changes",
        {
          event: "DELETE",
          schema: "public",
          table: table,
          filter: `project_id=eq.${projectId}`,
        },
        (payload) => {
          console.log(`[${table}] DELETE:`, payload.old);
          onDelete?.(payload.old);
        },
      )
      .subscribe((status) => {
        console.log(`[${table}] Subscription status:`, status);
        if (status === "SUBSCRIBED") {
          setStatus("connected");
        } else if (status === "CLOSED") {
          setStatus("disconnected");
        }
      });

    setChannel(realtimeChannel);

    return () => {
      realtimeChannel.unsubscribe();
    };
  }, [projectId, table]);

  return { status, channel };
}
```

2. **Create Supabase Project State Hook** (`app/frontend/hooks/useProjectState.ts`):

```typescript
import { useState } from "react";
import { useSupabaseRealtime } from "./useSupabaseRealtime";

interface ProjectState {
  mode: string;
  status: string;
  currentRequirementId?: string;
  iterationCount: number;
  requirements: any[];
}

export function useProjectState(projectId: string) {
  const [state, setState] = useState<ProjectState>({
    mode: "idle",
    status: "idle",
    iterationCount: 0,
    requirements: [],
  });

  // Use Supabase Realtime for all state updates
  const { status: agentStatus } = useSupabaseRealtime({
    projectId,
    table: "agents",
    onUpdate: (agent) => {
      setState((prev) => ({
        ...prev,
        mode: agent.mode,
        status: agent.status,
        currentRequirementId: agent.current_requirement_id,
      }));
    },
  });

  const { status: reqStatus } = useSupabaseRealtime({
    projectId,
    table: "requirements",
    onInsert: (req) => {
      setState((prev) => ({
        ...prev,
        requirements: [...prev.requirements, req],
      }));
    },
    onUpdate: (req) => {
      setState((prev) => ({
        ...prev,
        requirements: prev.requirements.map((r) => (r.id === req.id ? req : r)),
      }));
    },
  });

  return {
    state,
    isConnected: agentStatus === "connected",
  };
}
```

3. **Create Organization Context** (`app/frontend/contexts/OrganizationContext.tsx`):

```typescript
import { createContext, useContext, useState, useEffect } from 'react';
import { useSupabase } from './SupabaseContext';

interface Organization {
  id: string;
  name: string;
  slug: string;
  is_personal: boolean;
  plan: string;
}

interface OrganizationContextType {
  organizations: Organization[];
  currentOrganization: Organization | null;
  switchOrganization: (orgId: string) => void;
  loading: boolean;
}

const OrganizationContext = createContext<OrganizationContextType | null>(null);

export function OrganizationProvider({ children }: { children: React.ReactNode }) {
  const supabase = useSupabase();
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [currentOrganization, setCurrentOrganization] = useState<Organization | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadOrganizations();
  }, []);

  async function loadOrganizations() {
    const { data, error } = await supabase
      .from('organization_members')
      .select('*, organizations(*)')
      .eq('user_id', (await supabase.auth.getUser()).data.user?.id);

    if (!error && data) {
      const orgs = data.map(m => m.organizations);
      setOrganizations(orgs);

      // Default to personal org or first org
      const personal = orgs.find(o => o.is_personal);
      setCurrentOrganization(personal || orgs[0]);
    }

    setLoading(false);
  }

  function switchOrganization(orgId: string) {
    const org = organizations.find(o => o.id === orgId);
    if (org) {
      setCurrentOrganization(org);
      localStorage.setItem('currentOrganizationId', orgId);
    }
  }

  return (
    <OrganizationContext.Provider value={{
      organizations,
      currentOrganization,
      switchOrganization,
      loading
    }}>
      {children}
    </OrganizationContext.Provider>
  );
}

export function useOrganization() {
  const context = useContext(OrganizationContext);
  if (!context) {
    throw new Error('useOrganization must be used within OrganizationProvider');
  }
  return context;
}
```

4. **Add Organization Switcher Component** (`app/frontend/components/OrganizationSwitcher.tsx`):

```typescript
import { useOrganization } from '../contexts/OrganizationContext';

export function OrganizationSwitcher() {
  const { organizations, currentOrganization, switchOrganization } = useOrganization();

  return (
    <select
      value={currentOrganization?.id}
      onChange={(e) => switchOrganization(e.target.value)}
      className="org-switcher"
    >
      {organizations.map(org => (
        <option key={org.id} value={org.id}>
          {org.is_personal ? '👤 ' : '👥 '}{org.name}
        </option>
      ))}
    </select>
  );
}
```

5. **Keep Console WebSocket Unchanged** (`app/frontend/hooks/useConsoleWebSocket.ts`):

```typescript
// This stays exactly as-is - console streaming always uses custom WebSocket
// No changes needed - already correctly implemented
```

6. **Update Components** (`app/frontend/components/AgentDashboard.tsx`):

```typescript
import { useProjectState } from "../hooks/useProjectState";
import { useOrganization } from "../contexts/OrganizationContext";
import { OrganizationSwitcher } from "./OrganizationSwitcher";

export function AgentDashboard({ projectId }: { projectId: string }) {
  const { currentOrganization } = useOrganization();

  // Use Supabase Realtime for state updates
  const { state, isConnected } = useProjectState(projectId);

  // Console streaming ALWAYS uses WebSocket regardless of mode
  const { output } = useConsoleWebSocket(projectId);

  return (
    <div>
      <OrganizationSwitcher />
      {/* Rest of component logic unchanged... */}
    </div>
  );
}
```

**Deliverables**:

- Supabase Realtime hook for database subscriptions
- Supabase-based project state hook
- Organization context provider for multi-org support
- Organization switcher component
- Updated components using Realtime subscriptions and org context
- Console streaming remains WebSocket-based
- Environment variables for Supabase configuration

**Testing**:

- Test Supabase Realtime subscriptions for all state updates
- Verify console streaming WebSocket works correctly
- Test organization switching and context updates
- Verify personal vs team organization access
- Test real-time updates with multiple concurrent users in different organizations
- Load test with multiple simultaneous subscriptions
- Verify RLS policies isolate organization data correctly

### Phase 4: Integration & Production Readiness (3-4 days)

**Goal**: Complete end-to-end testing and deploy to production

**Tasks**:

1. **Environment Configuration**:

```bash
# .env.development
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
WEBSOCKET_URL=ws://localhost:8080  # For console streaming only

# .env.production
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
WEBSOCKET_URL=wss://api.yourapp.com  # For console streaming only
```

2. **Migration Scripts**:

- Create script to migrate existing file-based data to database
- One-time import of runs/ directory structure to runs table
- One-time import of requirements.json to requirements table
- One-time import of state.json to agents table

3. **Testing Checklist**:

- [ ] All database writes succeed with correct data
- [ ] RLS policies block unauthorized access
- [ ] WebSocket console streaming works correctly
- [ ] Frontend receives real-time updates via Supabase
- [ ] Multi-user isolation works (RLS validation)
- [ ] Load test: 10+ concurrent agents per project
- [ ] Load test: 100+ realtime subscribers
- [ ] Failover: Database connection retry logic works
- [ ] Failover: WebSocket reconnection works for console streaming

4. **Documentation Updates**:

- Update AGENTS.md with Supabase deployment instructions
- Update HOW_TO_USE.md with database setup steps
- Create DEPLOYMENT.md for production setup
- Document RLS policy management
- Document database backup/restore procedures
- Remove all references to file-based storage

5. **Monitoring & Observability**:

- Add Supabase connection health checks
- Add WebSocket connection metrics
- Add RLS policy audit logging
- Add database query performance monitoring

**Deliverables**:

- Fully functional cloud-native system
- Data migration scripts tested and executed
- Complete documentation
- Production deployment guide
- Monitoring dashboard

## Rollback Strategy

### If Migration Fails

1. **Phase 1 rollback**: Delete Supabase tables, revert schema
2. **Phase 2 rollback**: Revert backend to file-based storage (temporary)
3. **Phase 3 rollback**: Revert frontend to previous WebSocket implementation
4. **Phase 4 rollback**: Roll back production deployment

### Data Safety

- Keep file-based backup of all data before migration
- Test database writes extensively before deleting files
- Regular database backups to Supabase storage
- Point-in-time recovery enabled on Supabase

## Success Metrics

### Technical Metrics

- File system operations eliminated (100% database)
- Database query latency < 100ms (p95)
- Realtime subscription latency < 500ms
- Zero data loss during migration
- WebSocket used only for console streaming (90% reduction)

### User Experience Metrics

- No visible changes to existing workflows
- Faster state updates (database vs. filesystem polling)
- Multi-user collaboration enabled
- Mobile app support enabled (via Supabase)

## Timeline Summary

- **Phase 1**: 2-3 days (database setup)
- **Phase 2**: 4-5 days (backend hybrid implementation)
- **Phase 3**: 3-4 days (frontend migration)
- **Phase 4**: 3-4 days (integration & testing)

**Total**: 12-16 days

## Next Steps

1. **Immediate**: Create Supabase project and run Phase 1 migrations
2. **Week 1**: Complete Phase 1 + Phase 2 (database + backend)
3. **Week 2**: Complete Phase 3 + Phase 4 (frontend + testing)
4. **Week 3**: Production deployment and monitoring

## References

- [CLOUD_ORCHESTRATION.md](CLOUD_ORCHESTRATION.md) - Architecture principles
- [PRODUCTION-TODO.md](../PRODUCTION-TODO.md) - Full production roadmap
- [Supabase Realtime Docs](https://supabase.com/docs/guides/realtime)
- [FastAPI WebSocket Guide](https://fastapi.tiangolo.com/advanced/websockets/)

