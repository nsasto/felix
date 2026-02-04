# Felix Local Execution Architecture

One Page Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                          Front Ends                          │
│                                                              │
│  ┌───────────────┐   ┌────────────────┐   ┌────────────────┐ │
│  │ Plain Console │   │ Terminal UI    │   │ Tray App (C#)  │ │
│  │ (felix run)   │   │ (felix tui)    │   │ Background UI  │ │
│  └───────┬───────┘   └──────┬─────────┘   └──────┬─────────┘ │
│          │                  │                    │           │
│          │ NDJSON events    │ NDJSON events      │ NDJSON    │
│          │ + prompts        │ + prompts          │ events    │
└──────────┼──────────────────┼────────────────────┼───────────┘
           │                  │                    │
           ▼                  ▼                    ▼
┌──────────────────────────────────────────────────────────────┐
│                    C# Host Executable                        │
│                        (felix.exe)                           │
│                                                              │
│  Responsibilities:                                           │
│  - Single entrypoint for all local usage                     │
│  - Creates run directory                                     │
│  - Launches PowerShell engine                                │
│  - Reads stdout / stderr                                     │
│  - Forwards structured events (NDJSON)                       │
│  - Wraps unstructured output as log events                   │
│  - Handles cancellation                                      │
│  - Bridges prompt responses back to engine                   │
│                                                              │
│  Commands:                                                   │
│  - felix run <spec>                                          │
│  - felix run <spec> --emit ndjson                            │
│  - felix tui <spec>                                          │
└───────────────────────────────┬──────────────────────────────┘
                                │
                                │ pwsh subprocess
                                │ stdout / stderr
                                ▼
┌──────────────────────────────────────────────────────────────┐
│                PowerShell Execution Engine                   │
│                  (felix-loop.ps1)                            │
│                                                              │
│  - Master entrypoint                                         │
│  - Calls subscripts                                          │
│  - Owns execution logic                                      │
│  - Emits structured events                                   │
│  - Writes artifacts                                          │
│  - Never renders UI                                          │
│  - Never prompts via Read-Host                               │
│                                                              │
│  Uses shared helpers:                                        │
│  - Emit-Event                                                │
│  - Log-Info / Warn / Error                                   │
│  - Progress                                                  │
│  - Prompt-*                                                  │
└───────────────────────────────┬──────────────────────────────┘
                                │
                                │ filesystem
                                ▼
┌──────────────────────────────────────────────────────────────┐
│                        Run Directory                         │
│                                                              │
│  runs/<run_id>/                                              │
│    ├─ events.ndjson                                          │
│    ├─ manifest.json                                          │
│    ├─ artifacts/                                             │
│    ├─ prompts/                                               │
│    │    ├─ <prompt_id>.json                                  │
│    │    └─ <prompt_id>.response.json                         │
│    └─ cancel.txt                                             │
│                                                              │
│  - Single source of truth for run outputs                    │
│  - Enables replay, debugging, and UI reattachment            │
└──────────────────────────────────────────────────────────────┘
```

---

## Key Flows (at a glance)

### Execution

1. Front end starts `felix.exe`
2. Host creates run directory
3. Host launches `felix-loop.ps1`
4. Engine emits NDJSON events
5. Host forwards events to UI

### Prompts

1. Engine emits `prompt` event
2. UI displays prompt
3. UI writes response to run directory
4. Engine resumes

### Cancellation

1. User cancels in UI
2. Host writes `cancel.txt`
3. Engine detects and exits cleanly

---

## Why this diagram matters

- PowerShell stays focused on execution
- C# host is the integration and stability layer
- UIs are thin, replaceable renderers
- Event stream is the contract
- Run directory is the audit trail

## Flow

```mermaid
flowchart TB
    subgraph FE[Front Ends]
        CLI[Plain Console<br/>felix run]
        TUI[Terminal UI<br/>felix tui]
        TRAY[Tray App<br/>C# WPF]
    end

    subgraph HOST[C# Host Executable<br/>felix.exe]
        HOSTCORE[Process orchestration<br/>Event forwarding<br/>Prompt bridging]
    end

    subgraph ENGINE[PowerShell Engine]
        LOOP[felix-loop.ps1<br/>Master entrypoint]
        SUBS[Subscripts<br/>Execution logic]
    end

    subgraph RUNS[Run Directory<br/>runs/run_id]
        EVENTS[events.ndjson]
        PROMPTS[prompts/]
        ARTIFACTS[artifacts/]
        CANCEL[cancel.txt]
    end

    CLI -->|start run| HOSTCORE
    TUI -->|start run| HOSTCORE
    TRAY -->|start run| HOSTCORE

    HOSTCORE -->|pwsh subprocess| LOOP
    LOOP --> SUBS

    SUBS -->|emit NDJSON| LOOP
    LOOP -->|stdout NDJSON| HOSTCORE

    HOSTCORE -->|forward events| CLI
    HOSTCORE -->|forward events| TUI
    HOSTCORE -->|forward events| TRAY

    LOOP -->|write| EVENTS
    LOOP -->|write| ARTIFACTS
    LOOP -->|emit prompt| PROMPTS

    TRAY -->|write response| PROMPTS
    TUI -->|write response| PROMPTS
    CLI -->|write response| PROMPTS

    HOSTCORE -->|cancel| CANCEL
```
