# Contributing to Felix

Thanks for your interest in contributing! Felix is an open-source agent harness for autonomous coding loops.

## Getting Started

1. Fork the repo and clone your fork
2. Install dependencies: `.\scripts\install.ps1`
3. Create a branch: `git checkout -b my-feature`
4. Make your changes
5. Run tests: `.\run-test-spec.ps1`
6. Commit and push
7. Open a pull request

## What to Contribute

- **Bug fixes** — found something broken? Fix it and send a PR
- **Documentation** — typos, clarifications, new tutorials
- **New LLM integrations** — agent profiles for additional providers
- **Plugin development** — extend Felix with new sync or validation plugins
- **Platform support** — help Felix work better on Linux/macOS

## Code Style

- **PowerShell**: Must be PS 5.1 compatible — no `?:`, `??=`, or pipeline chain operators
- **Python**: Standard formatting, no strict linter enforced yet
- **Markdown**: Keep docs concise and operational

## Commit Messages

Use clear, descriptive commit messages. No specific format enforced, but prefer:

```
Short summary (50 chars or less)

Optional longer description explaining what and why.
```

## Reporting Issues

Open a GitHub issue with:

- What you expected to happen
- What actually happened
- Steps to reproduce
- Your OS and PowerShell version

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
