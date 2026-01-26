# S-0009: Light Theme

## Narrative

As a Felix user working in bright environments or preferring lighter interfaces, I need a light theme option in addition to the default dark theme, so that I can reduce eye strain and match my system preferences throughout the day.

## Acceptance Criteria

### Theme Toggle in Settings

- [ ] Theme selection dropdown appears in General settings category
- [ ] Options: "Dark" (default), "Light", "System" (follows OS preference)
- [ ] Selected theme saved to felix/config.json under ui.theme
- [ ] Theme change applies immediately without page refresh
- [ ] Theme preference persists across sessions

### Light Theme Color Palette

- [ ] Background colors: white/light gray gradient (#ffffff, #f6f8fa, #f0f2f5)
- [ ] Text colors: dark gray/black (#24292f, #57606a, #6e7781)
- [ ] Border colors: light gray (#d0d7de, #e1e4e8)
- [ ] Primary accent: Felix purple adjusted for light backgrounds
- [ ] Hover states: subtle gray overlays
- [ ] Active/selected states: light purple/blue tints

### Component Theme Support

- [ ] Sidebar navigation updates with light theme colors
- [ ] Project cards render with light backgrounds and dark text
- [ ] Kanban board columns and cards adapt to light theme
- [ ] Specs editor updates: light editor background, dark syntax highlighting
- [ ] Settings screen renders in light theme
- [ ] Agent controls panel uses light theme styling
- [ ] Modal dialogs and overlays adapt theme
- [ ] Buttons and inputs styled for light theme

### Theme Consistency

- [ ] All hardcoded dark colors (#0d1117, #161b22, etc.) replaced with theme variables
- [ ] Tailwind classes updated to use theme-aware utilities
- [ ] Custom scrollbar styles adapt to theme
- [ ] Shadows and elevation adjusted for light backgrounds
- [ ] Icon colors contrast appropriately in both themes

### System Theme Detection

- [ ] "System" option detects OS theme preference
- [ ] Theme updates automatically when OS theme changes
- [ ] Fallback to dark theme if system preference unavailable
- [ ] Works on Windows, macOS, and Linux

### Visual Feedback

- [ ] Theme switch provides immediate visual feedback
- [ ] No flash of wrong theme on page load
- [ ] Smooth transition between themes (200-300ms fade)
- [ ] Loading states visible in both themes
- [ ] Error states readable in both themes

## Technical Notes

**Architecture:** Implement theme system using CSS custom properties (CSS variables) and React context. Store theme preference in felix/config.json and sync via backend API.

**Implementation Approach:**

1. Create ThemeProvider context wrapping App component
2. Define CSS custom properties for both themes in global CSS
3. Apply theme class to root element (`<html>` or `<body>`)
4. Replace hardcoded Tailwind colors with theme-aware classes
5. Add theme toggle in General settings with save to backend

**Color System:**

Dark theme (current):

- Background: #0d1117, #161b22, #21262d
- Text: #c9d1d9, #8b949e
- Border: slate-800/60
- Accent: Felix purple (#a78bfa, #8b5cf6)

Light theme (new):

- Background: #ffffff, #f6f8fa, #f0f2f5
- Text: #24292f, #57606a, #6e7781
- Border: #d0d7de, #e1e4e8
- Accent: Felix purple (darker variants for contrast)

**Config Update:** Add to felix/config.json:

```json
{
  "ui": {
    "theme": "dark" | "light" | "system"
  }
}
```

**Don't assume not implemented:** Check if any theme-switching logic or CSS variables already exist. Look for existing Tailwind theme configuration in tailwind.config.js.

## Dependencies

- S-0007 (Settings Screen) - theme toggle appears in General settings
- S-0003 (Frontend Observer UI) - all UI components need theme support

## Non-Goals

- Custom theme creation (user-defined colors)
- Multiple color accent options
- Per-project theme preferences
- High contrast accessibility themes (separate requirement)
- Theme marketplace or sharing

## Validation Criteria

- [ ] Theme dropdown appears in General settings: Open settings, verify theme selector
- [ ] Dark theme is default: Fresh install shows dark theme
- [ ] Light theme applies correctly: Select Light, verify all components update
- [ ] Theme persists: Refresh page, verify theme remains selected
- [ ] System theme detection works: Select System, change OS theme, verify Felix updates
- [ ] All components readable: Navigate all screens in light theme, verify no contrast issues
- [ ] Theme transitions smoothly: Switch themes, verify smooth fade without flashing
