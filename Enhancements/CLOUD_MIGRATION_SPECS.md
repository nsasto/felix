# Cloud Migration Specification Breakdown

## Overview

This document provides a complete breakdown of the cloud migration work into 23 developer-ready specifications (S-0031 through S-0053). Each spec represents an atomic unit of work that can be completed in 1-3 days, has clear acceptance criteria, and explicit dependencies.

**Migration Philosophy:**

- Schema matches Supabase from day one (mechanical migration later)
- Core orchestration first, cloud features second
- Each phase is additive (no rewrites)
- Always shippable at the end of each phase

**Total Timeline:** 4-5 weeks (130-160 hours)

---

## Specification List

### Phase -1: Legacy Code Cleanup (1 day, 16-22 hours)

**S-0031: Remove File-Based WebSocket Infrastructure** (4-6 hours)

- Delete websocket.py (537 lines), useProjectWebSocket.ts
- Remove router registration, preserve console streaming
- Dependencies: None
- Priority: Critical

**S-0032: Remove Backend File Operations** (6-8 hours)

- Clean agents.py, agent_config.py, routes.py, storage.py, projects.py, main.py
- Remove state.json/requirements.json/agents.json access
- Dependencies: S-0031
- Priority: Critical

**S-0033: Remove Frontend Polling Mechanisms** (4-5 hours)

- Remove polling from Main.tsx (~1482-1740), AgentControl.tsx (71-93)
- Preserve LiveConsolePanel (777-1219)
- Dependencies: S-0031
- Priority: Critical

**S-0034: Cleanup Verification and Documentation** (2-3 hours)

- Run verification checks, update tests, commit with backup branch
- Dependencies: S-0031, S-0032, S-0033
- Priority: Critical

---

### Phase 0: Local Postgres Setup (2-3 days, 22-30 hours)

**S-0035: Database Schema and Migrations Setup** (6-8 hours)

- Create felix database, migrations/ directory
- Create 001_initial_schema.sql with 8 tables (organizations, projects, agents, agent_states, runs, run_artifacts, requirements, organization_members)
- Seed dev organization and project
- Dependencies: S-0034
- Priority: Critical

**S-0036: Backend Database Integration Layer** (6-8 hours)

- Install dependencies (asyncpg, sqlalchemy, python-dotenv)
- Create config.py, database/db.py, auth.py
- Create .env file, update main.py with startup event
- Dependencies: S-0035
- Priority: Critical

**S-0037: Database Writers Implementation** (6-8 hours)

- Create database/writers.py with AgentWriter, RunWriter classes
- Implement all CRUD methods (upsert_agent, update_heartbeat, update_status, create_run, update_run_status, create_artifact)
- Dependencies: S-0036
- Priority: High

**S-0038: Agent Registration and Heartbeat API** (4-6 hours)

- Add endpoints: POST /api/agents/register, POST /api/agents/{agent_id}/heartbeat, POST /api/agents/{agent_id}/status, GET /api/agents/
- Test with curl
- Dependencies: S-0037
- Priority: High

---

### Phase 1: Core Orchestration (3-4 days, 22-30 hours)

**S-0039: Control WebSocket Infrastructure** (6-8 hours)

- Create websocket/control.py with ControlConnectionManager
- Add WebSocket endpoint for agent control /{agent_id}/control
- Handle bidirectional communication for START/STOP commands
- Dependencies: S-0038
- Priority: High

**S-0040: Run Control API Endpoints** (6-8 hours)

- POST /api/agents/runs (create run and send START command)
- POST /api/agents/runs/{run_id}/stop (send STOP command)
- GET /api/agents/runs (list recent runs)
- GET /api/agents/runs/{run_id} (get run details)
- Dependencies: S-0039
- Priority: High

**S-0041: Console Streaming WebSocket** (4-6 hours)

- Add /{agent_id}/console WebSocket endpoint
- Implement log file tailing (runs/{run_id}/output.log)
- Stream new content to connected clients
- Dependencies: S-0040
- Priority: Medium

**S-0042: Frontend API Client and Dashboard** (6-8 hours)

- Create api/client.ts with functions (registerAgent, listAgents, createRun, listRuns)
- Create components/AgentDashboard.tsx with polling (temporary)
- Wire up in main App component
- Dependencies: S-0041
- Priority: High

---

### Phase 2: Supabase Migration (3-4 days, 22-29 hours)

**S-0043: Supabase Project Setup and Schema Migration** (4-6 hours)

- Create Supabase project (felix-production)
- Apply 001_initial_schema.sql to Supabase database
- Update .env with Supabase credentials (URL, anon key, service key, DATABASE_URL)
- Test connection and verify Phase 1 functionality still works
- Dependencies: S-0042
- Priority: Critical

**S-0044: Row-Level Security (RLS) Policies** (8-10 hours)

- Create 002_enable_rls.sql migration
- Implement helper functions (is_org_member, has_org_role)
- Enable RLS on all 8 tables
- Create policies for SELECT/INSERT/UPDATE/DELETE per table
- Create organization_members table, seed dev user membership
- Dependencies: S-0043
- Priority: Critical

**S-0045: JWT Authentication Integration** (6-8 hours)

- Install python-jose[cryptography]
- Update auth.py to decode Supabase JWT tokens
- Extract user_id from token payload
- Update endpoints to require JWT header
- Configure AUTH_MODE=enabled in .env
- Dependencies: S-0044
- Priority: High

**S-0046: Personal Organization Auto-Creation** (4-5 hours)

- Create 003_personal_org_trigger.sql migration
- Implement create_personal_organization() trigger function
- Create on_auth_user_created trigger on auth.users
- Test with new user signup
- Dependencies: S-0045
- Priority: High

