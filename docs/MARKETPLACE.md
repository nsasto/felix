# Plugin & Skill Marketplace

> **Quick links:** [What Is the Marketplace](#what-is-the-marketplace) · [Listing Remote Entries](#listing-remote-entries) · [Installing Plugins](#installing-plugins) · [Installing Skills](#installing-skills) · [Updating](#updating) · [Index Format](#index-format) · [Private Registry](#hosting-a-private-registry) · [SHA256 Verification](#sha256-verification)

---

## What Is the Marketplace

The Felix Marketplace is a **curated index** of plugins and skills that you can install with a single command. Felix reads a `plugins.json` index file hosted on GitHub Pages and uses it to discover compatible versions, download archives, and verify checksums.

The index URL is configurable so organisations can host their own private registries alongside (or instead of) the public one.

**Default index URL:** `https://nsasto.github.io/felix/plugins.json`

---

## Listing Remote Entries

### List remote plugins

```powershell
felix plugin list --remote              # All stable plugins in the index
felix plugin list --remote --channel beta  # Include beta channel
```

Output shows each plugin's ID, description, latest compatible version, and whether it is already installed.

### List remote skills

```powershell
felix skill list --remote               # All stable skills in the index
```

---

## Installing Plugins

```powershell
felix plugin install <name|url|path>
```

### From the index (by name)

```powershell
felix plugin install learning-capture
felix plugin install lsp-bridge --channel beta
```

Felix:

1. Fetches the index from `distribution.index_url`.
2. Finds the latest version in the requested channel that is compatible with your Felix version (`felix_min`).
3. Downloads the ZIP archive.
4. Verifies the SHA256 checksum.
5. Extracts the archive to `.felix/plugins/<id>/`.

### From a URL

```powershell
felix plugin install https://example.com/plugins/my-plugin-1.0.0.zip
```

### From a local path

```powershell
felix plugin install ./local-plugins/my-plugin
```

---

## Installing Skills

```powershell
felix skill install <name|url|path> [--scope repo|user] [--channel stable|beta]
```

### From the index (by name)

```powershell
felix skill install security-review
felix skill install security-review --scope user    # Install to user profile
```

### From a URL or local path

```powershell
felix skill install https://example.com/skills/code-reviewer-1.0.0.zip
felix skill install ./my-skills/code-reviewer
```

See [SKILLS.md](SKILLS.md) for full skill installation and management reference.

---

## Updating

### Check for updates

```powershell
felix plugin update --dry-run          # Report available updates without installing
felix plugin update --dry-run --all    # Check all installed plugins
```

Output shows current version, latest compatible version, and whether `felix_min` is satisfied.

### Apply updates

```powershell
felix plugin update my-plugin          # Update a specific plugin
felix plugin update --all              # Update all installed plugins
felix plugin update --all --channel beta  # Include beta versions
```

Felix downloads the new archive, verifies the SHA256, and replaces the existing plugin directory. The old version is not kept — use git to recover if needed.

---

## Index Format

The marketplace index is a single JSON file. Schema version: `index-v1`.

```json
{
  "schema": "index-v1",
  "updated": "2026-06-01T00:00:00Z",
  "plugins": [
    {
      "id":          "learning-capture",
      "name":        "Learning Capture",
      "description": "Captures learnings from run events and proposes AGENTS.md additions.",
      "categories":  ["learning", "reference"],
      "maintainer":  "felix-team",
      "versions": [
        {
          "v":         "1.0.0",
          "url":       "https://nsasto.github.io/felix/artifacts/learning-capture-1.0.0.zip",
          "sha256":    "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
          "felix_min": "1.3.0",
          "channel":   "stable"
        }
      ]
    }
  ],
  "skills": [
    {
      "id":          "security-review",
      "name":        "Security Review",
      "description": "Automated security review of diffs.",
      "categories":  ["security", "review"],
      "maintainer":  "felix-team",
      "versions": [
        {
          "v":         "1.0.0",
          "url":       "https://nsasto.github.io/felix/artifacts/skill-security-review-1.0.0.zip",
          "sha256":    "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
          "felix_min": "1.3.0",
          "channel":   "stable"
        }
      ]
    }
  ]
}
```

### Top-level fields

| Field | Type | Description |
|---|---|---|
| `schema` | `string` | Always `"index-v1"`. Increment to v2 for breaking changes. |
| `updated` | `string` | ISO 8601 timestamp of the last index update. |
| `plugins` | `object[]` | List of plugin entries. |
| `skills` | `object[]` | List of skill entries. |

### Entry fields (plugins and skills)

| Field | Type | Description |
|---|---|---|
| `id` | `string` | Unique kebab-case identifier. Must match the directory name. |
| `name` | `string` | Human-readable display name. |
| `description` | `string` | One-line description. |
| `categories` | `string[]` | Tags for filtering (e.g., `"security"`, `"reference"`). |
| `maintainer` | `string` | Author or team name. |
| `versions` | `object[]` | Ordered list of available versions (see below). |

### Version entry fields

| Field | Type | Description |
|---|---|---|
| `v` | `string` | SemVer version string (e.g., `"1.0.0"`). |
| `url` | `string` | Direct download URL for the ZIP archive. |
| `sha256` | `string` | Hex-encoded SHA256 digest of the ZIP archive. |
| `felix_min` | `string` | Minimum Felix version required (SemVer). |
| `channel` | `string` | Release channel: `"stable"` or `"beta"`. |

---

## Hosting a Private Registry

Override the index URL in `.felix/config.json`:

```json
"distribution": {
  "index_url": "https://my-company.internal/felix/plugins.json",
  "channels":  ["stable"]
}
```

Your private `plugins.json` must follow the same `index-v1` schema. Host it anywhere accessible from your development machines: GitHub Pages, Artifactory, S3, or a plain static file server.

**To include both public and private plugins**, maintain your own index that contains your private entries plus copies (or references) to the public entries you want to expose. Felix reads only one index URL — multi-index support is not implemented in v2.

---

## SHA256 Verification

Felix verifies the SHA256 checksum of every archive before extraction. If the checksum does not match the index entry, the install is rejected with an error.

**To compute the SHA256 of your archive before publishing:**

```powershell
(Get-FileHash .\my-plugin-1.0.0.zip -Algorithm SHA256).Hash.ToLower()
```

```bash
# Linux / macOS
sha256sum my-plugin-1.0.0.zip
```

Paste the hex string (lowercase, no spaces) into the `sha256` field of your index entry.

**Why this matters:** SHA256 verification ensures that an attacker who controls DNS or a CDN cannot substitute a malicious archive for a legitimate one. Always compute the hash from the final published file, not from a pre-upload copy.

---

*See also: [PLUGINS.md](PLUGINS.md) for plugin authoring · [SKILLS.md](SKILLS.md) for skill authoring · [CONFIGURATION.md](CONFIGURATION.md) for `distribution` config keys*
