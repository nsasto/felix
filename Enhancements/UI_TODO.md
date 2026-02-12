# UI Todo (Ordered)

- Extract views from `app/frontend/App.tsx` into dedicated components; keep App as a thin layout/router.
- Consolidate ProjectSelector (remove duplicate, update imports).
- Standardize shadcn primitives and Lucide icons (MarkdownEditor toolbar, menus, buttons, inputs).
- Centralize status/badge variants and add a shared EmptyState component.
- Replace inline styles with Tailwind utilities or shared class helpers.
- Add UI audit tooling (eslint rule or script) to flag inline styles and non-shadcn usage, then fix findings.
