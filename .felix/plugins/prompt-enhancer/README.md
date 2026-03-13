# Prompt Enhancer Plugin

Enhances LLM prompts with additional context and best practices to improve code quality and reduce errors.

## Features

- **Git Statistics**: Adds recent commit activity and modified files
- **Recent Errors**: Includes information about failed iterations to avoid repeating mistakes
- **Coding Standards**: Injects project coding standards if available
- **Best Practices**: Adds reminders for testing, documentation, and commit messages

## Configuration

Edit `plugin.json` to enable/disable features:

```json
{
  "config": {
    "add_git_stats": true,
    "add_recent_errors": true,
    "add_coding_standards": false
  }
}
```

## Hooks Implemented

### OnContextGathering
Gathers additional context like git statistics and repository activity.

### OnPreLLM
Modifies the prompt before LLM execution to include:
- Recent error history
- Coding standards (if file exists at `docs/CODING_STANDARDS.md`)
- Best practices reminders

## Example Enhanced Content

```markdown
## Recent Repository Activity

- Commits in last 7 days: 15
- Recently modified files:
  - src/app.js
  - package.json
  - README.md

---

# Recent Errors to Avoid

The following recent iterations encountered errors:
- Run 2026-01-27T10-15-00: Failed

Please learn from these failures and avoid repeating the same mistakes.

---

# Best Practices Reminder

- Always run tests before marking a task complete
- Write clear, self-documenting code
- Follow existing code patterns in the repository
```

## Testing

```powershell
cd ..felix/plugins
.\test-harness.ps1 -PluginPath .\prompt-enhancer -RunAll
```

## Permissions Required

- `read:specs` - Read spec files for context
- `read:state` - Read Felix state information
- `git:read` - Read git repository statistics

## Benefits

- **Improved Quality**: Reminders about testing and standards reduce bugs
- **Context Awareness**: LLM knows about recent changes and errors
- **Consistency**: Coding standards are automatically reinforced
- **Learning**: Agent learns from past mistakes


