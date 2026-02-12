# Frontend Audit - Code Quality, Reuse, Efficiency, UI Patterns

Date: 2026-02-11

## Scope

- app/frontend application code and UI components
- UI guidelines in Enhancements/UI_GUIDELINES.md

## Executive Summary

- The frontend works but has large monolithic components, heavy inline styling, and several deviations from the shadcn/ui-only rule set.
- There is repeated layout/styling logic and duplicated component variants that could be consolidated.
- Some UI elements are hand-built (custom buttons, inline SVGs) rather than shadcn primitives and Lucide icons.

## Code Quality Findings

1. Monolithic component structure

- app/frontend/App.tsx is ~1500 lines and mixes routing, layout, data fetch, and view rendering. This makes changes risky and hard to test.
- Several view render functions are defined inline (renderKanban, renderCanvas, etc.) with large JSX blocks and heavy inline styles.

2. Inline styles as primary styling mechanism

- Extensive use of inline style objects in app/frontend/App.tsx and other components (e.g., app/frontend/ProjectSelector.tsx, app/frontend/components/ProjectSelector.tsx, app/frontend/components/WorkflowVisualization.tsx, app/frontend/components/AgentDashboard.tsx).
- UI_GUIDELINES discourages inline styles except for direct token mapping; the code frequently uses inline styles instead of Tailwind classes.

3. Custom UI elements outside shadcn primitives

- Multiple places use raw button/input/div elements with custom styling instead of shadcn components.
- app/frontend/components/MarkdownEditor.tsx uses inline SVGs for toolbar actions rather than Lucide icons, violating guidelines.

4. Complex view state in App.tsx

- App.tsx manages many pieces of state and multiple UI views in one file, making state flow opaque and difficult to reason about.

## Repeated Code and Cleanup Opportunities

1. Duplicate ProjectSelector implementations

- app/frontend/ProjectSelector.tsx and app/frontend/components/ProjectSelector.tsx both exist, likely diverging implementations.
- Consolidate into a single component and update imports.

2. Repeated inline style blocks

- Repeated token-based styles across App.tsx and ProjectSelector variants can be centralized into Tailwind utility classes or component-level CSS classes.
- Example: repeated `backgroundColor: "var(--bg-base)"`, `color: "var(--text-muted)"`, `borderColor: "var(--border-default)"`.

3. Repeated status/pill styles

- Status and badge styles appear in multiple files (App.tsx, RequirementsKanban.tsx, ProjectSelector). Centralize in a shared utility or use Badge variants.

4. Repeated conditional view rendering

- App.tsx contains multiple similar "Select a project to view ..." empty states. Consider a shared EmptyState component.

5. Custom icons defined despite rule that all icons should be Lucide only.

## Efficiency and Performance Observations

1. Large render surface with frequent inline object creation

- Inline style objects and large JSX trees inside App.tsx may create unnecessary re-renders and make memoization harder.

2. Repeated data derivations in render

- Lists and labels are built inline within render functions, e.g., `columns`, `viewMetadata`, and `orgOptions`.
- Some are static and can live outside the component to reduce re-creation.

3. Missing memoization in heavy views

- Some derived values are already memoized (activeAsset), but many others are not. This is not critical yet but will scale poorly.

## Deviations From UI Guidelines

1. shadcn/ui primitives not consistently used

- Many custom buttons and inputs exist outside shadcn primitives, especially in App.tsx and ProjectSelector variants.

2. Inline SVGs instead of Lucide icons

- app/frontend/components/MarkdownEditor.tsx uses inline SVG for toolbar buttons; guidelines mandate Lucide only.

3. Inline styles used heavily

- Guidelines state "No inline styles" except for token mapping. Multiple files use inline styles extensively rather than Tailwind or tokens in className.

4. Custom UI patterns

- Some custom menus and panels are built without shadcn primitives (e.g., org menu, user menu, search input groups).
- Consider shadcn Dialog/Popover/Dropdown Menu where appropriate for consistency.

## Recommendations (Prioritized)

1. Break up App.tsx into view-specific components

- Move projects, kanban, orchestration, assets, config, plan, settings into their own components with clear props.

2. Consolidate ProjectSelector

- Remove the duplicate and standardize on one component in app/frontend/components.

3. Replace inline SVG icons with Lucide

- MarkdownEditor toolbar should use Lucide icons to comply with UI guidelines.

4. Reduce inline styles

- Convert repeated inline token styles to Tailwind utility classes or component-level CSS classes.

5. Adopt shadcn primitives consistently

- Replace custom buttons/inputs/menus with shadcn Button/Input/DropdownMenu/Popover where possible.

6. Add lightweight UI audit tooling

- Add ESLint rules or a quick script to flag inline styles or non-shadcn components.

## Files With High Deviation Density

- app/frontend/App.tsx
- app/frontend/ProjectSelector.tsx
- app/frontend/components/ProjectSelector.tsx
- app/frontend/components/MarkdownEditor.tsx
- app/frontend/components/WorkflowVisualization.tsx
- app/frontend/components/AgentDashboard.tsx

## Notes

- This audit focuses on UI consistency and maintainability, not on backend integration or functional correctness.
