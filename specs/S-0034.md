# S-0034: Cleanup Verification and Documentation

**Phase:** -1 (Legacy Code Cleanup)  
**Effort:** 2-3 hours  
**Priority:** Critical  
**Dependencies:** S-0031, S-0032, S-0033

---

## Narrative

This specification covers final verification that all legacy code has been successfully removed, the system still builds and runs, and proper documentation is updated. This is the final step in Phase -1 before moving to Phase 0 (Local Postgres Setup).

---

## Acceptance Criteria

### Code Verification

- [ ] Run comprehensive grep search for legacy patterns:
  - `grep -r "state.json" .` → No results in app/backend/routers/
  - `grep -r "requirements.json" .` → No results in app/backend/routers/
  - `grep -r "agents.json" .` → No results in app/backend/routers/
  - `grep -r "useProjectWebSocket" app/frontend/` → No results
  - `grep -rn "setInterval.*load" app/frontend/src/` → No polling intervals

- [ ] Verify deleted files no longer exist:
  - **app/backend/routers/websocket.py** → Does not exist
  - **app/frontend/src/hooks/useProjectWebSocket.ts** → Does not exist

- [ ] Verify preserved files still exist:
  - **..felix/state.json** → Still exists
  - **..felix/requirements.json** → Still exists
  - **..felix/agents.json** → Still exists
  - **runs/** directory → Still exists

### Build Verification

- [ ] Backend builds and starts: `cd app/backend && python main.py` (exit code 0, no import errors)
- [ ] Frontend builds: `cd app/frontend && npm run build` (exit code 0, no TypeScript errors)
- [ ] Frontend starts in dev mode: `cd app/frontend && npm run dev` (exit code 0)

### Functional Verification

- [ ] Backend health endpoint responds: `curl http://localhost:8080/health` (status 200)
- [ ] Backend API docs load: Open `http://localhost:8080/docs` in browser
- [ ] Frontend loads without console errors: Open `http://localhost:3000` in browser, check DevTools Console
- [ ] Console streaming works:
  - Start an agent: `.\felix-agent.ps1 C:\dev\Felix`
  - Open frontend console panel
  - Verify logs stream in real-time
  - Verify WebSocket connection in DevTools Network tab

### Test Suite Verification

- [ ] Backend tests pass: `powershell -File .\scripts\test-backend.ps1` (exit code 0 or 5 if no tests)
- [ ] Frontend tests pass: `powershell -File .\scripts\test-frontend.ps1` (exit code 0)
- [ ] No failing tests due to cleanup changes

### Git History

- [ ] Create backup branch: `git checkout -b backup/pre-phase-0`
- [ ] Commit Phase -1 changes: `git checkout main && git commit -m "Phase -1: Legacy Code Cleanup (S-0031 to S-0034)"`
- [ ] Tag the cleanup completion: `git tag v0.1-cleanup-complete`
- [ ] Push backup branch: `git push origin backup/pre-phase-0`

---

## Technical Notes

### Verification Commands

```powershell
# Comprehensive legacy code search
grep -r "state.json" app/backend/routers/
grep -r "requirements.json" app/backend/routers/
grep -r "agents.json" app/backend/routers/
grep -r "useProjectWebSocket" app/frontend/src/
grep -rn "setInterval" app/frontend/src/Main.tsx
grep -rn "setInterval" app/frontend/src/components/AgentControl.tsx

# File existence checks
Test-Path app/backend/routers/websocket.py  # Should be False
Test-Path app/frontend/src/hooks/useProjectWebSocket.ts  # Should be False
Test-Path ..felix/state.json  # Should be True
Test-Path ..felix/requirements.json  # Should be True
Test-Path ..felix/agents.json  # Should be True

# Build verification
cd app/backend; python main.py  # Start server
cd app/frontend; npm run build  # Build frontend
cd app/frontend; npm run dev    # Start dev server

# Test verification
powershell -File .\scripts\test-backend.ps1
powershell -File .\scripts\test-frontend.ps1

# Git operations
git checkout -b backup/pre-phase-0
git checkout main
git add .
git commit -m "Phase -1: Legacy Code Cleanup (S-0031 to S-0034)"
git tag v0.1-cleanup-complete
git push origin backup/pre-phase-0
git push origin main --tags
```

### Lines Removed Summary

**Backend:**

- websocket.py: 537 lines
- agents.py: ~200 lines
- agent_config.py: ~150 lines
- routes.py: ~100 lines
- storage.py: ~50 lines
- projects.py: ~200 lines
- main.py: ~50 lines
  **Backend Total:** ~1,287 lines

**Frontend:**

- useProjectWebSocket.ts: 289 lines
- Main.tsx: ~260 lines
- AgentControl.tsx: ~25 lines
- ProjectOverview.tsx: ~30 lines
- RequirementsList.tsx: ~20 lines
  **Frontend Total:** ~624 lines

**Grand Total:** ~1,911 lines removed

---

## Dependencies

**Depends On:**

- S-0031: Remove File-Based WebSocket Infrastructure
- S-0032: Remove Backend File Operations
- S-0033: Remove Frontend Polling Mechanisms

**Blocks:**

- S-0035: Database Schema and Migrations Setup (Phase 0)

---

## Validation Criteria

### Comprehensive Checklist

- [ ] All grep searches return no results in relevant directories
- [ ] Backend starts without errors
- [ ] Frontend builds without errors
- [ ] Frontend starts in dev mode without console errors
- [ ] Console streaming WebSocket works end-to-end
- [ ] Backend tests pass (or exit code 5 if no tests)
- [ ] Frontend tests pass
- [ ] Backup branch created and pushed
- [ ] Main branch committed with descriptive message
- [ ] Git tag created (v0.1-cleanup-complete)
- [ ] Documentation updated (see Documentation Updates section)

### Documentation Updates

- [ ] Update **README.md**: Add note about Phase -1 completion, list what was removed
- [ ] Update **AGENTS.md**: Remove references to file-based WebSocket and polling
- [ ] Update **..felix/config.md**: Note that state.json is no longer used for runtime state
- [ ] Create **Enhancements/PHASE_MINUS_ONE_COMPLETE.md**: Summary of cleanup, lines removed, what's preserved

---

## Rollback Strategy

If critical issues are discovered after this phase:

1. Checkout backup branch: `git checkout backup/pre-phase-0`
2. Review what broke
3. Cherry-pick fixes to main: `git checkout main && git cherry-pick <commit-sha>`
4. Re-run verification

**Rollback Decision Criteria:**

- Console streaming broken → Rollback immediately
- Agent execution broken → Rollback immediately
- Frontend styling broken → Fix forward (not critical)
- Missing features (agent status, requirements list) → Expected, don't rollback

---

## Success Metrics

**Quantitative:**

- ~1,900 lines of code removed
- 0 references to state.json in backend routers
- 0 polling intervals in frontend components
- 0 failing tests due to cleanup
- 1 backup branch created
- 1 git tag created

**Qualitative:**

- Codebase is cleaner and easier to understand
- No "dead code" reading from abandoned state files
- Console streaming still works (most critical feature)
- System is ready for database integration in Phase 0

---

## Notes

- This is primarily a verification and documentation spec
- No new code is written beyond documentation updates
- Console streaming must work 100% - this is non-negotiable
- Expected behavior: frontend shows static/missing data (agent status, requirements) until Phase 1
- This is the last spec in Phase -1 - celebrate the cleanup! 🎉
- Next step: S-0035 (Database Schema and Migrations Setup)


