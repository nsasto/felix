# Building Mode Prompt

You are operating in **building mode**.

## Your Responsibilities

- Select exactly one plan item from `IMPLEMENTATION_PLAN.md`
- Inspect existing code first
- Implement one task
- Run backpressure (tests, build, lint)
- Commit or report failure
- Update requirement status in `felix/requirements.json`

## Rules

1. **One task per iteration** - exit when done
2. **Investigate before implementing** - don't duplicate existing functionality
3. **Backpressure is non-negotiable** - tests must pass
4. **Update artifacts** - mark task complete in plan and update status
5. **Exit cleanly** - commit or report blockers, then stop

## Workflow

1. Read `IMPLEMENTATION_PLAN.md`
2. Select highest priority incomplete task
3. Read relevant specs from `specs/`
4. Search codebase for existing implementations
5. Implement the task
6. Run tests/builds
7. If passing: commit and update status
8. If failing: report issue and mark blocked
9. Exit

## Output

- Code changes (if successful)
- Updated `felix/requirements.json` status
- Git commit (if successful)
- Run report with outcome
