# Felix UI Development Guidelines

**Quick reference for maintaining consistency with our Supabase-inspired design system.**

---

## Component Sources

### Use shadcn/ui Primitives Only

All UI components must use shadcn/ui primitives from `app/frontend/components/ui/`:

- **Button** - All buttons, links, icon buttons
- **Input** - Text inputs, search fields
- **Badge** - Status indicators, tags, labels
- **Card** - Panels, containers, grouped content
- **Dialog / AlertDialog** - Modals, confirmations
- **Select / Switch / Textarea** - Form controls
- **Table** - Data tables
- **Sheet** - Slide-out panels
- **ToggleGroup** - Tab bars, view switchers

**Never create custom UI components.** If you need something not in the list, add the shadcn/ui primitive first.

### Adding New shadcn/ui Components

```bash
# From app/frontend directory
npx shadcn-ui@latest add [component-name]
```

This auto-generates the component in `components/ui/` with proper Tailwind styling.

---

## Styling Rules

### 1. Use CSS Variables from tokens.css

**Always reference tokens - never hardcode colors.**

```tsx
// ✅ CORRECT
<div className="bg-[var(--bg-surface-100)] text-[var(--text)]">

// ❌ WRONG
<div style={{ backgroundColor: '#161b22', color: '#f1f5f9' }}>
```

**Common tokens:**

```css
/* Backgrounds */
--bg                  /* Main canvas */
--bg-surface-100      /* Cards, panels */
--bg-surface-200      /* Nested elevation */

/* Text */
--text                /* Primary text */
--text-light          /* Secondary text */
--text-muted          /* Tertiary text */

/* Brand */
--brand-500           /* Primary green */
--brand-600           /* Hover state */

/* Status */
--status-in-progress  /* Yellow */
--destructive-500     /* Red */
--warning-500         /* Orange */
--success-500         /* Green */
```

### 2. Use Tailwind Brand Classes

For common brand colors, use Tailwind classes:

```tsx
// ✅ CORRECT
<Button className="bg-brand-500 hover:bg-brand-600">Save</Button>

// ❌ WRONG
<Button className="bg-felix-500 hover:bg-felix-600">Save</Button>
```

**Never use `felix-*` classes - all migrated to `brand-*`.**

### 3. No Inline Styles (Unless Mapping Tokens)

```tsx
// ✅ CORRECT
<div className="p-4 rounded-lg border border-[var(--border)]">

// ❌ WRONG
<div style={{ padding: '16px', borderRadius: '8px', border: '1px solid #30363d' }}>
```

### 4. Spacing Scale (8px Base)

Use Tailwind spacing utilities based on 8px increments:

- `p-2` = 8px
- `p-4` = 16px
- `p-6` = 24px
- `p-8` = 32px

---

## Icons

### Use Lucide React Only

All icons must come from Lucide React - no emoji, no inline SVGs.

```tsx
import { IconSettings, IconFolder, IconSparkles } from '@lucide-icons/react';

// ✅ CORRECT
<IconSettings className="w-4 h-4" />

// ❌ WRONG
<span>⚙️</span>
<svg>...</svg>
```

**Common sizes:**

- `w-4 h-4` (16px) - Inline icons, buttons
- `w-5 h-5` (20px) - Navigation, cards
- `w-6 h-6` (24px) - Headers, emphasis

**Browse icons:** [lucide.dev](https://lucide.dev/)

---

## Design Inspiration

### Supabase vs shadcn/ui

**shadcn/ui** - Component implementation source

- Use their components as-is from `components/ui/`
- Don't modify component internals

**Supabase** - Visual design inspiration

- Reference for spacing, colors, layout patterns
- Use for understanding "generous whitespace" aesthetic
- Copy visual hierarchy, not components

**Key principle:** Build with shadcn primitives, style like Supabase.

### Reference Links

- **shadcn/ui Documentation:** [ui.shadcn.com](https://ui.shadcn.com/)
- **Supabase Design System:** [supabase-design-system.vercel.app](https://supabase-design-system.vercel.app/)
- **Lucide Icons:** [lucide.dev](https://lucide.dev/)

---

## Quick Dos and Don'ts

### ✅ DO

- Use shadcn/ui primitives for all UI elements
- Reference CSS variables from `tokens.css`
- Use Lucide React icons with consistent sizing
- Follow 8px spacing scale
- Include hover and focus states
- Use `brand-*` Tailwind classes for green colors
- Keep generous padding and whitespace
- Test in dark theme (default)

### ❌ DON'T

- Create custom button/input/modal components
- Hardcode hex colors anywhere
- Use `felix-*` classes (deprecated)
- Use emoji characters for icons
- Write inline SVG icons
- Use inline `style` attributes (except for direct token mapping)
- Ignore hover/focus states
- Use tight spacing (Supabase = generous)

---

## Code Review Checklist

Before committing UI changes, verify:

- [ ] Uses shadcn/ui primitives (no custom UI components)
- [ ] No inline hex colors (variables only)
- [ ] No `felix-` classes remaining
- [ ] Lucide icons only (no emoji/SVG)
- [ ] Proper spacing (8px base unit)
- [ ] Hover and focus states defined
- [ ] Consistent with existing patterns
- [ ] Tested in dark theme

---

## Component File Locations

```
app/frontend/
├── components/
│   ├── ui/                    # shadcn/ui primitives (DON'T EDIT)
│   │   ├── button.tsx
│   │   ├── input.tsx
│   │   ├── badge.tsx
│   │   └── ...
│   ├── MarkdownEditor.tsx     # Reusable editor component
│   ├── ProjectSelector.tsx    # Feature components
│   └── ...
├── styles/
│   ├── tokens.css            # Design tokens (REFERENCE THIS)
│   ├── base.css              # Base styles, animations
│   └── components.css        # Component-specific styles
└── tailwind.config.cjs       # Tailwind config (brand colors)
```

---

## Examples

### Creating a Card with Button

```tsx
import { Card } from "./components/ui/card";
import { Button } from "./components/ui/button";
import { IconPlus } from "@lucide-icons/react";

function ProjectCard() {
  return (
    <Card className="p-6 bg-[var(--bg-surface-100)] hover:bg-[var(--bg-surface-200)] transition-colors">
      <h3 className="text-[var(--text)] font-semibold mb-2">Project Name</h3>
      <p className="text-[var(--text-muted)] text-sm mb-4">Description text</p>
      <Button className="bg-brand-500 hover:bg-brand-600">
        <IconPlus className="w-4 h-4 mr-2" />
        Add Item
      </Button>
    </Card>
  );
}
```

### Status Badge

```tsx
import { Badge } from "./components/ui/badge";

// Use semantic color variables
<Badge className="bg-[var(--status-in-progress)]/10 text-[var(--status-in-progress)] border-[var(--status-in-progress)]/20">
  In Progress
</Badge>;
```

### Modal Dialog

```tsx
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "./components/ui/dialog";
import { Button } from "./components/ui/button";

function ConfirmDialog({ open, onOpenChange }) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="bg-[var(--bg-surface-200)]">
        <DialogHeader>
          <DialogTitle className="text-[var(--text)]">
            Confirm Action
          </DialogTitle>
        </DialogHeader>
        <div className="flex gap-3 justify-end mt-4">
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button className="bg-brand-500 hover:bg-brand-600">Confirm</Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
```

---

**Last Updated:** February 11, 2026
