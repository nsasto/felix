# S-0006: Spec Edit Safety and Plan Invalidation

## Narrative

As a developer editing specs in the Felix frontend, I need warnings and safeguards when modifying requirements that are actively being worked on, so that I don't inadvertently invalidate in-progress work or create spec/plan drift without realizing it.

## Problem

Currently, users can edit spec files at any time without:

- Knowing if the requirement is actively being worked on
- Understanding the impact on existing plans
- Being prompted to invalidate stale plans when acceptance criteria change
- Visual indicators showing spec/plan drift

This leads to confusion, wasted agent iterations, and manual cleanup.

## Acceptance Criteria

### Pre-Edit Warnings

- [ ] When opening spec editor for "in_progress" requirement, user sees warning
- [ ] Warning explains impact and offers: continue editing, block requirement, or cancel
- [ ] "Block" option changes requirement status to "blocked" and stops agent if running

### Change Detection and Plan Invalidation

- [ ] When acceptance criteria section changes, system detects the change
- [ ] Stale plans are automatically deleted when criteria change
- [ ] User sees confirmation that plan was invalidated

### Visual Drift Indicators

- [ ] Spec list shows which requirements are actively being worked on
- [ ] Specs show indicator when modified after their plan was generated
- [ ] Timestamps visible: when spec last changed vs when plan generated

### Manual Controls

- [ ] User can manually "Reset Plan" for any requirement
- [ ] Confirmation dialog before deleting plan
- [ ] Clear feedback after plan deletion

## Validation Criteria

- [ ] Open spec editor for "in_progress" requirement → warning appears
- [ ] Choose "Block and edit" → requirement status becomes "blocked"
- [ ] Edit acceptance criteria and save → plan file deleted
- [ ] Spec list displays indicators showing which requirements have active agents
- [ ] Manual "Reset Plan" button deletes plan with confirmation

## Technical Context

- Plans are stored in `runs/<run-id>/plan-<req-id>.md`
- Requirement status in `..felix/requirements.json`: "draft", "planned", "in_progress", "complete", "blocked"
- Detection should focus on "## Acceptance Criteria" or "## Validation Criteria" sections
- Timestamps can come from file modification times or stored metadata

## Non-Goals

- Preventing all spec edits (human has final authority)
- Git-level version control or branching
- Automatic re-planning (agent handles on next run)
- Complex merge/conflict resolution



