# Release Notes - v0.7.0

## Highlights
- Standardized data surfaces with reusable table + card layouts.
- Specs UI overhaul with better metadata sync, validation, and layout consistency.
- UI cleanup: consistent loading/empty states, icon set normalization, and menu alignment.

## UI/UX
- Added reusable data table with filters, search, and row actions.
- Unified card hover and table row hover behaviors.
- Standardized header spacing and padding across Specs/Projects views.
- Menu alignment fixes for sidebar, user/org menus, and settings submenus.
- Replaced custom inline SVGs with Lucide icons.

## Specs Editor
- Improved spec metadata panel and validation workflows.
- Enforced spec title formatting and safer edits with warning prompts.
- Bidirectional metadata <-> markdown sync refinements.
- Added tags as a dedicated column in the specs table view.

## Loading + Empty States
- Introduced reusable PageLoading and EmptyState components.
- Applied consistent loading states across major views.

## Notifications
- Added Sonner-based toasts for validation and sync feedback.

## Internal UI Tooling
- Added a UI audit script to flag inline styles and non-standard components.
