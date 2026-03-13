# Git Commit Message Rules

> **Status:** Reference — Enforced commit conventions

## Overview

Felix now supports automatic commit message rewriting and validation through `.git-commit-rules.json`. This system strips unwanted content (like Droid co-author trailers) and enforces message standards.

## Features

- **regex-replace**: Rewrite or strip patterns from messages
- **prepend/append**: Add text blocks to messages
- **require**: Validation - message must match pattern
- **denylist**: Validation - message must NOT match pattern
- **normalize**: Automatic whitespace/blank line cleanup

## Configuration

Rules are defined in [.git-commit-rules.json](../.git-commit-rules.json) at the repository root.

### Active Rules

**Strip Droid co-author trailer** (enabled)

- Automatically removes `Co-authored-by: Droid` lines that Droid adds to commits
- Pattern: `(?m)^[ \t]*Co-authored-by:\s*Droid\b.*\r?\n?`
- Keeps human co-author lines intact

**Normalization** (enabled)

- Trims trailing whitespace from lines
- Collapses excessive blank lines (max 2)
- Trims leading/trailing blank lines
- Ensures final newline

### Available Rules (disabled by default)

**Require Conventional Commit format**

- Enforce commit message format: `feat: description` or `fix(scope): description`
- Enable by setting `"enabled": true` in config

**Deny all co-author trailers**

- Block ANY co-author lines (including human ones)
- Useful for strict single-author policies

**Prepend ticket reference**

- Automatically add ticket/issue reference to all commits

**Append signoff**

- Automatically add `Signed-off-by:` trailer

## Usage

Rules are automatically applied whenever `Invoke-GitCommit` is called:

```powershell
# Normal commit (rules applied automatically)
Invoke-GitCommit -Message "feat: Add new feature`n`nCo-authored-by: Droid"
# Result: Droid line removed, message normalized

# Commit and push
Invoke-GitCommit -Message "fix: Bug fix" -Push

# If validation rules fail, commit is rejected with error message
```

## Rule Types

### regex-replace

Rewrites message content using regex pattern matching.

```json
{
  "name": "Strip Droid co-author trailer",
  "enabled": true,
  "type": "regex-replace",
  "pattern": "(?m)^[ \\t]*Co-authored-by:\\s*Droid\\b.*\\r?\\n?",
  "replacement": ""
}
```

### prepend

Adds text block at the beginning of the message.

```json
{
  "name": "Prepend ticket",
  "enabled": false,
  "type": "prepend",
  "text": "Refs: ABC-123"
}
```

### append

Adds text block at the end of the message.

```json
{
  "name": "Append signoff",
  "enabled": false,
  "type": "append",
  "text": "Signed-off-by: Your Name <you@example.com>"
}
```

### require

Validates that message matches pattern (fails commit if not).

```json
{
  "name": "Require Conventional Commit-ish header",
  "enabled": false,
  "type": "require",
  "pattern": "^(feat|fix|docs|chore|refactor|test|build|ci|perf|revert)(\\([^)]+\\))?: .+"
}
```

### denylist

Validates that message does NOT match pattern (fails commit if matches).

```json
{
  "name": "Deny any other co-author trailers",
  "enabled": false,
  "type": "denylist",
  "pattern": "(?mi)^[ \\t]*Co-authored-by:"
}
```

## Implementation Details

### Functions

**Get-CommitRulesConfig**

- Loads and parses `.git-commit-rules.json`
- Returns `$null` if file doesn't exist (rules system disabled)

**Apply-CommitRules**

- Processes message through all enabled rules
- Returns hashtable: `@{ Message = $string; Errors = $array }`
- Rewrites happen before validations
- Normalization happens last

**Normalize-CommitMessage**

- Cleans up whitespace and blank lines
- Controlled by `options.normalize` in config

**Invoke-GitCommit** (updated)

- Applies rules before committing
- Rejects commit if validation rules fail
- Uses temp file for commit message (supports multi-line)
- Cleans up temp file automatically

### Error Handling

- Invalid regex patterns are caught and reported
- Empty messages after rule application are rejected
- Validation failures list all failed rules
- Original message is never committed if any rule fails

## Testing Rules

Test rule application without committing:

```powershell
# Load functions
. .\.felix\core\git-manager.ps1

# Load config
$cfg = Get-CommitRulesConfig -Path ".git-commit-rules.json"

# Test a message
$testMsg = "feat: New feature`n`nCo-authored-by: Droid"
$result = Apply-CommitRules -Message $testMsg -Config $cfg

# Check results
Write-Host $result.Message
$result.Errors  # Should be empty if valid
```

## Adding New Rules

1. Edit [.git-commit-rules.json](../.git-commit-rules.json)
2. Add rule to `rules` array
3. Set `"enabled": true`
4. Test with sample messages
5. Commit the config change

Example - require issue reference:

```json
{
  "name": "Require issue reference",
  "enabled": true,
  "type": "require",
  "pattern": "(?i)(fixes?|closes?|refs?)\\s*#\\d+"
}
```

## Future Enhancements

### Git Hooks (Optional)

To enforce rules for ALL commits (VS Code, GitHub Desktop, etc.), add a `commit-msg` hook:

1. Create `.git/hooks/commit-msg` (or `commit-msg.ps1` on Windows)
2. Make it load `.git-commit-rules.json` and call `Apply-CommitRules`
3. Exit with non-zero code if validation fails

This ensures rules apply regardless of commit tool used.

---

**Related Files:**

- [git-manager.ps1](../.felix/core/git-manager.ps1) - Implementation
- [.git-commit-rules.json](../.git-commit-rules.json) - Configuration
