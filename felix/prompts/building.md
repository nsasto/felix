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

1. **FIRST: Activate virtual environment if working with Python backend**
   - Check if `.venv` or `venv` directory exists in the project
   - Activate it before running any Python commands: `.venv\Scripts\Activate.ps1` (Windows) or `source .venv/bin/activate` (Unix)
   - Ensure all Python commands run within the activated environment
2. Read the implementation plan from context (loaded from `runs/<run-id>/plan-<requirement-id>.md`)
3. Select the FIRST incomplete task (`- [ ]`) in priority order
4. Read relevant context from specs and AGENTS.md
5. Search codebase for existing implementations (use Grep/Glob tools)
6. Implement the task (create/edit files as needed)
7. After implementation, update the plan at the path specified in context:
   - Change `- [ ] <task>` to `- [x] <task>` using the Edit tool
8. If this completes the requirement, update `felix/requirements.json`:
   - Set `status: "done"` for the requirement
   - Update `updated_at` to today's date
9. Output a run report

## Task Selection

The implementation plan is provided in context (from `runs/<run-id>/plan-<requirement-id>.md`).

Find tasks marked with `- [ ]` (incomplete) and select the first one that:

- Is not blocked by dependencies
- Belongs to the current requirement

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
