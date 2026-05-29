# Enhancements

Design docs, plans, and architectural notes for Felix (open-source CLI).
Cloud / SaaS docs live in the separate `felix-cloud` repo and are no longer tracked here.

## Conventions

Every doc starts with a header block:

```markdown
> **Status:** Active | Planned | Reference | Complete
> **Supersedes:** OLD_DOC.md (optional)
> **Superseded-By:** NEW_DOC.md (optional)
> **Last-Touched:** YYYY-MM-DD
```

**Lifecycle**

1. `Planned` → `Active` when work begins
2. `Active` → `Complete` when shipped; move file to **complete/**
3. When a doc is replaced (not just finished), set `Superseded-By` on the old one and `Supersedes` on the new one before moving the old one to **complete/**
4. `Reference` docs stay in the root until obsoleted, then move to **complete/** with `Status: Complete`
5. Update this README in the same commit as any move/status change

## Current

### Active

| Doc | Purpose |
|---|---|
| [V2_MIGRATION.md](V2_MIGRATION.md) | Felix v2 — Context Layer Modernization (umbrella plan) |
| [v2/CONTRACTS.md](v2/CONTRACTS.md) | Phase Contracts registry (freezes per-phase interfaces) |
| [v2/BENCH.md](v2/BENCH.md) | Bench harness design (gates phase merges) |

### v2 Phase plans

| Doc | Phase | Version |
|---|---|---|
| [v2/PHASE_A_CONTEXT.md](v2/PHASE_A_CONTEXT.md) | Context Foundation | v2.0 |
| [v2/PHASE_A5_DISTRIBUTION.md](v2/PHASE_A5_DISTRIBUTION.md) | Distribution Substrate | v2.0.x |
| [v2/PHASE_B_SKILLS.md](v2/PHASE_B_SKILLS.md) | Skills & Spec Frontmatter | v2.1 |
| [v2/PHASE_C_EXPLORE.md](v2/PHASE_C_EXPLORE.md) | Exploration Subagent | v2.2 |
| [v2/PHASE_D_SEARCH.md](v2/PHASE_D_SEARCH.md) | Search | v2.3 |
| [v2/PHASE_D_PRIME_NAVIGATION.md](v2/PHASE_D_PRIME_NAVIGATION.md) | Navigation (LSP) | v2.4 |
| [v2/PHASE_E_LEARNING.md](v2/PHASE_E_LEARNING.md) | Self-Improving Loop + Memory | v2.4 |
| [v2/PHASE_F_TARGETED.md](v2/PHASE_F_TARGETED.md) | Targeted Execution + Security | v2.5 |
| [v2/PHASE_H_CONCURRENCY.md](v2/PHASE_H_CONCURRENCY.md) | Concurrency & Worktrees | v2.6 |
| [v2/PHASE_G_MARKETPLACE.md](v2/PHASE_G_MARKETPLACE.md) | Marketplace | v2.7 |

### Reference (root)

_(None currently — all prior reference docs moved to **complete/** during the v2 cleanup.)_

## complete/

Finished or superseded work. See [complete/](complete/) for the full list.
Notable: `AGENTSCRIPT_MIGRATION`, `ARCHITECTURE`, `CLI*`, `RUNS_*`, `REPO_SPLIT` (kept as institutional memory of the open-source/cloud split).
