# Building Mode Prompt

You are operating in **building mode**.

## Your Responsibilities

- Select exactly ONE incomplete task from `IMPLEMENTATION_PLAN.md`
- Inspect existing code BEFORE implementing (don't duplicate functionality)
- Implement that single task
- Mark the task complete in `IMPLEMENTATION_PLAN.md` (change `- [ ]` to `- [x]`)
- Update requirement status in `felix/requirements.json` if needed

## Rules

1. **One task per iteration** - implement ONLY one item, then exit
2. **Investigate before implementing** - search codebase for existing implementations
3. **Update plan after implementing** - change `- [ ]` to `- [x]` for completed items
4. **Update requirements status** - if completing a requirement, set status to `done`
5. **Exit cleanly** - output a run report summarizing what was done

## Workflow

1. Read `IMPLEMENTATION_PLAN.md` to find the next incomplete task (`- [ ]`)
2. Select the FIRST incomplete task in priority order (top to bottom)
3. Read relevant specs from `specs/` for context
4. Search codebase for existing implementations (use Grep/Glob tools)
5. Implement the task (create/edit files as needed)
6. After implementation, update `IMPLEMENTATION_PLAN.md`:
   - Change `- [ ] <task>` to `- [x] <task>` using the Edit tool
7. If this completes a requirement, update `felix/requirements.json`:
   - Set `status: "done"` for completed requirements
   - Update `updated_at` to today's date
8. Output a run report

## Task Selection

Parse `IMPLEMENTATION_PLAN.md` to find tasks marked with `- [ ]` (incomplete).
Select the first one in the file that:
- Is not blocked by dependencies
- Belongs to the current requirement (see context below)

## Run Report Format

After completing the task, output a brief summary:

```
## Run Report

**Task Completed:** [brief description of task]

**Summary:**
- What was implemented
- Files modified
- Any notable decisions

**Outcome:** ✅ SUCCESS or ❌ BLOCKED (with reason)
```

## Backpressure Note

The Felix agent will automatically run tests/build/lint after your changes.
You do NOT need to run them yourself. Focus on implementation only.

## Completion Signal

When you have completed the task and updated the plan, you may include:
`<promise>COMPLETE</promise>`

This signals to the agent that you're done with this iteration.
