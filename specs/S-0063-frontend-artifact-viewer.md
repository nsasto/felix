# S-0063: Run Artifact Sync - Frontend Artifact Viewer

**Priority:** High  
**Tags:** Frontend, UI, React

## Description

As a Felix user, I need to view run artifacts and event timelines in the web UI so that I can inspect run results, debug failures, and understand what the agent did without accessing the filesystem directly.

## Dependencies

- S-0060 (Backend Sync Endpoints) - requires artifact list/download and events endpoints
- S-0042 (Frontend API Client and Dashboard) - requires existing UI infrastructure

## Acceptance Criteria

### API Client Extensions

- [ ] File `app/frontend/services/felixApi.ts` updated with new methods
- [ ] `RunFile` interface defined with path, kind, size_bytes, sha256, content_type, updated_at fields
- [ ] `RunEvent` interface defined with id, ts, type, level, message, payload fields
- [ ] Method `getRunFiles(runId: string)` returns Promise of run files list
- [ ] Method `getRunFile(runId: string, filePath: string)` returns Promise of file content as string
- [ ] Method `getRunEvents(runId: string, after?: number)` returns Promise of events with pagination
- [ ] All methods include proper error handling with try/catch

### Run Detail Component

- [ ] Component file `app/frontend/components/RunDetail.tsx` created
- [ ] Accepts runId and onClose props
- [ ] Component renders split view: file list sidebar + content viewer
- [ ] Shows loading state while fetching data
- [ ] Shows error message if run not found

### File List Sidebar

- [ ] Displays all artifacts grouped by kind (artifacts first, logs second)
- [ ] Shows file name with size in KB
- [ ] Highlights selected file with background color
- [ ] Clicking file loads content in viewer
- [ ] Auto-selects report.md if available on mount
- [ ] Falls back to plan.md if report.md not found
- [ ] Empty state shown if no artifacts found

### Content Viewer Area

- [ ] Displays selected file path as heading
- [ ] Renders markdown files with proper formatting
- [ ] Renders log files as plain text in monospace font
- [ ] Renders other text files as pre-formatted code
- [ ] Shows scrollbar for long content
- [ ] Large files don't freeze UI (lazy loading or streaming)

### Event Timeline Section (Optional)

- [ ] Event timeline panel below or beside file list
- [ ] Shows event timestamp, type, level, and message
- [ ] Color-codes events by level (error=red, warn=yellow, info=blue)
- [ ] Scrollable list with latest events at bottom
- [ ] Auto-scrolls to bottom when new events arrive

### Integration with Existing UI

- [ ] Run detail accessible from Agent Dashboard run list
- [ ] Clicking run row opens run detail component
- [ ] Run detail opens in modal, slide-out, or dedicated route
- [ ] Close button returns to dashboard
- [ ] Navigation preserves project context

### Styling and UX

- [ ] Component uses existing CSS variables for theming
- [ ] Works in both light and dark themes
- [ ] Responsive layout adapts to window width
- [ ] Keyboard navigation supported (arrow keys to select files)
- [ ] Loading spinners for async operations
- [ ] Error messages styled consistently with app

## Validation Criteria

- [ ] `cd app/frontend && npm run build` completes without TypeScript errors
- [ ] `cd app/frontend && npm run dev` starts dev server (exit code 0)
- [ ] Manual verification - navigate to run detail, verify file list displays
- [ ] Manual verification - click different files, verify content changes
- [ ] Manual verification - markdown rendering works (headings, lists, code blocks)
- [ ] Manual verification - large log files scroll smoothly without freezing

## Technical Notes

**Architecture:** Component uses React hooks (useState, useEffect) for data fetching and state management. File content loaded on-demand when selected to avoid loading all artifacts at once.

**Performance:** Large files streamed or chunked to prevent memory issues. Consider virtual scrolling for very long logs. Markdown rendering uses existing library (marked or react-markdown).

**UX Design:** Sidebar + content viewer pattern common in code editors (VS Code, GitHub). Familiar navigation model reduces learning curve.

**Don't assume not implemented:** Check if RunDetail or similar component already exists in components directory. May have partial implementation from earlier work.

## Non-Goals

- Real-time event streaming via SSE (deferred to Phase 7)
- Inline editing of artifacts
- Artifact diff comparison between runs
- Downloading artifacts as zip bundle
- Syntax highlighting for code files
- Search within artifacts
