# Task Completion Verification

You are verifying if all implementation tasks in a plan are complete.

## Your Job

Read the plan below and answer ONE question:

**Are all tasks under the `## Tasks` section marked as complete (`- [x]`)?**

## Rules

1. ONLY check tasks under `## Tasks` heading
2. IGNORE all other sections (Overview, Technical Notes, Dependencies, Acceptance Criteria, etc.)
3. Sub-tasks (indented under a main task) count as part of that task
4. A task is complete ONLY if the checkbox is `- [x]`
5. If ANY task shows `- [ ]`, answer NO

## Response Format

Respond with ONLY ONE of these signals:

- `<verification>TASKS_COMPLETE</verification>` - All tasks are `[x]`
- `<verification>TASKS_INCOMPLETE</verification>` - Some tasks are still `[ ]`

Include a one-line reason after the signal.

---

## Plan to Verify

{PLAN_CONTENT}
