# S-0008: Projects Settings Screen

## Narrative

As a Felix user managing multiple projects, I need a projects management screen within settings where I can view all registered projects, configure project-specific settings, and unregister projects I'm no longer working on, so that I can efficiently organize and maintain my workspace.

## Acceptance Criteria

### Projects List View

- [ ] "Projects" category appears in settings left sidebar menu
- [ ] Projects list displays all registered projects from ~/...felix/projects.json
- [ ] Each project card shows: name, path, registration date, last activity
- [ ] Projects sorted by last activity (most recent first)
- [ ] Empty state message when no projects registered
- [ ] Search/filter projects by name or path

### Project Card Display

- [ ] Project name displayed as heading
- [ ] Full project path shown (with copy-to-clipboard button)
- [ ] Status indicator (active, idle, or error)
- [ ] Last activity timestamp (relative time: "2 hours ago")
- [ ] Number of specs and requirements count
- [ ] Quick actions: Open, Configure, Unregister

### Project Registration

- [ ] "Register New Project" button at top of projects list
- [ ] Button opens directory picker dialog
- [ ] Selected directory validated for Felix structure (specs/, ..felix/)
- [ ] Project added to ~/...felix/projects.json on success
- [ ] Success notification shown after registration
- [ ] Project list automatically refreshes

### Project Configuration

- [ ] Click "Configure" opens project-specific settings panel
- [ ] Settings panel shows: project name (editable), default status, Tags
- [ ] Save button persists changes to project metadata
- [ ] Cancel button discards changes
- [ ] Validation prevents duplicate project names

### Project Unregistration

- [ ] Click "Unregister" opens confirmation dialog
- [ ] Dialog warns about removal from Felix (files remain on disk)
- [ ] Confirm button removes project from ~/...felix/projects.json
- [ ] Project disappears from list after unregistration
- [ ] Cannot unregister currently active project

### Project Navigation

- [ ] Click "Open" button switches to that project's workspace
- [ ] Active project highlighted in list
- [ ] Opening project closes settings and loads project view
- [ ] Recent projects indicator (accessed within last 7 days)

### Visual Feedback

- [ ] Loading state while fetching projects list
- [ ] Error state for inaccessible project paths
- [ ] Success/error toasts for register/unregister actions
- [ ] Disabled state for actions on invalid projects
- [ ] Hover states on project cards and buttons

## Technical Notes

**Architecture:** Projects Settings Screen is a new category within the SettingsScreen component. It reads from backend API endpoint GET /api/projects for registered projects list.

**Storage:** Projects metadata stored in ~/...felix/projects.json (or user's home directory equivalent on Windows). Backend API manages read/write operations to this file.

**Integration Points:**

- Backend endpoint: GET /api/projects (already exists in storage.py)
- Backend endpoint: POST /api/projects/register (already exists)
- Backend endpoint: DELETE /api/projects/:id/unregister (may need to be added)
- Backend endpoint: PUT /api/projects/:id (for updating project metadata)

**State Management:** Fetch projects list on mount. Local state tracks selected project for configuration. Mutations trigger refetch of projects list to stay in sync.

**Validation:** Check project path exists and contains required Felix structure (specs/ directory, ..felix/ directory with config.json). Prevent duplicate paths.

**Don't assume not implemented:** Backend already has project registration and listing. Check existing storage.py and routers for available endpoints before creating new ones.

## Dependencies

- S-0002 (Backend API Server) - requires projects API endpoints
- S-0007 (Settings Screen) - projects screen is a category within settings

## Non-Goals

- Project templates or scaffolding (covered by S-0004)
- Project import/export functionality
- Project cloning or duplication
- Multi-workspace support (one user, multiple Felix instances)
- Project archiving or soft-delete

## Validation Criteria

- [ ] Projects category appears in settings menu: Open settings, verify Projects in left sidebar
- [ ] Projects list displays registered projects: Register project, verify appears in list
- [ ] Register new project works: Click Register, select directory, verify added
- [ ] Unregister removes project: Click Unregister, confirm, verify removed from list
- [ ] Project configuration saves: Edit project name, save, verify persisted
- [ ] Search filters projects: Type in search box, verify list filters correctly
- [ ] Open project switches workspace: Click Open, verify project loads in main view



