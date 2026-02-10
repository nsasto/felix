# Felix UI Migration to Supabase Design System

**Status:** In Progress  
**Started:** February 2026  
**Goal:** Transform Felix UI to match Supabase's clean, modern design aesthetic

---

## Overview

Felix is migrating from its original purple-themed UI to a Supabase-inspired design system featuring green brand colors, refined neutrals, and generous whitespace. This migration maintains Felix's functional identity while adopting industry-leading design patterns.

**Decision Update (Feb 10, 2026):** Adopt **shadcn/ui** as the primary component source for full control, with strict token and pattern rules to preserve Supabase-inspired consistency. Avoid bespoke UI components unless they wrap shadcn primitives.

## Design Philosophy

### Core Principles

1. **Clean & Minimal** - Remove visual noise, embrace whitespace
2. **Consistent Hierarchy** - Clear typography and spacing scales
3. **Accessible Colors** - WCAG-compliant contrast ratios
4. **Semantic Naming** - Self-documenting design tokens
5. **Progressive Enhancement** - Backward compatibility during transition

### Visual Language

- **Primary Brand:** Green (#3ecf8e) - Supabase-inspired, conveys growth and reliability
- **Neutrals:** Dark slate backgrounds (#0d1117, #161b22) with refined grays
- **Typography:** Inter (UI) + Fira Code (monospace) - preserved from original
- **Spacing:** Generous padding, 8px base unit
- **Borders:** Subtle, refined (1px solid with low opacity)

---

## Migration Strategy

### Phase 1: Foundation (✅ Completed)

#### 1.1 Design Token System

**File:** `app/frontend/styles/tokens.css`

Established centralized design token system with semantic naming:

```css
/* Supabase-inspired semantic variables */
--bg: #0d1117; /* Main background */
--bg-200: #050608; /* Deepest background */
--bg-alternative: #161b22; /* Alternative surfaces */
--text: #f1f5f9; /* Primary text */
--text-light: #c9d1d9; /* Secondary text */
--brand-500: #3ecf8e; /* Primary brand color */
```

**Benefits:**

- Component-agnostic color definitions
- Easy theme switching (dark/light)
- Consistent across entire application
- Self-documenting variable names

#### 1.2 CSS Architecture Refactor

**Files:**

- `app/frontend/styles/tokens.css` - Design tokens
- `app/frontend/styles/base.css` - Base styles, animations, utilities
- `app/frontend/styles/components.css` - Component-specific styles

**What Changed:**

- Extracted 600+ lines of inline CSS from `index.html`
- Modular CSS architecture for maintainability
- Separated concerns (tokens → base → components)

**Before:**

```html
<!-- index.html -->
<style>
  /* 600+ lines of mixed styles */
</style>
```

**After:**

```html
<!-- index.html -->
<link rel="stylesheet" href="./styles/tokens.css" />
<link rel="stylesheet" href="./styles/base.css" />
<link rel="stylesheet" href="./styles/components.css" />
```

#### 1.3 Color Migration: `felix-` → `brand-`

**Scope:** 100+ occurrences across all components

**Tailwind Config Update:**

```javascript
// Old (Purple theme)
colors: {
  felix: {
    400: '#9ba9f8',
    500: '#738ef1',  // Old primary
    600: '#5666d4',
  }
}

// New (Green theme)
colors: {
  brand: {
    50: '#ecfdf5',
    400: '#4dd796',
    500: '#3ecf8e',  // New primary - Supabase green
    600: '#2fb87a',
    900: '#166d47',
  }
}
```

**Class Replacements:**

- `bg-felix-500` → `bg-brand-500`
- `text-felix-400` → `text-brand-400`
- `border-felix-600/40` → `border-brand-600/40`
- `hover:bg-felix-500/10` → `hover:bg-brand-500/10`

**Affected Files:**

- `App.tsx` - 30+ replacements
- All 29 component files - 70+ replacements
- Automated via PowerShell regex: `felix-(\d{3})` → `brand-$1`

#### 1.4 Backward Compatibility

**File:** `app/frontend/styles/tokens.css`

CSS variable aliases ensure gradual migration without breaking changes:

```css
/* Legacy aliases for backward compatibility */
--accent-primary: var(--brand-500);
--bg-deepest: var(--bg-200);
--bg-deep: var(--bg-alternative);
--bg-base: var(--bg-surface-100);
```

**Strategy:**

- Old components can use legacy variables
- New components use semantic tokens
- Allows incremental migration
- No breaking changes during transition

---

### Phase 2: Component Redesign (🔄 Next)

#### 2.0 shadcn/ui Migration Principles (Approved)

**Rules (non-negotiable):**

- Use shadcn primitives for all UI: Button, Input, Select, Tabs, Card, Badge, Dialog, Sheet, DropdownMenu, Tooltip, Table, Accordion.
- No custom UI components unless they are thin wrappers over shadcn primitives.
- No new colors or ad-hoc shadows. All styling must reference tokens from **app/frontend/styles/tokens.css**.
- No inline hex colors in JSX.
- Prefer semantic tokens (eg. --bg-surface-100, --text-secondary) over legacy aliases.

#### 2.0.1 Tailwind Build Migration (In Progress)

**Why:** shadcn/ui requires a local Tailwind build (CDN cannot generate component classes).

**Changes:**

- Added Tailwind build pipeline and PostCSS config
  - **app/frontend/tailwind.config.cjs**
  - **app/frontend/postcss.config.cjs**
- Bundled CSS entry point for Tailwind + tokens
  - **app/frontend/styles/app.css**
- Linked bundled CSS in app entry
  - **app/frontend/index.tsx** now imports **styles/app.css**
- Removed Tailwind CDN scripts and direct CSS links
  - **app/frontend/index.html**
- Added shadcn foundational dependencies
  - **app/frontend/package.json**

**Notes:**

- Existing tokens remain the source of truth (**app/frontend/styles/tokens.css**)
- Base/component styles remain unchanged but are now imported via **styles/app.css**

#### 2.1 UI Surface Mapping (to shadcn primitives)

**App shell:** Header, org/user menus, badges, search

- Targets: Button, DropdownMenu, Badge, Input

**Sidebar navigation**

- Targets: Button, NavigationMenu (or Button + Tooltip)

**Projects (selector + dashboard)**

- Targets: Tabs/ToggleGroup, Card, Table, Badge, Dialog, Input, Progress

**Kanban + requirement detail**

- Targets: Card, Badge, Sheet/Drawer, Tooltip, Tabs

**Specs editor**

- Targets: Dialog, AlertDialog, Tabs, Accordion, Input, Textarea, Badge

**Plan viewer**

- Targets: Tabs, Textarea, Badge, Button, Alert

**Settings + config**

- Targets: Card, Input, Select, Switch, Dialog, Alert

**Agent dashboards + runs**

- Targets: DropdownMenu, Button, Badge, Card, Table, Tabs

**Copilot chat panel**

- Targets: Dialog/Sheet, Textarea, ScrollArea, Button, Badge

#### 2.2 Token Harmonization

**Source of truth:** **app/frontend/styles/tokens.css**

**Action:** Align shadcn theme variables to existing tokens to avoid double systems. Continue using Supabase-inspired palette defined in tokens.css.

#### 2.3 AI Tooling Guardrails (Codex / Droid / GitHub Copilot)

**Shared Rules:**

- Only use shadcn/ui components for UI primitives. No bespoke JSX for buttons, inputs, menus, dialogs, or tabs.
- Use tokens from **app/frontend/styles/tokens.css**. No hex colors in JSX or CSS.
- Prefer semantic tokens; legacy aliases allowed only for existing components.
- Avoid inline style objects unless mapping directly to tokens.

**Codex / Droid Prompt Addendum:**

- "All UI must use shadcn/ui primitives. Use tokens from tokens.css only. Do not invent new components or styles."

**GitHub Copilot Prompt Addendum:**

- "Prefer shadcn/ui components and existing tokens. Avoid custom UI or direct Tailwind color classes."

#### 2.0.2 Migration Progress Log

**Feb 10, 2026**

- Added shadcn UI primitives: Button, Input, Badge, Card, Dialog, AlertDialog, ToggleGroup, Table, Alert
  - **app/frontend/components/ui/**
  - **app/frontend/lib/utils.ts**
- Started ProjectSelector migration to shadcn primitives
  - **app/frontend/components/ProjectSelector.tsx**
- Installed Radix dependencies for dialogs/toggles
  - **app/frontend/package.json** + **app/frontend/package-lock.json**
- Added shadcn Switch and migrated Copilot toggles
  - **app/frontend/components/ui/switch.tsx**
  - **app/frontend/components/SettingsScreen.tsx**
- Migrated PlanViewer controls to shadcn primitives (Button, ToggleGroup, Badge, Textarea)
  - **app/frontend/components/PlanViewer.tsx**
  - **app/frontend/components/ui/textarea.tsx**
- Migrated SpecsEditor toolbar + editor to shadcn primitives (Button, ToggleGroup, Badge, Textarea)
  - **app/frontend/components/SpecsEditor.tsx**
- Migrated SpecsEditor modals to shadcn Dialog/AlertDialog
  - **app/frontend/components/SpecsEditor.tsx**
- Migrated SpecsEditor sidebar list to shadcn primitives (Button, Input, Badge, Alert)
  - **app/frontend/components/SpecsEditor.tsx**
- Migrated SpecEditWarningModal to shadcn AlertDialog
  - **app/frontend/components/SpecEditWarningModal.tsx**
- Cleaned remaining SpecsEditor inline styles (content area)
  - **app/frontend/components/SpecsEditor.tsx**

#### 2.1 Navigation Sidebar

**Target Component:** `App.tsx` sidebar (lines 1215-1415)

**Current State:** Fixed 64px width, vertical icon nav

**Planned Changes:**

- Collapsible: 64px (collapsed) ↔ 240px (expanded)
- Icon + label layout when expanded
- Smooth width transition (300ms ease)
- Persist state in localStorage
- Add tooltips for collapsed state

**Design Reference:** Supabase sidebar pattern

#### 2.2 Card Component System

**New Component:** `components/Card.tsx`

**Variants:**

```tsx
<Card variant="default">      // Standard elevated card
<Card variant="interactive">  // Hover states, clickable
<Card variant="flat">         // Minimal, no elevation
<Card variant="bordered">     // Emphasized border
```

**Features:**

- Consistent shadow system
- Unified padding scale
- Hover/focus states
- Dark theme optimized

#### 2.3 Button System Standardization

**New Component:** `components/Button.tsx`

**Variants:**

```tsx
<Button variant="primary">    // brand-500 background
<Button variant="secondary">  // Outline style
<Button variant="ghost">      // Transparent, subtle
<Button variant="danger">     // Destructive actions
```

**Sizes:** `xs | sm | md | lg`

**States:** default, hover, active, disabled, loading

#### 2.4 Status Badge Redesign

**Target:** Status indicators across Kanban, Requirements, Runs

**Current:** Bold backgrounds, prominent

**New Design:**

- Subtle backgrounds (10% opacity)
- Uppercase 9px text
- Refined borders
- Reduced visual weight

**Example:**

```tsx
// Before
<span className="bg-brand-500 text-white px-2 py-1 rounded font-bold">
  RUNNING
</span>

// After
<span className="bg-brand-500/10 text-brand-400 border border-brand-500/20 px-2 py-0.5 rounded uppercase text-[9px] font-bold">
  running
</span>
```

#### 2.5 Typography Refinement

**Changes:**

- Base font size: 13px → 14px (improved readability)
- Reduce uppercase usage (less shouty)
- Better hierarchy: h1-h6 scale
- Consistent line heights
- Refined letter spacing

**Scale:**

```css
--font-xs: 11px;
--font-sm: 12px;
--font-base: 14px; /* New default */
--font-lg: 16px;
--font-xl: 20px;
```

---

### Phase 3: Advanced Features (📋 Planned)

#### 3.1 Loading States

- Skeleton screens (Supabase pattern)
- Unified spinner component
- Staggered content reveal
- Progress indicators

#### 3.2 Form Components

- Consistent input styling
- Focus states (brand-500 ring)
- Error states
- Helper text patterns
- Label positioning

#### 3.3 Toast Notifications

- Unified notification system
- Success/error/info/warning variants
- Auto-dismiss with progress bar
- Accessible (ARIA live regions)

#### 3.4 Modal/Dialog System

- Backdrop blur
- Focus trap
- Esc to close
- Consistent spacing
- Mobile responsive

---

## Implementation Checklist

### ✅ Completed

- [x] Design token system (tokens.css)
- [x] CSS extraction to modular files
- [x] Tailwind config update (felix → brand colors)
- [x] Color migration across all components (100+ occurrences)
- [x] Backward compatibility aliases

### 🔄 In Progress

- [ ] Navigation sidebar redesign
- [ ] Card component library
- [ ] Button system standardization
- [ ] Status badge redesign
- [ ] Typography refinement

### 📋 Planned

- [ ] Loading states & skeletons
- [ ] Form component suite
- [ ] Toast notification system
- [ ] Modal/dialog system
- [ ] Animation library (Framer Motion?)
- [ ] Responsive breakpoints review
- [ ] Mobile UI optimization

---

## Technical Details

### Color System

**Brand Scale (Green):**

```
50:  #ecfdf5  (lightest - hover states)
100: #d1fae5
200: #a7f3d0
300: #6ee7b7
400: #4dd796  (secondary actions)
500: #3ecf8e  ★ Primary brand color
600: #2fb87a  (hover state)
700: #26a269
800: #1e8b5c
900: #166d47  (darkest - text on light)
950: #0d4530
```

**Neutral Scale (Slate):**

```
Background hierarchy:
--bg           (#0d1117) - Main canvas
--bg-200       (#050608) - Deepest wells
--bg-alternative (#161b22) - Elevated surfaces
--bg-surface-100 (#161b22) - Cards, panels
--bg-surface-200 (#21262d) - Nested elevation
--bg-surface-300 (#2d333b) - Highest elevation

Text hierarchy:
--text         (#f1f5f9) - Primary text
--text-light   (#c9d1d9) - Secondary text
--text-lighter (#8b949e) - Tertiary text
--text-muted   (#6e7781) - Muted text

Borders:
--border       (#30363d) - Default borders
--border-muted (#21262d) - Subtle separators
```

### Animation Standards

**Timing Functions:**

- Default transitions: `150ms ease-out`
- Hover states: `200ms ease`
- Layout changes: `300ms ease-in-out`
- Modal enter/exit: `250ms ease-out`

**Keyframes:**

```css
@keyframes workflow-pulse {
  0%,
  100% {
    box-shadow: 0 0 0 0 rgba(62, 207, 142, 0.4);
    border-color: rgb(62, 207, 142);
  }
  50% {
    box-shadow: 0 0 12px 4px rgba(62, 207, 142, 0.3);
    border-color: rgb(110, 231, 183);
  }
}
```

### Tailwind Customization

**Custom Classes:**

```css
.custom-scrollbar {
  /* Refined scrollbar styling */
}

.line-clamp-2 {
  /* Text truncation utility */
}

.theme-bg-elevated {
  background: var(--bg-surface-100);
}

.theme-text-primary {
  color: var(--text);
}
```

---

## Migration Guidelines

### For New Components

1. Use semantic CSS variables (`var(--bg)`, `var(--text)`)
2. Use `brand-XXX` Tailwind classes, NOT `felix-XXX`
3. Follow Supabase patterns: generous spacing, subtle borders
4. Include hover/focus states
5. Test in dark theme (default)

### For Existing Components

1. Replace inline styles with CSS variables where possible
2. Update `felix-` classes to `brand-` classes
3. Review spacing (increase padding/margins)
4. Refine borders (reduce opacity, increase radius)
5. Test before/after visually

### Code Review Checklist

- [ ] No hardcoded colors (use variables/Tailwind)
- [ ] No `felix-` classes remaining
- [ ] Consistent spacing (8px increments)
- [ ] Hover states defined
- [ ] Focus states for interactive elements
- [ ] Accessible contrast ratios (WCAG AA minimum)
- [ ] Responsive on smaller screens

---

## Design References

### External Resources

- [Supabase Design System](https://supabase-design-system.vercel.app/design-system/docs)
- [Tailwind CSS Palette](https://tailwindcss.com/docs/customizing-colors)
- [GitHub Primer Design](https://primer.style/) - Dark theme inspiration
- [Radix UI](https://www.radix-ui.com/) - Accessible components

### Internal Files

- `app/frontend/styles/tokens.css` - Design token reference
- `app/frontend/index.html` - Tailwind config
- `app/frontend/components/` - Component examples

---

## Testing Strategy

### Visual Regression

1. Take screenshots before changes
2. Apply migration
3. Compare screenshots
4. Verify consistency

### Manual Testing

- [ ] Dark theme rendering
- [ ] Color contrast (Chrome DevTools)
- [ ] Interactive states (hover, focus, active)
- [ ] Loading states
- [ ] Error states
- [ ] Empty states
- [ ] Mobile viewport (responsive)

### Accessibility Testing

- [ ] Keyboard navigation
- [ ] Screen reader labels
- [ ] Focus indicators
- [ ] Color contrast ratios
- [ ] ARIA attributes

---

## Migration Timeline

**Phase 1 (Foundation):** ✅ Completed February 2026

- Design tokens established
- CSS architecture refactored
- Color migration completed

**Phase 2 (Components):** 🔄 Current (Est. 2-3 weeks)

- Sidebar, cards, buttons, badges, typography

**Phase 3 (Advanced):** 📋 Planned (Est. 2-3 weeks)

- Loading states, forms, toasts, modals

**Total Estimated Completion:** March 2026

---

## Notes & Decisions

### Why Green Over Purple?

- Supabase's green is distinctive and modern
- Green conveys growth, stability, success
- Better contrast against dark backgrounds
- Industry trend toward green in developer tools

### Why Keep Inter + Fira Code?

- Inter is highly readable at small sizes
- Fira Code has excellent programming ligatures
- Both are industry-standard
- No need to change what works

### Why Modular CSS?

- Better organization and maintainability
- Easier to understand design system
- Allows tree-shaking in production builds
- Cleaner HTML files

### Why Backward Compatibility?

- Avoid breaking existing functionality
- Allow gradual migration
- Reduce risk of bugs
- Enable A/B testing if needed

---

## Future Considerations

### Light Theme

- Currently dark theme only
- Light theme tokens already defined
- Toggle mechanism TBD
- May implement in Q2 2026

### Design System Documentation

- Consider Storybook for component library
- Interactive design token explorer
- Usage guidelines for contributors
- Automated visual regression testing

### Performance

- CSS bundle size monitoring
- Critical CSS extraction
- Unused style removal
- Animation performance profiling

---

## Contact & Feedback

For questions or suggestions about the UI migration:

- Review this document
- Check design token definitions in `tokens.css`
- Reference Supabase design system documentation
- Test changes thoroughly before committing

**Last Updated:** February 9, 2026
