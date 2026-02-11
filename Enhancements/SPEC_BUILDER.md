# Spec Builder - Bidirectional Sync Architecture

This document describes the bidirectional sync system between markdown specification files and database metadata in the Felix requirements management system.

## Overview

The spec builder provides real-time synchronization between:

- **Markdown files** (`specs/*.md`) - Source of truth for specification content
- **Database metadata** (Supabase) - Source of truth for workflow state and searchable fields

Users can edit either the markdown or the metadata UI, and changes are automatically synchronized to the other side.

## Design Principles

1. **Auto-sync on user edits** - No manual sync buttons needed for normal workflow
2. **Track sync source** - Prevent false conflict warnings when user just made an edit
3. **Per-field conflict resolution** - Let users resolve mismatches field-by-field
4. **Status is workflow-only** - Status field is never synced to markdown (it's live state, not spec content)
5. **Debounced markdown parsing** - 500ms debounce before syncing markdown → metadata

## Syncable Fields

| Field            | Markdown Location         | Metadata Field           | Example                         |
| ---------------- | ------------------------- | ------------------------ | ------------------------------- |
| **Title**        | `# S-XXXX: Title`         | `requirement.title`      | `# S-0042: Frontend API Client` |
| **Priority**     | `**Priority:** High`      | `requirement.priority`   | Low, Medium, High, Critical     |
| **Tags**       | `## Tags` section or `**Tags**` line | `requirement.tags`     | `["backend", "api"]`            |
| **Dependencies** | `## Dependencies` section | `requirement.depends_on` | `["S-0001", "S-0002"]`          |

### Excluded from Sync

- **Status** - Workflow state only (planned, in_progress, blocked, complete, done)
  - Lives only in database
  - Changes via Kanban board or metadata panel
  - Never written to markdown

## Auto-Sync Behavior

### Metadata → Markdown (Immediate)

When user edits metadata via the UI:

```typescript
handleMetadataUpdate(field, value)
  ↓
1. Set lastSyncSource = 'metadata'
2. Update database via API
3. Immediately update markdown content
   - replaceTitle() / replacePriority() / replaceTags() / replaceDependenciesSection()
4. No conflict warning shown
```

**Example:** User changes priority from "Medium" to "High" in dropdown → Markdown is immediately updated with `**Priority:** High`

### Markdown → Metadata (Debounced)

When user types in markdown editor:

```typescript
useEffect on specContent change
  ↓
1. Skip if lastSyncSource === 'metadata' (within 2 seconds)
2. Wait 500ms (debounce)
3. Parse all syncable fields from markdown
4. Compare with current metadata
5. For each changed field:
   - Update database via API
   - Set lastSyncSource = 'markdown'
6. No conflict warning shown
```

**Example:** User types `**Priority:** Critical` in markdown → After 500ms, database is updated with priority="critical"

## Conflict Detection & Resolution

### When Conflicts Appear

Mismatch warnings only appear when:

- **External changes** occur (Supabase realtime updates from another user/session)
- **File reloads** where markdown and metadata diverged
- User's own edits are **never** flagged (5-second grace period after sync)

### Conflict Resolution UI

Each mismatched field gets its own warning card:

```
┌─────────────────────────────────────────────────┐
│ ⚠️  Priority mismatch: priority                 │
│                                                  │
│ Markdown: high                                   │
│ Metadata: medium                                 │
│                                                  │
│ [→ Use Markdown] [← Use Metadata] [⊘ Ignore]   │
└─────────────────────────────────────────────────┘
```

**Actions:**

- **→ Use Markdown** - Sync markdown value to metadata (calls `syncField('markdown-to-metadata', field)`)
- **← Use Metadata** - Sync metadata value to markdown (calls `syncField('metadata-to-markdown', field)`)
- **⊘ Ignore** - Dismiss warning for this field (adds to `dismissedFields` set)

### Per-Field Dismissal

Each field can be independently dismissed:

- Clicking ignore adds field to `dismissedFields` set
- Field won't show warnings until next external change
- Resolved conflicts are automatically removed from dismissed set

## Implementation Details

### File Structure

```
app/frontend/
├── utils/
│   └── specParser.ts          # Parsing & replacement functions
├── components/
│   ├── SpecEditorPage.tsx     # Sync orchestration & state
│   ├── SpecMetadataPanel.tsx  # Metadata UI & conflict warnings
│   └── SpecSidebarTabs.tsx    # Props wiring
```

### Key Functions in specParser.ts

**Parsing (Markdown → Values):**

```typescript
parseTitle(markdown: string): string
parsePriority(markdown: string): string
parseLabels(markdown: string): string[]
parseSpecDependencies(markdown: string): string[]
```

**Replacement (Values → Markdown):**

```typescript
replaceTitle(markdown: string, title: string): string
replacePriority(markdown: string, priority: string): string
replaceTags(markdown: string, tags: string[]): string
replaceDependenciesSection(markdown: string, deps: string[]): string
```

**Validation:**

```typescript
validateSpecMetadata(
  requirement: Requirement,
  markdown: string
): ValidationIssue[]
```

Returns array of issues, one per mismatched field:

```typescript
interface ValidationIssue {
  field: SyncableField; // 'title' | 'priority' | 'tags' | 'depends_on'
  type: "mismatch";
  message: string; // e.g., "Priority mismatch"
  markdownValue: any; // Parsed from markdown
  metadataValue: any; // From database
}
```

### Sync State in SpecEditorPage.tsx

```typescript
// Track sync source to prevent false warnings
const [lastSyncSource, setLastSyncSource] = useState<
  "metadata" | "markdown" | null
>(null);
const [lastSyncTimestamp, setLastSyncTimestamp] = useState<number>(0);

// Track dismissed fields per session
const [dismissedFields, setDismissedFields] = useState<Set<string>>(new Set());
```

**Grace Periods:**

- **2 seconds** after metadata sync - Skip markdown → metadata auto-sync
- **5 seconds** after any sync - Skip validation (no warnings)

### Core Sync Function

```typescript
const syncField = async (
  direction: "markdown-to-metadata" | "metadata-to-markdown",
  field: SyncableField,
) => {
  // 1. Set sync source & timestamp
  setLastSyncSource(
    direction === "markdown-to-metadata" ? "markdown" : "metadata",
  );
  setLastSyncTimestamp(Date.now());

  // 2. Remove from dismissed
  setDismissedFields((prev) => {
    const next = new Set(prev);
    next.delete(field);
    return next;
  });

  // 3. Sync in chosen direction
  if (direction === "markdown-to-metadata") {
    const value = parseField(specContent, field);
    await handleMetadataUpdate(field, value);
  } else {
    const updatedMarkdown = replaceField(
      specContent,
      field,
      requirement[field],
    );
    onContentChange(updatedMarkdown);
  }
};
```

## Markdown Format Specifications

### Title

```markdown
# S-XXXX: Title Text Here
```

- Must start with `# S-` followed by 4 digits, colon, and title
- Title parsed from capture group after colon
- Replacement preserves spec ID

### Priority

```markdown
**Priority:** High
```

- Format: `**Priority:**` followed by value
- Values: Low, Medium, High, Critical (case-insensitive in markdown)
- If missing, defaults to "medium"
- Auto-added after title if not present

### Tags

```markdown
## Tags

- backend
- api
- high-priority
```

Alternative (empty):

```markdown
## Tags

None
```

Inline alternative (single line):

```markdown
**Tags** backend, api
```

- Bullet list (`- item`) under `## Tags` heading
- Empty section shows "None"
- Auto-created after Dependencies section if missing

### Dependencies

```markdown
## Dependencies

- S-0001
- S-0042
```

Alternative (empty):

```markdown
## Dependencies

None
```

- Bullet list of spec IDs (S-XXXX pattern)
- Parser extracts all S-XXXX patterns from section
- Empty section shows "None"

## Edge Cases

### Multi-User Editing

**Scenario:** Two users edit same spec simultaneously

1. User A edits metadata (priority: high)
2. User B edits markdown (priority: critical)
3. Supabase realtime sends B's update to A
4. A sees conflict warning: "Priority mismatch"
5. A chooses resolution direction

**Prevention:**

- Each user's own edits auto-sync immediately
- Only external changes trigger warnings
- Per-field resolution prevents full file conflicts

### Rapid Markdown Typing

**Scenario:** User types quickly in markdown editor

1. User types "**Priority:** H"
2. 500ms debounce timer starts
3. User continues typing "ig"
4. Timer resets (new 500ms)
5. User finishes typing "h"
6. After 500ms idle, sync occurs

**Result:** Only final complete value syncs to database

### Missing Sections

**Scenario:** Old spec file missing `## Tags` section

1. Parser returns empty array: `parseLabels() → []`
2. User adds tag in UI: `tags = ["backend"]`
3. `replaceTags()` adds section:

   ```markdown
   ## Dependencies

   - S-0001

   ## Tags

   - backend
   ```

4. Section inserted after Dependencies

### Malformed Markdown

**Scenario:** User manually edits markdown with typo

```markdown
**Priortiy:** High # Typo: "Priortiy"
```

1. `parsePriority()` fails to match, returns default "medium"
2. If metadata has "high", validation detects mismatch
3. Conflict warning shows: Markdown="medium", Metadata="high"
4. User can choose to fix with "Use Metadata" button

## Testing Considerations

### Unit Tests (specParser.ts)

```typescript
describe("parseTitle", () => {
  it("extracts title from spec heading", () => {
    const md = "# S-0042: Frontend API Client";
    expect(parseTitle(md)).toBe("Frontend API Client");
  });
});

describe("replaceTags", () => {
  it("adds Tags section if missing", () => {
    const result = replaceTags(originalMd, ["api", "backend"]);
    expect(result).toContain("## Tags\n\n- api\n- backend");
  });
});
```

### Integration Tests

```typescript
describe("Auto-sync metadata → markdown", () => {
  it("updates markdown when priority changed in UI", async () => {
    await handleMetadataUpdate("priority", "critical");
    expect(specContent).toContain("**Priority:** Critical");
    expect(validationIssues).toHaveLength(0); // No warning
  });
});

describe("Auto-sync markdown → metadata", () => {
  it("updates database when markdown edited", async () => {
    onContentChange("**Priority:** Low");
    await waitFor(600); // Wait for debounce
    expect(mockApi.updateRequirementMetadata).toHaveBeenCalledWith(
      projectId,
      reqId,
      "priority",
      "low",
    );
  });
});
```

## Future Enhancements

### Potential Additions

1. **Sync History** - Track sync events for debugging
2. **Conflict Auto-Resolution** - Configurable rules (always prefer markdown/metadata)
3. **Bulk Sync** - Sync all specs in project
4. **Offline Support** - Queue syncs when offline, apply when reconnected
5. **Description Field** - Sync spec description/narrative section
6. **Assignee Field** - If we add user assignments

### Performance Optimization

- **Differential sync** - Only sync changed fields, not all fields
- **Batch updates** - Combine multiple field updates into single API call
- **WebSocket sync** - Use WebSocket for immediate bidirectional updates
- **Optimistic UI** - Update UI before API response

## Troubleshooting

### Sync Not Working

**Symptoms:** Changes in metadata don't appear in markdown

**Checks:**

1. Verify `lastSyncSource` is being set
2. Check browser console for errors
3. Verify replacement functions return updated markdown
4. Check if `onContentChange` is called

**Debug:**

```typescript
console.log("Syncing field:", field, "value:", value);
console.log("Updated markdown:", updatedMarkdown);
```

### False Conflict Warnings

**Symptoms:** User edits show as conflicts

**Checks:**

1. Verify `lastSyncTimestamp` is being updated
2. Check grace period calculation (should be < 5000ms)
3. Verify validation useEffect dependencies include sync state

**Fix:**

```typescript
const isRecentEdit = lastSyncSource && Date.now() - lastSyncTimestamp < 5000;
if (isRecentEdit) {
  setValidationIssues([]);
  return;
}
```

### Sync Loops

**Symptoms:** Infinite sync back-and-forth

**Cause:** Auto-sync not checking sync source

**Prevention:**

```typescript
// In markdown → metadata auto-sync:
if (lastSyncSource === "metadata" && Date.now() - lastSyncTimestamp < 2000) {
  return; // Skip - we just synced FROM metadata
}
```

## Summary

The bidirectional sync system provides seamless integration between markdown files and database metadata:

- ✅ **Automatic** - No manual sync buttons in normal workflow
- ✅ **Intelligent** - Tracks sync source to prevent false warnings
- ✅ **Granular** - Per-field conflict resolution
- ✅ **Safe** - Status field excluded from sync
- ✅ **Performant** - Debounced parsing, optimistic updates

Users can work in either markdown or UI, whichever fits their workflow, and the system keeps everything synchronized automatically.

