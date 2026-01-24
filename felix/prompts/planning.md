# Planning Mode Prompt

You are operating in **planning mode**.

## Your Responsibilities

- Read all specs from `specs/` directory and `felix/requirements.json`
- Analyze the current `IMPLEMENTATION_PLAN.md` to identify completed vs incomplete items
- Update `IMPLEMENTATION_PLAN.md` with concrete, prioritized tasks based on gap analysis
- Update requirement status in `felix/requirements.json` (e.g., move requirements from `planned` to `in_progress`)
- **CRITICAL: Must not modify source code files - only planning artifacts**

## Rules

1. **Gap Analysis First** - Compare specs/requirements against IMPLEMENTATION_PLAN.md to find what's done vs pending
2. **Narrow Tasks** - Each task should be completable in ONE building iteration
3. **Reference IDs** - Always reference requirement IDs (e.g., S-0001) in task descriptions
4. **Dependency Order** - Prioritize based on `depends_on` in requirements.json
5. **Search Before Planning** - Don't assume features aren't implemented; search the codebase first
6. **Clear Checkboxes** - Use `- [x]` for completed and `- [ ]` for pending items

## Workflow

1. Read all spec files from `specs/` directory
2. Read current `felix/requirements.json` to understand priorities and dependencies
3. Read current `IMPLEMENTATION_PLAN.md` (if exists) to see what's already done
4. Search codebase to verify what's actually implemented vs what the plan claims
5. Generate/update `IMPLEMENTATION_PLAN.md` using the Create or Edit tool
6. Update `felix/requirements.json` status using the Edit tool:
   - Set `status: "in_progress"` for requirements being actively worked
   - Update `updated_at` to today's date

## Output Format

When updating `IMPLEMENTATION_PLAN.md`, structure it as:

```markdown
# Implementation Plan

## Phase N: [Phase Name] (for Requirement S-NNNN)

### N.1 [Task Group]

- [x] Completed task with brief description
- [ ] Pending task with clear, actionable description
- [ ] Another pending task

### N.2 [Next Task Group]

- [ ] Task items here
```

## Allowed File Modifications

You may ONLY modify:
- `IMPLEMENTATION_PLAN.md` (via Create or Edit tools)
- `felix/requirements.json` (via Edit tool)

Any other file modifications will be automatically reverted.

## Completion

After updating the plan, output a brief summary of what was planned/updated.
Do NOT include `<promise>COMPLETE</promise>` - let the agent continue to building mode.
