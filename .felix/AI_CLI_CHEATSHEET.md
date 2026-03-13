# AI Coding Assistants CLI Cheat Sheet

Covers practical terminal usage for:

- Claude Code (Anthropic)
- Codex CLI (OpenAI)
- Gemini CLI (Google)
- Factory.ai Droid

This focuses on the commands you actually use in real workflows, not every flag.

---

## Claude Code (Anthropic)

### Install

```bash
curl -fsSL https://claude.ai/install.sh | bash
# or
brew install --cask claude-code
```

### First run

```bash
claude
/login
```

### Common usage

```bash
# Interactive
claude

# Start with a prompt
claude "explain this project"

# One-shot, script friendly
claude -p "explain this function"

# Pipe logs into it
cat logs.txt | claude -p "summarize errors and likely causes"

# Continue last session in this directory
claude -c

# Resume named session
claude -r "auth-refactor" "finish the PR"
```

### High value flags

```bash
claude --add-dir ../apps ../lib
claude --model sonnet
claude -p "query" --output-format json
claude --tools "Read,Edit,Bash"
claude --permission-mode plan
claude --append-system-prompt "Prefer minimal diffs and run tests first"
```

---

## Codex CLI (OpenAI)

### Install

```bash
npm i -g @openai/codex
codex
```

### Common usage

```bash
# Run in a repo
codex -C path/to/repo "scan and suggest a small safe refactor"

# Add writable directories
codex --add-dir ../shared-lib

# Choose model
codex -m gpt-5-codex "implement feature with tests"

# Approval mode
codex -a on-request "fix failing tests"

# Sandbox level
codex -s read-only "audit this repo"
codex -s workspace-write "apply fix and run tests"

# Use live web search
codex --search "latest breaking changes for dependency X"
```

### Useful slash commands (inside Codex)

```
/permissions
/diff
/compact
/init
/model
/mcp
/logout
/exit
```

---

## Gemini CLI (Google)

### Install

```bash
npm install -g @google/gemini-cli
gemini
```

### Common usage

```bash
# Interactive
gemini

# One-shot
gemini "explain this project"

# Script friendly
gemini -p "explain this function"

# Pipe logs
cat logs.txt | gemini -p "summarize errors"

# Plan then stay interactive
gemini -i "help me plan a refactor"

# Resume last session
gemini -r "latest"
```

### Useful flags

```bash
gemini -m auto "review these changes"
gemini --sandbox
gemini --approval-mode=auto_edit
gemini --allowed-tools grep,terminal
gemini -p "run tests and summarize failures" --output-format json
gemini -p "run tests" --output-format stream-json
```

### Interactive commands

```
/auth
/model
/mcp
/memory
/compress
/restore
/quit
```

---

## Factory.ai Droid

### Install

```bash
brew tap factory-ai/tap
brew install droid
```

### Common usage

```bash
# Interactive in repo
droid

# One-shot
droid "scan this repo and propose a minimal refactor plan"

# Specific directory
droid -C path/to/repo "add tests for uncovered modules"

# Resume session
droid --resume

# Script friendly JSON
droid -p "summarize failing tests" --output json
```

### High value flags

```bash
droid --profile fast
droid --profile deep
droid --read-only
droid --workspace-write
droid --approval on-request
droid --add-dir ../shared ../infra
droid --scope src/,tests/
droid --attach trace.log,ui.png
droid -p "run tests and summarize" --output stream-json
```

### Interactive commands

```
/status
/permissions
/diff
/plan
/commit
/model
/mcp
/exit
```

---

## Mental model differences from the terminal

| Tool        | Strength                                                      | What it feels best at                               |
| ----------- | ------------------------------------------------------------- | --------------------------------------------------- |
| Claude Code | Tight tool control, system prompt shaping, structured output  | Careful refactors, controlled edits, CI scripting   |
| Codex CLI   | Strong approvals and sandboxing, great TUI flow               | Safe autonomous fixes inside repos                  |
| Gemini CLI  | Excellent headless and JSON streaming, rich built-in commands | Automation and pipeline friendly workflows          |
| Droid       | Plan → diff → approve → commit loop, repo aware               | Test driven refactors and clean, reviewable patches |

---

## Common patterns that work across all four

### Safe audit

```bash
<tool> --read-only "audit for dead code, risky patterns, and missing tests"
```

### Small safe fix

```bash
<tool> --workspace-write --approval on-request \
"fix the smallest issue causing test failures and show diff"
```

### CI helper step

```bash
<tool> -p "summarize linter/test output and propose a patch" --output json
```

### Use logs as input

```bash
cat test-output.txt | <tool> -p "summarize failures and likely root causes"
```

---
