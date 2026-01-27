# S-0019: Settings Not Project Dependent

## Narrative

As a user, I want to access and modify Felix settings without having to select a project first, since settings are global configuration stored in the felix/ folder and not tied to any specific project.

## Problem

Currently, the Settings screen may require project selection or context to be accessible. This creates unnecessary friction because:

- Settings are stored globally in felix/config.json, not per-project
- Users must select an arbitrary project just to access global configuration
- The UX implies settings are project-specific when they are not
- Settings should be accessible from any application state

## Solution

Make the Settings screen fully independent of project context:

- Settings route should not require project_id parameter
- Backend settings endpoints should work without project context
- UI navigation should allow direct access to Settings at any time
- Settings persistence uses global felix/config.json location

## Acceptance Criteria

### Navigation & Access

- [ ] Settings screen accessible without selecting a project
- [ ] Settings route works without project_id parameter
- [ ] Settings menu/button available from any app state
- [ ] Direct URL navigation to Settings works (e.g., /settings)

### Functionality

- [ ] Settings display correctly when accessed without project context
- [ ] All settings fields load from felix/config.json
- [ ] Settings changes save to felix/config.json (global location)
- [ ] No project-specific data required to view or edit settings

### Backend API

- [ ] GET /api/settings endpoint works without project_id
- [ ] PUT /api/settings endpoint works without project_id
- [ ] Settings endpoints return global felix/config.json data
- [ ] API documentation reflects project-independent nature

## Technical Notes

**Architecture**: Settings are global Felix configuration, not project configuration. The Settings screen and backend endpoints should operate independently of the project selection state.

**Storage**: Settings persist to felix/config.json in the user's Felix installation directory, not within any project directory.

**UI State**: The Settings component should not depend on ProjectContext or require project_id in routing. Navigation should be accessible from the main app navigation at all times.

**Don't assume not implemented**: Check existing Settings components and API endpoints. May need refactoring to remove project dependencies rather than building from scratch.

## Dependencies

- S-0007 (Settings Screen) - requires existing settings screen implementation
- S-0008 (Projects Settings Screen) - may need refactoring to separate project-specific settings from global settings

## Non-Goals

- Project-specific configuration (separate concern - should remain project-dependent)
- Multiple user profiles or settings sets
- Settings synchronization across machines
- Agent-specific settings (handled separately in agent configuration)

## Validation Criteria

- [ ] Backend starts successfully: `python app/backend/main.py` (exit code 0)
- [ ] Settings endpoint accessible: `curl http://localhost:8080/api/settings` (status 200)
- [ ] Frontend runs successfully: `cd app/frontend && npm run dev` (exit code 0)
- [x] Settings display without project: Manual verification - navigate to Settings without selecting any project, verify UI displays correctly
- [x] Settings persist globally: Manual verification - change a setting, verify felix/config.json updated in global location (not project directory)
- [x] Settings independent of project state: Manual verification - switch between projects, verify Settings screen shows same global configuration
