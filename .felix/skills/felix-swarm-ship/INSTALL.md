# Install felix-swarm-ship on other agents

Canonical location in this repo:

```text
.felix/skills/felix-swarm-ship/
  skill.json    # Felix manifest
  prompt.md     # In-loop Felix fragment ({{SKILLS}})
  SKILL.md      # Portable playbook for outer coding agents
  INSTALL.md    # This file
```

## Felix (this repo or another project)

```powershell
# From a clone of felix, into the current project
felix skill install .\.felix\skills\felix-swarm-ship --scope repo

# Or user-wide
felix skill install .\.felix\skills\felix-swarm-ship --scope user
```

## Grok Build

Copy the skill directory (or at least `SKILL.md`) to:

```text
%USERPROFILE%\.grok\skills\felix-swarm-ship\SKILL.md
```

Or project-local: `<repo>\.grok\skills\felix-swarm-ship\SKILL.md`

Then invoke `/felix-swarm-ship` or ask to publish a requirement to Felix cloud.

## Codex CLI / Codex app

Copy `SKILL.md` into your Codex skills directory (typical patterns):

```text
%USERPROFILE%\.agents\skills\felix-swarm-ship\SKILL.md
# or the skills path shown by your Codex version's docs /agents skills
```

Keep the YAML frontmatter at the top of `SKILL.md`.

## Claude Code / Claude Desktop

```text
%USERPROFILE%\.claude\skills\felix-swarm-ship\SKILL.md
# or project: <repo>\.claude\skills\felix-swarm-ship\SKILL.md
```

## Keep copies in sync

Treat **this repo path** as canonical. After editing, refresh host copies:

```powershell
# Example: refresh Grok user skill from repo
Copy-Item C:\dev\felix\.felix\skills\felix-swarm-ship\SKILL.md `
  $env:USERPROFILE\.grok\skills\felix-swarm-ship\SKILL.md -Force
```
