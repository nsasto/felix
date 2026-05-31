# Phase G — Marketplace (v2.7)

> **Status:** Planned
> **Version:** v2.7 (last)
> **Depends-On:** A.5, B, C, D, D′, E, F, H
> **Unblocks:** —
> **Last-Touched:** 2026-05-29

Phase A.5 already shipped `felix plugin install` and signature verification. G is the **minimum viable curated distribution layer** on top — just enough that an installed Felix can discover and update reference plugins from a single index. Coming last is intentional: by v2.7 every extension point has a reference plugin shipped via A.5, so the index launches with a known-good catalog rather than an empty storefront.

This phase has been deliberately shrunk from the original plan. Packs, certification, and GitHub Action templates are **deferred until ≥3 external plugins exist** — the article motivates _distribution_, not _certification programs_, and there is no user demand for plugin packs while we ship the entire catalog ourselves.

## Goals

1. Make installed plugins/skills discoverable and updatable from a single curated index.
2. Keep the marketplace surface area minimal until external authorship justifies more.

## Deliverables

### G2 — Curated index

- Single `plugins.json` hosted from this repo's GitHub Pages (no separate domain until justified)
- Schema:
  ```json
  {
    "schema": "https://felix.dev/plugins-index/v1.json",
    "updated": "2026-09-01T00:00:00Z",
    "plugins": [
      {
        "id": "lsp-bridge",
        "versions": [{"v":"1.0.0","url":"...","sha256":"...","felix_min":"2.4.0"}],
        "categories": ["navigation","reference"],
        "maintainer": "felix-team"
      }
    ],
    "skills": [
      {"id":"security-review","versions":[...]}
    ]
  }
  ```
- Index URL configurable in `.felix/config.json#distribution.index_url`
- **Single index only.** Multi-index support (corporate internal + public) deferred until one corporate user asks.

### G3 — Remote update/list

- `felix plugin list --remote` queries index
- `felix plugin update [<id>|--all] [--dry-run]` — diff installed vs. latest compatible version
- Update channel per plugin (`stable`, `beta`); defaults to `stable`

### G5 — `felix skill install`

- Parallel to plugin install: `<name|path|url|git>` from the same index
- Verification model identical to A.5

> **G4 (plugin packs), G6 (skill packs), G7 (certification pipeline + GitHub Action template) cut from v2.** Reopen when ≥3 external authors exist and there is concrete demand to bundle their work. Until then: one author (us) does not need a certification program, and a single-vendor catalog does not need packs.

## Non-goals

- Plugin packs and skill packs (deferred until ≥3 external plugins exist)
- Certification pipeline + GitHub Action template (deferred for the same reason)
- Bidirectional sync with `runfelix.io` (v3 roadmap)
- Paid plugins / commercial marketplace (out of scope)
- Auto-update without user consent (always opt-in)

## Phase Contracts frozen here

- `plugins.json` index schema (v1)
- `felix plugin list|update [--remote] [--channel stable|beta]` CLI surface (extends A.5's `plugin` verb)
- `felix skill install` CLI surface

## Verification

- `felix plugin install lsp-bridge` from index pulls + verifies SHA256
- Corrupted index entry (mismatched hash) → install rejected
- `felix plugin update --dry-run` reports compatible updates only (skips ones requiring `felix_min` > installed)
- `felix skill install <id>` works against the same index

## Dogfood specs

- `specs/S-2G02-plugins-index.md`
- `specs/S-2G03-plugin-update-remote.md`
- `specs/S-2G05-skill-install.md`

## Anchor files

- [src/Felix.Cli/Program.Commands.cs](../../src/Felix.Cli/Program.Commands.cs) — `plugin list|update [--remote]`, `skill install`
- [.felix/config.json](../../.felix/config.json) — `distribution.index_url`, `distribution.channels`
- [docs/PLUGINS.md](../../docs/PLUGINS.md) — index documented
- New: `plugins.json` (hosted)
