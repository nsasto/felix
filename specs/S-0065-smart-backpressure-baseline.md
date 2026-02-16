# S-0065: Smart Backpressure with Test Baseline Comparison

**Priority:** High  
**Tags:** Testing, Agent, Quality, Infrastructure

## Description

As a Felix developer, I need the backpressure validation system to distinguish between pre-existing test failures and new regressions introduced by changes, so that agents don't get blocked by unrelated infrastructure issues while still catching actual regressions.

## Problem Statement

The current backpressure system blocks requirement completion if ANY test fails after changes, even if those failures existed before the agent started work. This causes:

- False positive blocks from pre-existing infrastructure issues (e.g., Vitest worker timeouts)
- Wasted agent retry attempts on non-regressions
- Developer frustration when requirements are blocked despite correct implementation
- Inability to make progress when baseline has flaky tests

## Dependencies

- S-0001 (Felix Agent Executor) - requires agent execution framework
- S-0005 (Validation Driven Completion) - requires validation infrastructure

## Acceptance Criteria

### Baseline Capture

- [ ] Agent runs test suite at start of requirement (before planning phase)
- [ ] Baseline results stored in runs/{run-id}/baseline-tests.json
- [ ] Baseline captures: passed count, failed count, test names, exit code
- [ ] Baseline includes timestamp and test command used
- [ ] Failed tests in baseline logged as warnings, not errors
- [ ] Baseline failure does not prevent agent from starting work

### Final Test Comparison

- [ ] Agent runs test suite after completion (existing behavior)
- [ ] Final results stored in runs/{run-id}/final-tests.json
- [ ] Comparison logic detects: new failures, fixed tests, unchanged failures
- [ ] Comparison stored in runs/{run-id}/test-regression-analysis.json

### Smart Blocking Logic

- [ ] Block requirement if new test failures introduced (tests passing in baseline, failing in final)
- [ ] Block requirement if previously passing tests now fail
- [ ] Allow requirement if all failures existed in baseline (with warning)
- [ ] Allow requirement if failures fixed (with success message)
- [ ] Allow requirement if test count increased (new tests added and passing)

### Reporting

- [ ] Baseline warnings show pre-existing failures: "⚠️ Baseline: 3 tests failing (pre-existing)"
- [ ] Regression errors clearly identify new failures: "❌ Regression: 2 new test failures"
- [ ] Success messages highlight improvements: "✅ Fixed 3 previously failing tests"
- [ ] Backpressure log shows comparison details
- [ ] Run report includes test delta summary

### Test Result Parsing

- [ ] Parse backend test output (pytest format) for test names and counts
- [ ] Parse frontend test output (vitest format) for test names and counts
- [ ] Extract test names from pytest verbose output
- [ ] Extract test names from vitest output
- [ ] Handle test output format variations gracefully
- [ ] Store raw output for debugging if parsing fails

### Edge Cases

- [ ] Handle baseline test timeout without blocking requirement start
- [ ] Handle final test timeout (treat as failure, trigger retry)
- [ ] Handle missing baseline file (fall back to current behavior with warning)
- [ ] Handle test count mismatch (tests added/removed) intelligently
- [ ] Handle flaky tests (pass/fail inconsistently) with configurable tolerance

### Configuration

- [ ] Config option backpressure.baseline_enabled (defaults to true)
- [ ] Config option backpressure.baseline_timeout_sec (defaults to 300)
- [ ] Config option backpressure.allow_flaky_tests (defaults to false)
- [ ] Config option backpressure.flaky_tolerance (defaults to 1 retry)
- [ ] Environment variable overrides: FELIX_BACKPRESSURE_BASELINE

## Validation Criteria

- [ ] Manual test - introduce pre-existing test failure, verify agent doesn't block on unrelated change
- [ ] Manual test - introduce new test failure, verify agent blocks correctly
- [ ] Manual test - fix pre-existing failure, verify success message
- [ ] Check runs/{run-id}/baseline-tests.json contains test results
- [ ] Check runs/{run-id}/test-regression-analysis.json shows comparison

## Technical Notes

**Architecture:** The baseline capture should happen in the validation phase before planning begins. Store structured JSON with enough detail to diff test names, not just counts. Use test name matching to identify specific new failures.

**Test Parsing:** Different test frameworks have different output formats. Use regex patterns to extract test names from both pytest and vitest output. Store raw output as fallback for manual inspection.

**Performance:** Baseline adds one extra test run (~1-2 minutes overhead). This is acceptable given it prevents false blocks and wasted retry cycles.

**Flaky Tests:** Consider marking known flaky tests in a configuration file (.felix/flaky-tests.json) so they can be handled specially. This is optional enhancement for Phase 2.

**Don't assume not implemented:** Check if any baseline logic exists in felix-agent.ps1 backpressure section. May have partial implementation or different approach.

## Example Scenarios

### Scenario 1: Pre-existing failure (should NOT block)

```
Baseline: 192 passed, 1 failed (test_vitest_runner_timeout)
Changes: Add SQL migration file
Final: 192 passed, 1 failed (test_vitest_runner_timeout)
Result: ✅ ALLOW - no regression detected, 1 pre-existing failure
```

### Scenario 2: New regression (SHOULD block)

```
Baseline: 193 passed, 0 failed
Changes: Modify API endpoint
Final: 192 passed, 1 failed (test_api_endpoint_handler)
Result: ❌ BLOCK - new regression: test_api_endpoint_handler
```

### Scenario 3: Fixed pre-existing issue (should celebrate)

```
Baseline: 192 passed, 1 failed (test_vitest_runner_timeout)
Changes: Upgrade vitest, fix test config
Final: 193 passed, 0 failed
Result: ✅ ALLOW - fixed 1 test! 🎉
```

## Non-Goals

- Automatic flaky test detection (would require multiple runs)
- Integration with external CI systems
- Historical test trend analysis
- Test coverage metrics
- Performance benchmarking integration
