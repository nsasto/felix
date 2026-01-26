# S-0005: Validation-Driven Completion

## Narrative

As the Felix agent, I need to verify that requirements are actually working before marking them complete, so that completion is based on passing tests and validation rather than just plan checklist progress.

Currently, Felix signals `<promise>COMPLETE</promise>` when all plan tasks are checked off, but doesn't verify the code actually works. This breaks the Ralph methodology's core principle: backpressure is non-negotiable.

## Problem

Without validation-driven completion:

- Felix can claim completion with broken code
- No feedback loop to catch regressions
- Human must manually verify every requirement
- Loses autonomous delivery benefits

## Solution

Implement validation as the gatekeeper for requirement completion:

1. **Validation Runner**: Execute test/build commands from AGENTS.md for the current requirement
2. **Acceptance Criteria Verification**: Parse and verify acceptance criteria from spec files
3. **Auto-update requirements.json**: Mark requirement "complete" only when validation passes
4. **Stuck Signal**: Emit `<promise>STUCK</promise>` when tasks done but validation fails

## Acceptance Criteria

- [ ] `scripts/validate-requirement.py` exists and can be invoked with requirement ID
- [ ] Script reads acceptance criteria from spec file (markdown checklist under "## Validation Criteria" or "## Acceptance Criteria")
- [ ] Script executes validation commands based on requirement labels (backend → pytest, frontend → npm test)
- [ ] Script returns exit code 0 on success, 1 on failure
- [ ] felix-agent.ps1 calls validation after all plan tasks complete
- [ ] felix-agent.ps1 auto-updates requirements.json status to "complete" on validation pass
- [ ] felix-agent.ps1 emits `<promise>STUCK</promise>` on validation failure
- [ ] AGENTS.md includes "## Validate Requirement" section with validation command examples
- [ ] All existing specs (S-0001 through S-0004) include testable criteria (in "## Validation Criteria" or "## Acceptance Criteria" section)

## Technical Details

### Validation Flow in Building Mode

```
Plan task complete → Run validation → Pass?
  ├─ Yes → Continue to next task
  └─ No → Log failure, stay on task

All tasks complete → Run final validation → Pass?
  ├─ Yes → Update requirements.json to "complete", emit COMPLETE
  └─ No → Emit STUCK, stay in_progress
```

### Acceptance Criteria Format

Specs should use markdown checklist format. Use "## Validation Criteria" for testable CLI commands, or "## Acceptance Criteria" for feature-level requirements:

```markdown
## Validation Criteria

- [ ] Backend starts: `python app/backend/main.py` (exit code 0)
- [ ] Health endpoint responds: `curl http://localhost:8080/health` (status 200)
- [ ] Tests pass: `cd app/backend && python -m pytest` (exit code 0)
```

### Validation Script Behavior

```python
# py -3 scripts/validate-requirement.py S-0002
# 1. Parse specs/S-0002-*.md for acceptance criteria
# 2. Execute each criterion's command
# 3. Verify expected outcomes
# 4. Return 0 if all pass, 1 if any fail
```

## Non-Goals

- Complex test orchestration (just run commands from AGENTS.md)
- Test generation (specs define acceptance criteria manually)
- Coverage requirements (pass/fail is binary)

## Dependencies

None - this is foundational infrastructure needed by all requirements.

## Labels

`foundation`, `validation`, `agent`
