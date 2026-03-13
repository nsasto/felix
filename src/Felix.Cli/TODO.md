# Felix.Cli TODO

## Installation & Distribution (Day 4-5)

### Installation Script

- [x] Create `scripts/install-cli-csharp.ps1`
- [ ] Test PATH installation across terminal sessions
- [ ] Verify installation on fresh machine
- [ ] Add uninstall option

### Documentation

- [ ] Update HOW_TO_USE.md with C# CLI section
  - Installation instructions
  - Usage examples with `Felix.Cli.exe`
  - Explain coexistence with `felix.ps1`
  - Troubleshooting section
- [ ] Document `--ui` flag for enhanced output
- [ ] Add screenshots/examples of Spectre.Console UI

### Optional Enhancements

- [ ] Tab completion registration (System.CommandLine built-in)
- [ ] Create shorter alias: `felix.cmd` → `Felix.Cli.exe %*`
- [ ] Version detection in installer
- [ ] Check for updates mechanism

## Week 2 Enhancements (Deferred)

### Cross-Platform

- [ ] Linux build: `dotnet publish -r linux-x64`
- [ ] macOS build: `dotnet publish -r osx-x64`
- [ ] Test on non-Windows platforms

### Testing

- [ ] Behavior validation tests (output matches felix.ps1)
- [ ] Exit code validation tests
- [ ] Integration test matrix

### Advanced Features

- [ ] Self-update mechanism
- [ ] Config file support (.felixrc)
- [ ] Plugin system for custom commands

## Current TUI Features

### Completed

- [x] Add Spectre.Console package
- [x] Enhanced `status --ui` with color-coded table
- [x] Enhanced `list --ui` with rich table formatting
- [ ] Fix RuleStyle API usage (build error)

### In Progress

- [ ] Interactive requirement picker (arrow keys)
- [ ] Live agent execution monitor
- [ ] Dependency tree visualization
- [ ] Dashboard view with panels

### Ideas

- [ ] `felix watch` - live monitoring of agent runs
- [ ] `felix tree <req-id>` - visual dependency graph
- [ ] `felix dashboard` - real-time overview panel
- [ ] Prompt for interactive requirement selection
- [ ] Color themes (dark/light mode)
