# Felix swarm ship (in-loop fragment)

When this skill is loaded, prefer Felix CLI over ad-hoc scripts:

- Configure `agent.by_phase`: planning/reviewing → Codex; building → OpenCode Go (`opencode-go/deepseek-v4-pro`)
- Enable `review.enabled` (architecture review after validation)
- Publish with `felix spec push --force` when sync is configured
- Run work with `felix loop --sync` / `felix run-next --sync` — do not reimplement plan/build/validate
- On `REVIEW_CHANGES_REQUESTED`, continue building with remediation notes; on `REVIEW_COMPLETE`, requirement finishes and learnings land under `.felix/memory/requirement/<id>/`

Full portable playbook for outer agents (Grok/Codex/Claude): see **SKILL.md** in this skill directory and **INSTALL.md** for install paths.
