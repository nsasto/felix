# Bench Harness

> **Status:** Active (gating workstream)
> **Owner:** v2 migration
> **Last-Touched:** 2026-05-29

The bench harness is **non-negotiable** for v2. Without it, we can't tell whether Phase C is paying for itself, whether Phase B's skill triggers are correctly scoped, or whether Phase E's memory tree is helping more than it hurts. It gates every phase merge.

## What it is

A sibling repo (`felix-bench` or `bench/` checked out alongside `felix`) containing:

- **Frozen reference projects** — small, stable, polyglot
- **Frozen requirement specs** — the same `S-NNNN-*.md` Felix consumes elsewhere
- **Frozen expected outcomes** — what "done" looks like for each fixture
- **A runner** — drives Felix at two configs (baseline + candidate) and measures the deltas

## Location

**Sibling `bench/` repo, not inside [tests/](../../tests/)**. Reasons:

- Bench fixtures grow over time and would bloat the main repo
- Bench has its own commit cadence (changes when fixtures need updating, not when Felix changes)
- Separable means it can be public/private independently

The runner inside the Felix repo (`src/Felix.Cli/...`) shells out to the bench checkout configured via `bench.path` in `.felix/config.json`.

## Fixtures (initial set)

Start with three; add others when the phase that needs them ships.

| Fixture                      | Stack                                                    | Why it's in the set                                          | Ship                      |
| ---------------------------- | -------------------------------------------------------- | ------------------------------------------------------------ | ------------------------- |
| `bench/fixtures/py-flask`    | Python + Flask + pytest                                  | Small Python web app; tests fast                             | v2.0                      |
| `bench/fixtures/cs-classlib` | C# class library + xUnit                                 | Hits Roslyn LSP path; tests `Program.*.cs` partial-discovery | v2.0                      |
| `bench/fixtures/polyglot`    | C# API + TS frontend + Python tooling                    | Cross-language; stresses per-path backpressure (F1)          | v2.0                      |
| `bench/fixtures/ts-frontend` | TypeScript + Vite + Vitest                               | tsserver LSP path; modern JS toolchain                       | add with D′               |
| `bench/fixtures/legacy-mono` | C# console + small Python helpers, no AGENTS.md at start | Tests A1 walk-up against a "naked" repo                      | add with A                |
| `bench/fixtures/de-locale`   | Same as `py-flask` but runner forces `LANG=de_DE.UTF-8`  | i18n guard (cross-cutting)                                   | add when i18n guard ships |

Each fixture ships with a small set of requirement specs (`bench/fixtures/<id>/specs/`) Felix is asked to implement.

## Metrics

Captured per run, written to `bench/results/<utc-iso>-<candidate>/results.jsonl` and emitted as Event Bus entries (`kind=bench.iteration`, `kind=bench.summary`):

| Metric                                                                        | Why                                             |
| ----------------------------------------------------------------------------- | ----------------------------------------------- |
| Iterations to green                                                           | Headline quality signal                         |
| Tokens consumed (input + output) per iteration                                | Cost & context efficiency                       |
| Wall time per iteration                                                       | UX                                              |
| Backpressure retries                                                          | Did the agent know how to fix its own failures? |
| Context-map quality (C) — % of "files likely to change" actually changed      | Subagent calibration                            |
| Skill activations (B) — which fired, which didn't                             | Trigger correctness                             |
| Memory entries surfaced (E) — which loaded, which influenced output           | Memory utility                                  |
| Tool calls (D′ F4) — count by tool, denial rate                               | Tool-shim health                                |
| Final diff size (lines added/removed)                                         | Solution shape                                  |
| `bench.summary.outcome` ∈ {`green`, `red`, `flaky`, `budget-stop`, `timeout`} | Final state                                     |

## Runner

```
felix bench run --baseline <ref> --candidate <ref> [--fixtures <list>] [--repeat N] [--seed S]
```

- `--baseline` / `--candidate`: git refs in the Felix repo
- `--fixtures`: comma-separated fixture ids; defaults to all
- `--repeat`: each fixture run N times to detect flakiness (default 3)
- `--seed`: passed to agent params where supported, for repeatability

Each run:

1. Checks out the baseline ref into a temp dir
2. Runs Felix against each fixture (with deterministic config)
3. Captures metrics
4. Repeats for candidate
5. Diffs metrics + writes report

## Gate

**Advisory until v2.1** (after A ships a baseline). From v2.1 onward, phase merges to `main` blocked by CI if:

- **Iterations-to-green regresses > 10%** vs. baseline on any fixture
- **Total tokens regresses > 20%** vs. baseline on any fixture
- **Outcome regresses** (e.g., `green → red` on any fixture)

CI publishes the report as a PR comment so authors can decide to override (override requires explicit approval).

## UX

`felix bench run` with unset `bench.path` prints actionable clone instructions (e.g., `clone https://github.com/nsasto/felix-bench to ./bench, then set bench.path in .felix/config.json`), not a stack trace.

## What it isn't

- **Not a correctness oracle** — fixtures have expected outcomes, but the bench doesn't grade code quality beyond "tests pass"
- **Not a benchmark suite** — we're not publishing leaderboards; this is internal regression detection
- **Not a model benchmark** — we hold the agent profile fixed across baseline/candidate runs; this measures the **harness**, not the model

## Open items

- Fixture seeding strategy when an agent legitimately needs randomness (currently: per-fixture override of agent temperature where the adapter supports it)
- How to handle non-deterministic test failures (flaky tests in fixtures themselves) — currently filtered via `--repeat N` median
- Cost tracking units across adapters (Droid vs. Codex vs. Copilot bill differently) — feeds into Cost guardrails cross-cutter

## Anchor files

- New sibling repo: `bench/` (separate git remote)
- [src/Felix.Cli/Program.Commands.cs](../../src/Felix.Cli/Program.Commands.cs) — `bench run`, `bench report`
- [.felix/config.json](../../.felix/config.json) — `bench.path`, `bench.gate` (thresholds)
- CI config — phase-merge gate