---

### Phase 3: Realtime Subscriptions (3-4 days, 18-24 hours)

**S-0047: Frontend Supabase Client and Realtime Hooks** (6-8 hours)

- Install @supabase/supabase-js in frontend
- Create lib/supabase.ts client configuration
- Create hooks/useSupabaseRealtime.ts for subscribing to postgres_changes
- Handle INSERT/UPDATE/DELETE events with proper cleanup
- Dependencies: S-0046
- Priority: High

**S-0048: Project State Management with Realtime** (6-8 hours)

- Create hooks/useProjectState.ts
- Subscribe to agents, runs, requirements tables
- Maintain synchronized state in React
- Update AgentDashboard to use useProjectState
- Remove all polling intervals
- Dependencies: S-0047
- Priority: High

**S-0049: Organization Context and Switcher** (6-8 hours)

- Create contexts/OrganizationContext.tsx (load orgs, track current, switch)
- Create components/OrganizationSwitcher.tsx (dropdown selector)
- Wire into App component
- Persist selection to localStorage
- Dependencies: S-0047
- Priority: Medium

---

### Phase 4: Production Hardening (3-4 days, 24-32 hours)

**S-0050: Data Migration Script** (4-6 hours)

- Create scripts/migrate_file_data.py
- Scan runs/ directory, read state.json, insert into database
- Handle errors gracefully, report progress
- Test on development data
- Dependencies: S-0049
- Priority: High

**S-0051: Monitoring, Logging, and Health Checks** (4-6 hours)

- Create logging_config.py with structured logging
- Update health endpoint to check database connectivity
- Create metrics endpoint (agent counts, active runs, performance stats)
- Configure log levels
- Dependencies: S-0050
- Priority: Medium

**S-0052: Docker Containerization and Deployment** (8-10 hours)

- Create app/backend/Dockerfile (Python 3.11, install dependencies, expose 8080)
- Test Docker build and run locally
- Deploy backend to Railway
- Deploy frontend to Vercel
- Configure environment variables
- Dependencies: S-0051
- Priority: High

**S-0053: Production Testing and Validation** (8-10 hours)

- Test agent registration in production
- Verify RLS isolation with 2+ test users
- Test realtime subscriptions (sub-500ms latency)
- Test organization switching
- Load test: 10 concurrent agents
- Failover test: disconnect/reconnect scenarios
- Dependencies: S-0052
- Priority: Critical

---

## Dependency Graph

```
Phase -1 (Cleanup):
S-0031 → S-0032, S-0033
S-0032, S-0033 → S-0034

Phase 0 (Local Postgres):
S-0034 → S-0035 → S-0036 → S-0037 → S-0038

Phase 1 (Core Orchestration):
S-0038 → S-0039 → S-0040 → S-0041 → S-0042

Phase 2 (Supabase Migration):
S-0042 → S-0043 → S-0044 → S-0045 → S-0046

Phase 3 (Realtime):
S-0046 → S-0047 → S-0048, S-0049

Phase 4 (Production):
S-0049 → S-0050 → S-0051 → S-0052 → S-0053
```

---

## Statistics

**Total Specifications:** 23

**By Phase:**

- Phase -1 (Cleanup): 4 specs (16-22 hours)
- Phase 0 (Local Postgres): 4 specs (22-30 hours)
- Phase 1 (Core Orchestration): 4 specs (22-30 hours)
- Phase 2 (Supabase Migration): 4 specs (22-29 hours)
- Phase 3 (Realtime): 3 specs (18-24 hours)
- Phase 4 (Production): 4 specs (24-32 hours)

**Total Estimated Effort:** 130-160 hours (approximately 4-5 weeks with one developer)

**Priority Distribution:**

- Critical: 10 specs
- High: 10 specs
- Medium: 3 specs

---

## Implementation Guidelines

### For Each Spec:

1. **Read the full spec** before starting work
2. **Check dependencies** are complete (verify acceptance criteria of dependent specs)
3. **Create a feature branch** (e.g., `feature/S-0031-websocket-cleanup`)
4. **Implement all acceptance criteria** systematically
5. **Run validation commands** as specified
6. **Test manually** beyond automated checks
7. **Commit with descriptive message** referencing spec ID
8. **Mark spec as complete** in requirements.json
9. **Move to next spec** in dependency order

### Quality Checkpoints:

- **Code Review**: Each spec should be reviewed before merge
- **Testing**: All validation criteria must pass
- **Documentation**: Update inline comments and README as needed
- **Backward Compatibility**: Until Phase 3, frontend loses realtime updates (acceptable)
- **Data Safety**: Never delete runs/ directory until Phase 4 migration complete

---

## Success Metrics by Phase

**Phase -1:** ~1,700 lines removed, no file-based state references, console streaming preserved

**Phase 0:** Postgres database with 8 tables, agent registration working, all data persists

**Phase 1:** Agents register via API, WebSocket commands work, runs tracked, frontend shows status

**Phase 2:** Supabase connected, JWT auth enforced, RLS isolating data, personal orgs auto-created

**Phase 3:** No polling, sub-500ms realtime updates, organization switching works

**Phase 4:** All data migrated, deployed to production, monitoring active, load tests passed

---

## Reference

- **Detailed Migration Plan**: [CLOUD_MIGRATION_PLAN.md](CLOUD_MIGRATION_PLAN.md)
- **Architecture Documentation**: [CLOUD_MIGRATION.md](CLOUD_MIGRATION.md)
- **Requirements Tracking**: `.felix/requirements.json`

