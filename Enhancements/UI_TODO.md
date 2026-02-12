# UI Todo - FE_AUDIT Remediation

1. Split monolithic views

- Extract view blocks from `app/frontend/App.tsx` into dedicated components with clear props.
- Keep `app/frontend/App.tsx` as a thin layout/router container.

2. Consolidate duplicate components

- Remove one of the ProjectSelector implementations and standardize imports on the remaining one.
- Delete the duplicate file once all imports are updated.

3. Enforce shadcn primitives + Lucide icons only

- Replace custom buttons/inputs/menus with shadcn components where applicable.
- Replace inline SVG icons with Lucide equivalents (notably `app/frontend/components/MarkdownEditor.tsx`).
- Add a rule: no custom icons; always use Lucide equivalents.

4. Reduce inline styles

- Convert inline token styles to Tailwind utility classes or shared class helpers.
- Target: `app/frontend/App.tsx`, `app/frontend/components/WorkflowVisualization.tsx`,
  `app/frontend/components/AgentDashboard.tsx`, `app/frontend/components/ProjectSelector.tsx`.

5. Centralize repeated UI patterns

- Create shared status/badge variant helpers for consistent colors.
- Add a shared EmptyState component for repeated "no data" views.

pause and confirm aproach on next one before proceeding: 6) Add lightweight UI audit tooling

- Add an ESLint rule or script to flag inline styles and non-shadcn usage.
- Run it and fix the first pass of findings.
