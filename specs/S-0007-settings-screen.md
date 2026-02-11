# S-0007: Settings Screen

## Narrative

As a developer using Felix, I need a centralized settings interface where I can view and configure all system settings in one place, so that I can easily manage Felix's behavior, preferences, and integrations without manually editing configuration files.

## Acceptance Criteria

### Settings Menu Access

- [x] Settings menu option appears in the sidebar navigation
- [x] Clicking settings icon navigates to full-screen settings view
- [x] Settings screen is accessible from any project context
- [x] Settings can be closed to return to previous view

### Layout and Design

- [x] Full-screen GitHub-style settings interface
- [x] Left sidebar menu with category navigation
- [x] Right panel displays settings for selected category
- [x] Consistent with Felix's dark theme and visual style
- [ ] Responsive layout that adapts to window size

### Settings Categories

- [x] **General**: Basic Felix configuration (max_iterations, auto_transition, default_mode)
- [x] **Projects**: Default project settings and behaviors
- [x] **Agent**: Agent execution preferences and policies
- [x] **Interface**: UI preferences (theme, layout, notifications)
- [x] **Advanced**: Developer options and debug settings

### Settings Persistence

- [ ] Settings changes are saved to `..felix/config.json`
- [ ] Settings are saved via backend API (PUT /api/config)
- [ ] Changes apply immediately without restart where possible
- [ ] Validation prevents invalid configuration values
- [ ] Unsaved changes warning when navigating away

### Settings Management

- [ ] Input fields for text, numeric, and boolean settings
- [ ] Dropdowns for enumerated values
- [ ] Reset to defaults button per category
- [ ] Export/import configuration functionality
- [ ] Search/filter settings by name or description

### Visual Feedback

- [ ] Success message when settings are saved
- [ ] Error messages for validation failures
- [ ] Loading states during save operations
- [ ] Modified indicator for unsaved changes
- [ ] Tooltips explaining each setting's purpose

## Technical Notes

**Architecture:** Settings screen is a new top-level view in App.tsx, similar to the projects, kanban, and specs views. It renders as a full-screen overlay with GitHub-style two-column layout.

**State Management:** Settings data is fetched from the backend API on mount. Local state tracks modifications. Changes are saved via API calls to persist to disk.

**Integration Points:**

- Add settings icon/button to sidebar in App.tsx
- Create new `uiState` value: `'settings'`
- Add SettingsScreen component to render logic
- Backend API endpoint: GET/PUT `/api/config` (may need to be created)

**Existing Patterns:** Follow the same visual design language used in ConfigPanel.tsx but expand to full-screen multi-category interface. Use the same color palette, borders, shadows, and transitions.

**Settings Schema:** Settings should map to the structure in `..felix/config.json`. Provide sensible defaults and validation rules for each setting.

## Validation Criteria

- [x] Settings icon appears in sidebar: Visual inspection of App.tsx sidebar
- [x] Settings screen renders full-screen: Navigate to settings view, verify layout
- [x] Left sidebar shows categories: Verify menu with multiple categories
- [x] Right panel shows settings: Verify settings display for each category
- [x] Settings save successfully: Manual verification - modify setting, save, verify ..felix/config.json updated
- [x] Settings load from backend: Manual verification - refresh page, verify settings reflect saved values
- [x] Validation prevents invalid values: Manual verification - attempt invalid input, verify error shown
- [x] Navigation returns to previous view: Manual verification - click back/close, verify returns to prior state

## Dependencies

- S-0002 (Backend API Server) - requires API endpoints for config management
- S-0003 (Frontend Observer UI) - settings screen integrates into existing UI structure

## Non-Goals

- Multi-language support configuration
- Theme customization beyond built-in options
- Plugin/extension management (future enhancement)
- Advanced text editor preferences (use existing ConfigPanel patterns)



