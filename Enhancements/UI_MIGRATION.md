# Felix UI Migration to Supabase Design System

**Status:** ✅ Complete  
**Completed:** February 2026  
**Goal:** Transform Felix UI to match Supabase's clean, modern design aesthetic

---

## Overview

Felix successfully migrated from its original purple-themed UI to a Supabase-inspired design system featuring green brand colors, refined neutrals, and generous whitespace. The migration used **shadcn/ui** primitives throughout with strict token-based styling rules.

## Design Principles

- **Clean & Minimal** - Removed visual noise, embraced whitespace
- **Consistent Hierarchy** - Clear typography and spacing scales
- **Accessible Colors** - WCAG-compliant contrast ratios
- **Semantic Tokens** - Self-documenting CSS variables
- **shadcn/ui Only** - No custom UI components, all primitives from shadcn

### Visual System

- **Brand Color:** Green (#3ecf8e) - Supabase-inspired
- **Neutrals:** Dark slate backgrounds (#0d1117, #161b22)
- **Typography:** Inter (UI) + Fira Code (monospace)
- **Spacing:** 8px base unit, generous padding
- **Icons:** Lucide React (consistent, accessible)

---

## What Was Accomplished

### Foundation (✅ Completed)

**Design Token System** - Centralized CSS variables in `styles/tokens.css`

- Semantic naming (`--bg-base`, `--text-muted`, `--brand-500`)
- Backward compatibility aliases for gradual migration
- Component-agnostic color definitions

**CSS Architecture** - Modular file structure

- `tokens.css` - Design tokens
- `base.css` - Base styles, animations, utilities
- `components.css` - Component-specific styles
- Extracted 600+ lines from index.html

**Color Migration** - 100+ occurrences updated

- `felix-*` → `brand-*` across all components
- Tailwind config updated with new green scale
- PowerShell regex automation for consistency

**Tailwind Build Pipeline** - Local build for shadcn/ui support

- Added tailwind.config.cjs, postcss.config.cjs
- Bundled entry point: styles/app.css
- Removed CDN scripts

### Component Migration (✅ Completed)

**shadcn/ui Primitives Added:**

- Button, Input, Badge, Card, Dialog, AlertDialog
- ToggleGroup, Table, Alert, Select, Switch
- Textarea, Sheet, Skeleton

**Migrated Components:**

- **ProjectSelector** - Cards, tables, dialogs, badges
- **ProjectDashboard** - Forms, toggles, alerts
- **AgentDashboard** - Status badges, cards, toolbar controls
- **SettingsScreen** - All form controls, category navigation
- **SpecsEditor** - Toolbar, modals, sidebar list
- **PlanViewer** - Controls, badges, textarea
- **RequirementsKanban** - Cards, badges, dropzones
- **RequirementDetailSlideOut** - Animated slideout with Lucide icons
- **SpecEditWarningModal** - AlertDialog primitive

**Code Quality Improvements:**

- Created reusable **MarkdownEditor** component (eliminated ~600 lines duplication)
- Unified **Badge** component with proper TypeScript types
- Migrated all emoji icons to **Lucide React** icons
- Settings submenu matches main navigation style
- Compact kanban view optimizations

### UI Refinements (✅ Completed)

**Animations:**

- RequirementDetailSlideOut smooth slide-in/fade (10ms mount delay, 300ms unmount)
- Dual-state pattern (shouldRender + isOpen) for proper transitions

**Kanban Dropzones:**

- Fit-to-screen width (no horizontal scrolling)
- Subtle state-colored backgrounds (10-20% opacity)
- Match status colors (`--status-in-progress`, `--brand-500`, `--destructive-500`)

**Icons:**

- 100% Lucide React coverage (IconSettings, IconSparkles, IconFolder, etc.)
- Removed all emoji characters and inline SVGs
- Consistent sizing (w-4 h-4, w-5 h-5)

**Typography:**

- Sidebar sublabels: font-weight 100, 0.55rem
- Consistent uppercase usage for tags
- Refined hierarchy throughout

---

## Technical Implementation

### Design Token Reference

**Brand Scale (Green):**

```css
--brand-50: #ecfdf5 --brand-400: #4dd796 --brand-500: #3ecf8e /* Primary */
  --brand-600: #2fb87a --brand-900: #166d47;
```

**Background Hierarchy:**

```css
--bg: #0d1117 /* Main canvas */ --bg-200: #050608 /* Deepest */
  --bg-alternative: #161b22 /* Elevated */ --bg-surface-100: #161b22 /* Cards */
  --bg-surface-200: #21262d /* Nested */;
```

**Text Hierarchy:**

```css
--text: #f1f5f9 /* Primary */ --text-light: #c9d1d9 /* Secondary */
  --text-lighter: #8b949e /* Tertiary */ --text-muted: #6e7781 /* Muted */;
```

### shadcn/ui Rules (Enforced)

1. Use shadcn primitives for all UI elements
2. No custom components unless wrapping shadcn
3. No inline hex colors - reference tokens only
4. Prefer semantic tokens over legacy aliases
5. All icons from Lucide React

### Animation Standards

- Default transitions: 150ms ease-out
- Hover states: 200ms ease
- Layout changes: 300ms ease-in-out
- Modal enter/exit: 250ms ease-out

---

## Key Decisions

**Why Green Over Purple?**

- Supabase's green is distinctive and modern
- Better contrast against dark backgrounds
- Conveys growth, stability, success

**Why shadcn/ui?**

- Full control over components
- Radix UI primitives (accessible)
- Tailwind-based (consistent with our stack)
- No proprietary dependencies

**Why Keep Inter + Fira Code?**

- Industry-standard fonts
- Excellent readability and ligatures
- No need to change what works

---

## Migration Guidelines

### For New Code

1. Use shadcn/ui primitives only
2. Reference CSS variables from tokens.css
3. Use Lucide React for all icons
4. Follow 8px spacing scale
5. Include hover/focus states

### Code Review Checklist

- [ ] No inline hex colors
- [ ] No `felix-` classes remaining
- [ ] shadcn/ui primitives used
- [ ] Lucide icons (no emoji/SVG)
- [ ] Semantic token references
- [ ] Consistent spacing (8px base)
- [ ] Hover and focus states defined

---

## Reference Files

- `app/frontend/styles/tokens.css` - Design token definitions
- `app/frontend/tailwind.config.cjs` - Tailwind configuration
- `app/frontend/components/ui/` - shadcn/ui primitives
- [Supabase Design System](https://supabase-design-system.vercel.app/)
- [Lucide Icons](https://lucide.dev/)

**Completed:** February 11, 2026
