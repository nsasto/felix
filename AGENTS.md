# Agents - How to Operate This Repository

This file tells Felix **how to run the system**.

## Install

```powershell
git clone https://github.com/nsasto/felix.git
cd felix
.\scripts\install.ps1
```

Or download the installer from [GitHub Releases](https://github.com/nsasto/felix/releases/latest).

## Run Felix

### CLI Commands

```powershell
# Set up a new project
cd C:\your\project
felix setup

# Run agent on a requirement
felix run S-0001

# Run in continuous loop mode
felix loop

# Launch interactive TUI dashboard
felix tui
```

### Running the Agent Directly (PowerShell)

```powershell
# Start the agent for a repository
.\felix\felix-agent.ps1 C:\dev\your-project

# Alternative: run the looped runner
.\felix\felix-loop.ps1 C:\dev\your-project
```

### Agent Profiles

- Agent profiles live in **.felix/agents.json** in the target repo.
- User profile **%USERPROFILE%\.felix\agents.json** is no longer used.

## Run Tests

```powershell
# Run Felix CLI tests
.\run-test-spec.ps1
```

## Validate Requirement

Run requirement-level acceptance verification for a specific requirement. The validation script reads validation/acceptance criteria from the spec file and executes any commands specified.

This command answers: "Did we achieve this requirement per its criteria?"

This command is separate from loop backpressure checks. Backpressure gates each iteration before commit; `felix validate` checks requirement completion criteria.

```bash
# Validate a specific requirement
felix validate S-0002

# Machine-readable output (for CI / dashboards)
felix validate S-0002 --json

# If `py -3` is not available, use `python` or set the full Python executable path in `.felix/config.json` under `python.executable`.

# Example output:
# Validating Requirement: S-0002
# ✅ Tests pass: `pytest` (exit code 0)
# VALIDATION PASSED for S-0002
```

### Exit Codes

**Validation Script (validate-requirement.py):**

- `0` - All acceptance criteria passed
- `1` - One or more acceptance criteria failed
- `2` - Invalid arguments or requirement not found

**Felix Agent (felix-agent.ps1):**

- `0` - Success: requirement complete and validated
- `1` - Error: general execution failure (droid errors, file I/O issues)
- `2` - Blocked: backpressure failures exceeded max retries (default: 3 attempts)
- `3` - Blocked: validation failures exceeded max retries (default: 2 attempts)

When the agent exits with code 2 or 3, the requirement is automatically marked as "blocked" in `.felix/requirements.json`. To unblock:

1. Fix the underlying issues (tests, validation criteria, or code)
2. Manually edit `.felix/requirements.json` and change status from `"blocked"` to `"planned"`
3. Restart the agent - it will pick up the unblocked requirement

### Validation Criteria Format

Specs should include testable validation criteria with commands and expected outcomes. The script looks for "## Validation Criteria" first, then falls back to "## Acceptance Criteria":

```markdown
## Validation Criteria

- [ ] Tests pass: `pytest` (exit code 0)
- [ ] Lint clean: `npm run lint` (exit code 0)
```

**Important:** Only use backticks for actual executable commands. Do NOT use backticks for:

- File paths (use **bold** instead: **src/main.py**)
- URLs (use plain text: http://localhost:3000)
- Placeholders (use plain text: {ComputerName})
- Configuration values (use plain text or **bold**)

The validation script executes anything in backticks as a shell command. If it's not meant to be executed, don't use backticks.

## Sync Configuration (Optional)

Enable artifact mirroring to [runfelix.io](https://runfelix.io) via the **sync-http plugin**. Quick start:

```powershell
$env:FELIX_SYNC_ENABLED = "true"
$env:FELIX_SYNC_URL = "https://runfelix.io"
$env:FELIX_SYNC_KEY = "fsk_your_api_key_here"  # Required when sync enabled
```

Or use the `--sync` CLI flag for a single run: `felix run S-0001 --sync`

See **docs/SYNC_OPERATIONS.md** for full configuration, troubleshooting, and architecture details.

## Sync Troubleshooting

For sync errors, outbox management, configuration examples, emergency disable, and log viewing, see **docs/SYNC_OPERATIONS.md**.

Quick checks:

```powershell
# Pending uploads
(Get-ChildItem .felix\outbox\*.jsonl -ErrorAction SilentlyContinue).Count

# Recent sync errors
Select-String -Path .felix\sync.log -Pattern "ERROR" -ErrorAction SilentlyContinue | Select-Object -Last 5
```

## Repository Conventions

- Keep this file operational only
- No planning or status updates
- No long explanations
- If it wouldn't help a new engineer run the repo, it doesn't belong here

## CLI Scope

Felix CLI configuration and execution are always local to the machine running it.

## Version Bump Workflow (Agent)

When asked to bump a release version, do this sequence exactly:

1. Choose the target version (example: `1.1.0`) and keep the same value everywhere below.
2. Update required version files:
   - `.felix/version.txt` (used by release packaging scripts)
   - `src/Felix.Cli/Felix.Cli.csproj` `<Version>` value
3. Add release notes file at `release_notes/RELEASE_NOTES_v<major>.<minor>.md` (or next repo convention), with date, highlights, fixes, and breaking changes if any.
4. Validate build/release artifacts:
   - `powershell -File .\scripts\package-release.ps1 -Rid win-x64`
5. Commit changes:
   - `git add .felix/version.txt src/Felix.Cli/Felix.Cli.csproj release_notes/*`
   - `git commit -m "chore(release): bump version to v<version>"`
6. Create annotated git tag:
   - `git tag -a v<version> -m "Release v<version>"`
7. Push commit and tag:
   - `git push`
   - `git push origin v<version>`

Notes:

- `scripts/package-release.ps1` reads `.felix/version.txt` for artifact names.
- Update release server `latest.txt` to the new version when publishing artifacts.
