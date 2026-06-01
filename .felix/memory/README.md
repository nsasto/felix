# Felix Memory Tree

Durable, human-curated memory loaded additively into every iteration prompt.

## Scopes

| Scope | Location | Committed? | Who edits |
|-------|----------|-----------|-----------|
| `global` | `%USERPROFILE%\.felix\memory\global\*.md` | No (user-local) | Human via `felix memory add --scope global` |
| `repo` | `.felix/memory/repo/*.md` | Yes | Human via `felix memory add --scope repo` |
| `requirement` | `.felix/memory/requirement/<S-NNNN>/*.md` | Yes | Human via `felix memory add --scope requirement --req S-NNNN` |

## Frontmatter

Every memory file must start with:

```yaml
---
title: Short title for this memory
scope: global|repo|requirement
created: YYYY-MM-DD
tags: []
---
```

## Loading order (prompt budget)

Memory is evicted **after** layered AGENTS.md but **before** spec/plan. Use `context.budget_tokens` in `.felix/config.json` to control total budget.

## Never auto-modified

Files in `.felix/memory/` are **never** modified or deleted by the Felix loop.
Only `runs/*/agents-md-suggestions.md` proposal files are auto-pruned (30 days default).

## Promoting proposals

1. Run `felix review --learnings` to inspect proposals from recent runs.
2. Accept a proposal — it is appended to `AGENTS.md` with a `<!-- [felix-learning] -->` marker.
3. Optionally promote to a memory file via `felix memory add`.
