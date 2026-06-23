# Graphify

Graphify is an optional Felix investigation aid. Felix does not inject graph output into every prompt. Instead, Felix can load a small `graphify-investigator` skill that tells agents to query a Graphify knowledge graph when it would reduce broad search, repeated file reads, or architecture guesswork.

Graphify remains the source of truth for graph creation and querying. Felix only provides setup, wrapper commands, and safe workflow automation.

## Install Graphify

Graphify is external to Felix. Install it with one of Graphify's recommended package managers:

```powershell
uv tool install graphifyy
# or
pipx install graphifyy
```

Check status from a Felix repo:

```powershell
felix graphify status
felix graphify status --json
```

## Local Mode

Local mode is for personal graph use. Felix writes Graphify output to `.felix/graphify` and keeps it out of normal team commits.

```powershell
felix graphify setup --local
felix graphify build
felix graphify query "what owns requirement execution?"
```

Use local mode when you want token-efficient investigation without adding generated graph files to the repo.

## Team Mode

Team mode follows Graphify's team guidance: commit `graphify-out/` so everyone starts with the same map after pulling the repo.

```powershell
felix graphify setup --team
felix graphify build

git add graphify-out .gitignore .felix/skills/graphify-investigator
git commit -m "chore(graphify): add team graph"
```

Recommended ignore entries:

```gitignore
graphify-out/cost.json
graphify-out/cache/
```

`graphify-out/cache/` is configurable. Ignoring it keeps the repo smaller. Committing it can make first checkout faster.

Graphify's portable manifest files should be committed in team mode. They use relative paths and avoid full rebuilds on first checkout.

## Post-Commit Refresh

`felix graphify setup --team` runs `graphify hook install` when Graphify is available. Graphify's post-commit hook refreshes code graph data after commits and sets up a merge driver so `graph.json` can be merged safely when multiple developers update it.

Because post-commit hooks run after Git creates the commit, graph refreshes appear as unstaged changes afterward. The manual workflow is:

```powershell
git commit -m "feat: add requirement runner improvement"
git status
git add graphify-out
git commit -m "chore(graphify): refresh graph"
```

When docs, PDFs, papers, or other semantic inputs change, run an explicit update:

```powershell
felix graphify update
# or native Graphify:
graphify . --update
```

## Felix Auto Chore Commit

For unattended Felix runs, enable a separate graph refresh commit:

```powershell
felix graphify setup --team --auto-commit-refresh
```

After Felix successfully creates a requirement commit, Felix checks the working tree. If every remaining change is under `graphify-out/`, Felix stages only that directory and creates:

```text
chore(graphify): refresh graph
```

Felix will not auto-commit when non-graph files changed, will not amend the requirement commit, and will not push graph commits unless the surrounding Felix flow already pushes.

## Querying

Use Felix wrappers from agents or terminals:

```powershell
felix graphify query "what connects validation to backpressure?"
felix graphify path "Invoke-TaskCompletion" "Invoke-GitCommit"
felix graphify explain "Get-ExploreConfig"
```

The wrappers set Graphify's output directory from Felix config and disable Graphify query logging by default for Felix-invoked queries.

## Felix Skill vs Native Hooks

Felix's default integration uses the `graphify-investigator` Felix skill. This works across Droid, Claude, Codex, Gemini, and Copilot because Felix injects skills into the prompt before handing work to the active adapter.

Native Graphify assistant installs are optional:

```powershell
felix graphify setup --native --harness codex
felix graphify setup --native --harness all
```

Use native installs when you also want Graphify guidance outside Felix. They may modify platform-specific files such as assistant instruction files or hooks, so Felix keeps them opt-in.

## Troubleshooting

If `felix graphify status` says Graphify is missing, install `graphifyy` and reopen the terminal so `graphify` is on `PATH`.

If a team graph looks stale after code changes, check that the post-commit hook is installed and run `felix graphify update` when semantic files changed.

If Graphify leaves tracked changes after a commit, commit them separately as `chore(graphify): refresh graph`.

If graph conflicts appear, rerun `graphify hook install` so Graphify can configure its merge driver.
