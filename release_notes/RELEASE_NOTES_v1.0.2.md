# Release Notes - v1.0.2

**Release Date:** March 17, 2026

## Highlights

- Simplified `felix setup` agent UX to remove duplicate provider-style selection prompts
- Added automatic active-agent selection when exactly one profile is configured
- Improved active-agent guidance and fallback messaging for invalid or stale agent IDs
- Expanded test coverage for setup agent-selection planning and key normalization paths

---

## New Features

### Clearer Setup Agent Flow

`felix setup` now separates two concerns more clearly:

1. Configure/update agent profiles in `.felix/agents.json`
2. Choose active profile in `.felix/config.json` (`agent.agent_id`)

This removes the previous experience where users could feel prompted to select provider-like options twice in a row.

### Single-Agent Auto-Select

When setup finds exactly one configured agent profile, it now auto-selects that profile as active and skips manual selection.

### Active Agent Selection From Configured Profiles

The active-agent chooser now reads real configured entries from `.felix/agents.json` (name/provider/model/key) instead of relying on a fixed hardcoded provider list.

---

## Improvements

- Setup prompt copy now explicitly distinguishes profile configuration vs active selection
- Legacy numeric active IDs are migrated to key-based IDs during setup selection with a visible notice
- Runtime warning text now provides explicit remediation (`felix setup` or `felix agent use <name|key>`)

---

## Test Coverage

Added setup utility tests for agent selection behavior:

- `ConvertTo-ConfiguredAgentList` normalization behavior
- `Get-ActiveAgentSelectionPlan` branch coverage for:
  - no configured agents (`none` mode)
  - single configured agent (`auto` mode)
  - multiple agents (`choose` mode)
  - missing vs valid current active agent

Also retained and validated config-loader tests for key and legacy ID resolution paths.

---

## Migration Notes

- Existing projects with numeric `agent.agent_id` continue to work.
- Running `felix setup` on those projects will migrate selection to key-based IDs when applicable.
- No manual changes to existing `agents.json` are required.
