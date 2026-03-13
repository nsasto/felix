# Felix Plugins

This directory contains plugins that extend Felix's behavior through lifecycle hooks.

## Plugin Hook Flow

This diagram shows when each plugin hook is triggered during a Felix agent iteration:

```mermaid

flowchart TD

    Start([Start Iteration]) --> Hook1[🔌 OnPreIteration]

    Hook1 --> CheckContinue{Continue?}

    CheckContinue -->|No| End([End])

    CheckContinue -->|Yes| ModeSelect[Determine Mode<br/>planning/building]



    ModeSelect --> Hook2[🔌 OnPostModeSelection]

    Hook2 --> Context[Gather Context<br/>specs, git, plan]



    Context --> Hook3[🔌 OnContextGathering]

    Hook3 --> BuildPrompt[Build Full Prompt]



    BuildPrompt --> Hook4[🔌 OnPreLLM]

    Hook4 --> CheckSkip{Skip LLM?}

    CheckSkip -->|Yes| Hook11

    CheckSkip -->|No| LLM[Execute LLM<br/>droid exec]



    LLM --> Hook5[🔌 OnPostLLM]

    Hook5 --> CheckMode{Mode?}



    CheckMode -->|Planning| Guardrails[Check Guardrails<br/>no commits allowed]

    CheckMode -->|Building| TaskCheck{Task<br/>Complete?}



    Guardrails --> GuardrailResult{Passed?}

    GuardrailResult -->|Failed| Hook6[🔌 OnGuardrailCheck]

    GuardrailResult -->|Passed| Hook11

    Hook6 --> Revert[Revert Changes]

    Revert --> Hook11



    TaskCheck -->|No| Hook11

    TaskCheck -->|Yes| Hook7[🔌 OnPreBackpressure]

    Hook7 --> CheckSkipBP{Skip<br/>Backpressure?}

    CheckSkipBP -->|Yes| Commit

    CheckSkipBP -->|No| Backpressure[Run Validation<br/>tests/build/lint]



    Backpressure --> BPResult{Passed?}

    BPResult -->|Failed| Hook8[🔌 OnBackpressureFailed]

    Hook8 --> Block[Mark Task Blocked]

    Block --> Hook11



    BPResult -->|Passed| Hook9[🔌 OnPreCommit]

    Hook9 --> CheckSkipCommit{Skip<br/>Commit?}

    CheckSkipCommit -->|Yes| Hook11

    CheckSkipCommit -->|No| Commit[Git Commit]



    Commit --> AllComplete{All Tasks<br/>Complete?}

    AllComplete -->|No| Hook11

    AllComplete -->|Yes| Validate[Run Requirement<br/>Validation]



    Validate --> Hook10[🔌 OnPostValidation]

    Hook10 --> ValidationResult{Passed?}

    ValidationResult -->|Yes| Complete([Requirement Complete])

    ValidationResult -->|No| Hook11



    Hook11[🔌 OnPostIteration]

    Hook11 --> ShouldContinue{Continue<br/>Iterations?}

    ShouldContinue -->|Yes| Start

    ShouldContinue -->|No| End



    style Hook1 fill:#e1f5ff

    style Hook2 fill:#e1f5ff

    style Hook3 fill:#e1f5ff

    style Hook4 fill:#e1f5ff

    style Hook5 fill:#e1f5ff

    style Hook6 fill:#ffe1e1

    style Hook7 fill:#e1f5ff

    style Hook8 fill:#ffe1e1

    style Hook9 fill:#e1f5ff

    style Hook10 fill:#e1f5ff

    style Hook11 fill:#e1f5ff

```

**Legend:**

- 🔌 **Blue hooks** - Normal execution flow where plugins can enhance or modify behavior

- 🔌 **Red hooks** - Error/failure handling where plugins can react to problems

- **Decision diamonds** - Points where plugin return values can alter the flow

## Directory Structure

Each plugin should be in its own subdirectory:

```

..felix/plugins/

  plugin-name/

    plugin.json           # Manifest file (required)

    on-prediteration.ps1  # Hook script (v1 API)

    on-postllm.ps1        # Hook script (v1 API)

    persistent-state.json # Persistent state (auto-generated)

    README.md             # Plugin documentation

    tests/                # Plugin tests

```

## Plugin Discovery

Felix automatically discovers and loads plugins from this directory during agent startup.

Plugins are loaded in dependency order, then sorted by priority (lower = earlier).

## API Versions

- **v1**: Hook scripts named `on-{hookname}.ps1` (e.g., `on-prediteration.ps1`)

- **v2**: Hook scripts in `hooks/{HookName}.ps1` subdirectory (e.g., `hooks/OnPreIteration.ps1`)

Set `api_version` in config.json to control which API version is used.

## State Management

Plugins can store state in two ways:

1. **Persistent State**: `persistent-state.json` in plugin directory (survives across runs)

2. **Transient State**: `plugin-state-{name}.json` in each run directory (per-run only)

Use the helper functions in felix-agent.ps1:

- `Get-PluginPersistentState` / `Set-PluginPersistentState`

- `Get-PluginTransientState` / `Set-PluginTransientState`

## Circuit Breaker

If a plugin fails repeatedly (default: 3 times), it is automatically disabled for the session.

Adjust `circuit_breaker_max_failures` in config.json to change this threshold.

## Debugging

Check these files for plugin execution details:

- `runs/{runId}/plugin-chain-debug.json` - Hook execution chain

- `runs/{runId}/plugin-execution.json` - Plugin execution metrics

- `runs/{runId}/plugin-state-{name}.json` - Per-plugin transient state

## Example Plugins

See example plugins in this directory for reference implementations.

For a complete guide to writing plugins, see **[docs/PLUGINS.md](../../docs/PLUGINS.md)**.
