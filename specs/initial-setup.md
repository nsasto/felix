# S-0001: Initial Project Setup

## Narrative

As a developer, I need the Felix repository properly structured and documented so I can begin implementing the executor and understand the system's design principles.

## Acceptance Criteria

- [x] Directory structure matches final design
- [x] README.md and HOW_TO_USE.md are consistent
- [x] Core artifacts (specs/, felix/, AGENTS.md, IMPLEMENTATION_PLAN.md) exist
- [x] Example spec file demonstrates ID-in-first-line convention
- [ ] Basic executor scaffold (Phase 2)
- [ ] Initial tests (Phase 2)

## Technical Notes

This requirement establishes the foundation. The structure emphasizes:

- Flat, scannable `specs/` directory
- Single state directory `felix/` containing all executor concerns
- Top-level `runs/` for append-only execution evidence
- Descriptive filenames with IDs in content, not filenames

## Dependencies

None - this is the foundation requirement.
