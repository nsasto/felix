# Documentation

This hub covers everything you need to run, configure, and extend Felix — the autonomous agent executor for software development. Felix v2 added eight phases of new capabilities on top of the original plan-driven loop.

---

## 🚀 Getting Started

| Document | Audience | Covers |
|---|---|---|
| [CLI.md](CLI.md) | Developers, AI agents | Command index, global options, operating modes, workflows, war stories |
| [SETUP.md](SETUP.md) | Developers, operators | Installation, setup, agents, tools, migration, doctor, gc |
| [CONFIGURATION.md](CONFIGURATION.md) | Operators, developers | Every `config.json` key with type, default, and description |
| [../tuts/EXECUTION_FLOW.md](../tuts/EXECUTION_FLOW.md) | Developers | Execution flow, mode transitions, validation, artifacts |

## 📖 Reference

| Document | Audience | Covers |
|---|---|---|
| [FEATURES.md](FEATURES.md) | Everyone | Full product capabilities, v1 and v2 feature set |
| [PLUGINS.md](PLUGINS.md) | Plugin authors | Writing, testing, and publishing plugins |
| [SYNC_OPERATIONS.md](SYNC_OPERATIONS.md) | Operators | Sync setup, troubleshooting, env vars, emergency disable |

## 🔧 Guides

| Document | Audience | Covers |
|---|---|---|
| [RUNNING.md](RUNNING.md) | Developers | Executing requirements, loop, procs, exit codes |
| [SPECS.md](SPECS.md) | Developers | Spec and requirement lifecycle management |
| [CONTEXT.md](CONTEXT.md) | Developers | Run artifacts, context inspection, event stream, replay |
| [SEARCH.md](SEARCH.md) | Developers | Full-text search, dependency graph, structured queries |
| [MEMORY.md](MEMORY.md) | Developers | Persistent agent memory, CLI, budget, learning proposals |
| [SKILLS.md](SKILLS.md) | Developers | Skills system — manifest, triggers, install, authoring |

## ⚙️ Advanced

| Document | Audience | Covers |
|---|---|---|
| [CONCURRENCY.md](CONCURRENCY.md) | Power users, operators | Parallel workers, worktrees, lease protocol, recovery |
| [MARKETPLACE.md](MARKETPLACE.md) | Plugin/skill authors | Curated index, remote install, update, private registry |

---

## ✨ v2 New in This Release

Felix v2 shipped eight phases of new capabilities:

| Phase | Name | Summary |
|---|---|---|
| **A** | Context Foundation | Hierarchical `AGENTS.md`, `.felixignore`, token budgeter, `felix migrate` registry |
| **B** | Skills & Spec Frontmatter | Progressive-disclosure skills, spec YAML frontmatter, `felix skill` CLI |
| **C** | Exploration Subagent | Auto-enabled repo explorer that runs before plan/build on large repos |
| **D** | Search & Navigation | `felix search`, per-run memoization cache, LSP-bridge for symbol navigation |
| **E** | Learning & Memory | `.felix/memory/` tree, `learning-capture` plugin, `felix memory` CLI |
| **F** | Targeted Execution & Security | Per-path backpressure, `felix query` including usage, tool allowlist, `felix gc` |
| **G** | Marketplace | Curated `plugins.json` index, `felix plugin update`, `felix skill install` |
| **H** | Concurrency & Worktrees | `--parallel N`, git worktrees, atomic leases, `felix recover` |

---

*See also: [learnings/](../learnings/README.md) for technical war stories · [Enhancements/](../Enhancements/) for roadmap and planning docs*
