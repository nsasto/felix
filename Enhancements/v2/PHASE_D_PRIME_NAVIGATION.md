# Phase D′ — Navigation (v2.4)

> **Status:** Planned
> **Version:** v2.4 (parallel with E)
> **Depends-On:** D, A.5
> **Unblocks:** —
> **Last-Touched:** 2026-05-29

The article calls LSP integration "one of the highest-value investments" for multi-language codebases. Felix's own repo is C# + PowerShell + Python + Markdown; grep on `Program` returns hundreds of false hits across [src/Felix.Cli/](../../src/Felix.Cli/)'s 8 `Program.*.cs` partials. Symbol-precise navigation eliminates the noise.

## Goals

1. Give agents symbol-precise navigation when an LSP is available.
2. Expose `felix search`, `felix navigate`, and `felix query` (F3) as agent tools via a shim per adapter.
3. Degrade gracefully (back to D) when an LSP isn't running.

## Deliverables

### D4 — `lsp-bridge` daemon

- Distributed as a reference plugin via A.5
- Supervises per-language LSP servers as stdio child processes:
  - C#: OmniSharp / Roslyn-based LSP
  - TypeScript: `tsserver` / `typescript-language-server`
  - Python: `pyright` / `pylsp`
- Auto-detection from project signals (`*.csproj`, `tsconfig.json`, `pyproject.toml`)
- Daemon lifecycle: started by `felix loop`/`felix run`, killed on exit; recovers on crash (1 retry, then ripgrep fallback)
- Felix installer prompts to install missing LSPs but doesn't require them

### D5 — Tool exposure (MCP-first; per-adapter shim where required)

- **Primary path: `felix mcp serve`.** Felix exposes `search`, `navigate`, and `query` (F3) as tools on a single MCP server. MCP-capable adapters (Claude Code, Codex, Copilot CLI, Gemini where supported) consume natively — no bespoke shim, no per-adapter divergence. This collapses what was originally five per-adapter shims into one server + one contract.
- **Fallback path: per-adapter shim** for adapters without MCP. Same input/output contract; thin translator only.
- Tools registered (whether via MCP or shim):
  - `felix search` (D1/D5a)
  - `felix navigate` — `definition <symbol> <file:line>`, `references <symbol>`, `callers <symbol>`, `implementations <symbol>`
  - `felix query` (F3) — limited to `requirements`, `runs`, `state` (see F3)
- Allowlist enforcement (F5) applies identically to both paths; denial returns the same structured error

### D5a — `felix search --symbol`

- When LSP up: returns precise references; rank reflects symbol kind (definition > reference > comment)
- When LSP down: transparently falls back to D1's text search with a warning in `--json` output (`"fallback": true`)
- Same output schema as D — additive, doesn't break D consumers

## Non-goals

- IDE-style features beyond search/navigate (hover, completions, refactors)
- Cross-language navigation (each LSP scoped to its language)
- Bundled LSP binaries (size; users install via official channels)

## Phase Contracts frozen here

- `felix navigate` CLI flags + `--json` schema
- Tool exposure contract: MCP tool schema (primary) **and** per-adapter shim input/output JSON (fallback) — both share one logical contract
- `lsp-bridge` plugin manifest (auto-detection rules; daemon control commands)
- `felix search --symbol` extension of D's schema (`fallback` boolean)
- `felix mcp serve` CLI surface (port/socket flags; tool listing)

## Verification

- LSP resolves `RegisterCommands` across all 8 `Program.*.cs` partials in [src/Felix.Cli/](../../src/Felix.Cli/) — single ranked list vs. raw grep returning ~80 hits
- Daemon crash mid-iteration: next tool call gets ripgrep fallback within 2s; Event Bus records `lsp.fallback` event
- `felix mcp serve` starts; an MCP-capable adapter lists Felix tools without any per-adapter configuration
- For at least one non-MCP adapter, the fallback shim round-trips a known navigate query and surfaces results in the iteration prompt
- Allowlist denies `felix navigate` for an adapter not listed in `tools.allow`; denial audited on Event Bus
- Bench harness shows C# fixture iterations drop ≥ 25% in tokens with LSP up vs. without

## Dogfood specs

- `specs/S-2D04-lsp-bridge-daemon.md`
- `specs/S-2D05-tool-exposure-mcp-and-shim.md` — one spec for the contract; the per-adapter implementations are listed in a status table inside it, not separate specs
- `specs/S-2D05e-felix-search-symbol.md`

## Anchor files

- New: `.felix/plugins/lsp-bridge/`
- [src/Felix.Cli/Program.Commands.cs](../../src/Felix.Cli/Program.Commands.cs) — `navigate`, `mcp serve` commands
- [src/Felix.Cli/AgentCommands.cs](../../src/Felix.Cli/AgentCommands.cs) — fallback shim registration (per adapter, thin)
- [scripts/install.ps1](../../scripts/install.ps1) — optional LSP prompts
- [docs/PLUGINS.md](../../docs/PLUGINS.md) — `lsp-bridge` documented as reference plugin
