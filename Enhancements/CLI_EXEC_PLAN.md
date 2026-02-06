# Felix CLI Execution Plan - Option B: C# CLI

## Document Purpose

Detailed implementation plan for building `felix.exe` as a thin wrapper over `felix.ps1`. This is the corrected approach where the C# CLI delegates to PowerShell rather than reimplementing logic.

**Date Created:** 2026-02-06  
**Status:** Ready to Start  
**Related Docs:** [CLI_EXEC_IMPLEMENTATION.md](CLI_EXEC_IMPLEMENTATION.md), [CLI_MIGRATION.md](CLI_MIGRATION.md)

---

## Architecture Decision

### The Thin Wrapper Approach

```
felix.exe (C#)
    ↓ System.CommandLine parsing
    ↓ Argument validation
    ↓ calls: pwsh -File felix.ps1 <command> <args>
    ↓ streams output
    ↓ exits with same code
    ↓
felix.ps1 (PowerShell) ← UNCHANGED
    ↓ existing routing logic
    ↓ delegates to felix-agent.ps1, spec-builder.ps1, etc.
    ↓
Scripts (PowerShell/Python) ← UNCHANGED
    ↓ all business logic
```

### Why This Approach

✅ **Single source of truth** - felix.ps1 remains canonical CLI implementation  
✅ **Zero logic duplication** - C# doesn't reimplement routing or business logic  
✅ **Minimal code** - ~200 lines of C# vs ~800 lines if porting logic  
✅ **Safe migration** - PowerShell CLI remains functional fallback  
✅ **Easy maintenance** - Changes to commands only touch felix.ps1  
✅ **No behavior drift** - Impossible to have different behavior between CLIs

### What felix.exe Provides

1. **Better argument parsing** - System.CommandLine validation and help
2. **Professional UX** - Native .exe feels more polished than .ps1
3. **Tab completion** - Generate completion scripts automatically
4. **Faster startup** - Pre-validated args before calling PowerShell
5. **Distribution** - Single file .exe easier to install than PowerShell module

### What felix.exe Does NOT Do

❌ Implement command logic  
❌ Parse NDJSON events  
❌ Read requirements.json  
❌ Execute agent workflows  
❌ Validate requirements  
❌ Build specs

All logic stays in PowerShell/Python scripts.

---

## Implementation Plan

### Week 1: MVP - Core Commands

**Day 1: Project Setup**

```bash
# Create project
cd c:\dev\Felix
mkdir src
dotnet new console -n Felix.Cli -o src/Felix.Cli
cd src/Felix.Cli

# Add packages
dotnet add package System.CommandLine --prerelease
dotnet add package System.CommandLine.NamingConventionBinder --prerelease

# Initial structure
```

**Day 2-3: Command Definitions**

```csharp
// src/Felix.Cli/Program.cs

using System.CommandLine;
using System.Diagnostics;

namespace Felix.Cli;

class Program
{
    static async Task<int> Main(string[] args)
    {
        var rootCommand = new RootCommand("Felix - Autonomous agent executor");

        // Get repository root (parent of .felix where exe lives)
        var exePath = AppDomain.CurrentDomain.BaseDirectory;
        var repoRoot = Path.GetFullPath(Path.Combine(exePath, "..", ".."));
        var felixPs1 = Path.Combine(repoRoot, ".felix", "felix.ps1");

        if (!File.Exists(felixPs1))
        {
            Console.Error.WriteLine($"Error: felix.ps1 not found at {felixPs1}");
            return 1;
        }

        // Add commands
        rootCommand.AddCommand(CreateRunCommand(felixPs1));
        rootCommand.AddCommand(CreateLoopCommand(felixPs1));
        rootCommand.AddCommand(CreateStatusCommand(felixPs1));
        rootCommand.AddCommand(CreateListCommand(felixPs1));
        rootCommand.AddCommand(CreateValidateCommand(felixPs1));
        rootCommand.AddCommand(CreateDepsCommand(felixPs1));
        rootCommand.AddCommand(CreateSpecCommand(felixPs1));
        rootCommand.AddCommand(CreateVersionCommand(felixPs1));

        return await rootCommand.InvokeAsync(args);
    }

    static Command CreateRunCommand(string felixPs1)
    {
        var cmd = new Command("run", "Execute a single requirement");

        var reqIdArg = new Argument<string>(
            name: "requirement-id",
            description: "Requirement ID (e.g., S-0001)"
        );
        cmd.AddArgument(reqIdArg);

        var formatOpt = new Option<string>(
            name: "--format",
            description: "Output format",
            getDefaultValue: () => "rich"
        );
        formatOpt.AddCompletions("json", "plain", "rich");
        cmd.AddOption(formatOpt);

        var verboseOpt = new Option<bool>("--verbose", "Enable verbose logging");
        cmd.AddOption(verboseOpt);

        var quietOpt = new Option<bool>("--quiet", "Suppress non-essential output");
        cmd.AddOption(quietOpt);

        cmd.SetHandler((reqId, format, verbose, quiet) =>
        {
            var args = new List<string> { "run", reqId };
            if (format != "rich") args.AddRange(new[] { "--format", format });
            if (verbose) args.Add("--verbose");
            if (quiet) args.Add("--quiet");

            return ExecutePowerShell(felixPs1, args.ToArray());
        }, reqIdArg, formatOpt, verboseOpt, quietOpt);

        return cmd;
    }

    static Command CreateLoopCommand(string felixPs1)
    {
        var cmd = new Command("loop", "Run agent in continuous loop mode");

        var maxIterOpt = new Option<int?>("--max-iterations", "Maximum iterations");
        cmd.AddOption(maxIterOpt);

        var formatOpt = new Option<string>("--format", () => "rich");
        formatOpt.AddCompletions("json", "plain", "rich");
        cmd.AddOption(formatOpt);

        cmd.SetHandler((maxIter, format) =>
        {
            var args = new List<string> { "loop" };
            if (maxIter.HasValue) args.AddRange(new[] { "--max-iterations", maxIter.Value.ToString() });
            if (format != "rich") args.AddRange(new[] { "--format", format });

            return ExecutePowerShell(felixPs1, args.ToArray());
        }, maxIterOpt, formatOpt);

        return cmd;
    }

    static Command CreateStatusCommand(string felixPs1)
    {
        var cmd = new Command("status", "Show requirement status");

        var reqIdArg = new Argument<string?>(
            name: "requirement-id",
            description: "Requirement ID (optional, shows summary if omitted)"
        );
        reqIdArg.Arity = ArgumentArity.ZeroOrOne;
        cmd.AddArgument(reqIdArg);

        var formatOpt = new Option<string>("--format", () => "rich");
        cmd.AddOption(formatOpt);

        cmd.SetHandler((reqId, format) =>
        {
            var args = new List<string> { "status" };
            if (!string.IsNullOrEmpty(reqId)) args.Add(reqId);
            if (format != "rich") args.AddRange(new[] { "--format", format });

            return ExecutePowerShell(felixPs1, args.ToArray());
        }, reqIdArg, formatOpt);

        return cmd;
    }

    static Command CreateListCommand(string felixPs1)
    {
        var cmd = new Command("list", "List all requirements");

        var statusOpt = new Option<string?>("--status", "Filter by status");
        statusOpt.AddCompletions("planned", "in_progress", "done", "complete", "blocked");
        cmd.AddOption(statusOpt);

        var priorityOpt = new Option<string?>("--priority", "Filter by priority");
        priorityOpt.AddCompletions("low", "medium", "high", "critical");
        cmd.AddOption(priorityOpt);

        var labelsOpt = new Option<string?>("--labels", "Filter by labels (comma-separated)");
        cmd.AddOption(labelsOpt);

        var blockedByOpt = new Option<string?>("--blocked-by", "Filter by blocker type");
        blockedByOpt.AddCompletions("incomplete-deps");
        cmd.AddOption(blockedByOpt);

        var withDepsOpt = new Option<bool>("--with-deps", "Show dependencies inline");
        cmd.AddOption(withDepsOpt);

        var formatOpt = new Option<string>("--format", () => "rich");
        cmd.AddOption(formatOpt);

        cmd.SetHandler((status, priority, labels, blockedBy, withDeps, format) =>
        {
            var args = new List<string> { "list" };
            if (status != null) args.AddRange(new[] { "--status", status });
            if (priority != null) args.AddRange(new[] { "--priority", priority });
            if (labels != null) args.AddRange(new[] { "--labels", labels });
            if (blockedBy != null) args.AddRange(new[] { "--blocked-by", blockedBy });
            if (withDeps) args.Add("--with-deps");
            if (format != "rich") args.AddRange(new[] { "--format", format });

            return ExecutePowerShell(felixPs1, args.ToArray());
        }, statusOpt, priorityOpt, labelsOpt, blockedByOpt, withDepsOpt, formatOpt);

        return cmd;
    }

    static Command CreateValidateCommand(string felixPs1)
    {
        var cmd = new Command("validate", "Run validation checks");

        var reqIdArg = new Argument<string>("requirement-id");
        cmd.AddArgument(reqIdArg);

        cmd.SetHandler((reqId) =>
        {
            return ExecutePowerShell(felixPs1, "validate", reqId);
        }, reqIdArg);

        return cmd;
    }

    static Command CreateDepsCommand(string felixPs1)
    {
        var cmd = new Command("deps", "Show dependencies and validate status");

        var reqIdArg = new Argument<string?>("requirement-id");
        reqIdArg.Arity = ArgumentArity.ZeroOrOne;
        cmd.AddArgument(reqIdArg);

        var checkOpt = new Option<bool>("--check", "Quick validation check only");
        cmd.AddOption(checkOpt);

        var treeOpt = new Option<bool>("--tree", "Show full dependency tree");
        cmd.AddOption(treeOpt);

        var incompleteOpt = new Option<bool>("--incomplete", "List all requirements with incomplete dependencies");
        cmd.AddOption(incompleteOpt);

        cmd.SetHandler((reqId, check, tree, incomplete) =>
        {
            var args = new List<string> { "deps" };

            if (incomplete)
            {
                args.Add("--incomplete");
            }
            else if (!string.IsNullOrEmpty(reqId))
            {
                args.Add(reqId);
                if (check) args.Add("--check");
                if (tree) args.Add("--tree");
            }
            else
            {
                Console.Error.WriteLine("Error: requirement-id required unless using --incomplete");
                return Task.FromResult(1);
            }

            return ExecutePowerShell(felixPs1, args.ToArray());
        }, reqIdArg, checkOpt, treeOpt, incompleteOpt);

        return cmd;
    }

    static Command CreateSpecCommand(string felixPs1)
    {
        var cmd = new Command("spec", "Spec management utilities");

        // spec create
        var createCmd = new Command("create", "Create a new specification");
        var descArg = new Argument<string?>("description", "Feature description (optional for interactive mode)");
        descArg.Arity = ArgumentArity.ZeroOrOne;
        createCmd.AddArgument(descArg);

        var quickOpt = new Option<bool>(new[] { "--quick", "-q" }, "Quick mode with minimal questions");
        createCmd.AddOption(quickOpt);

        createCmd.SetHandler((desc, quick) =>
        {
            var args = new List<string> { "spec", "create" };
            if (!string.IsNullOrEmpty(desc)) args.Add(desc);
            if (quick) args.Add("--quick");

            return ExecutePowerShell(felixPs1, args.ToArray());
        }, descArg, quickOpt);

        // spec fix
        var fixCmd = new Command("fix", "Align specs folder with requirements.json");
        var fixDupsOpt = new Option<bool>(new[] { "--fix-duplicates", "-f" }, "Auto-rename duplicate spec files");
        fixCmd.AddOption(fixDupsOpt);

        fixCmd.SetHandler((fixDups) =>
        {
            var args = new List<string> { "spec", "fix" };
            if (fixDups) args.Add("--fix-duplicates");

            return ExecutePowerShell(felixPs1, args.ToArray());
        }, fixDupsOpt);

        // spec delete
        var deleteCmd = new Command("delete", "Delete a specification");
        var delReqIdArg = new Argument<string>("requirement-id");
        deleteCmd.AddArgument(delReqIdArg);

        deleteCmd.SetHandler((reqId) =>
        {
            return ExecutePowerShell(felixPs1, "spec", "delete", reqId);
        }, delReqIdArg);

        cmd.AddCommand(createCmd);
        cmd.AddCommand(fixCmd);
        cmd.AddCommand(deleteCmd);

        return cmd;
    }

    static Command CreateVersionCommand(string felixPs1)
    {
        var cmd = new Command("version", "Show version information");

        cmd.SetHandler(() =>
        {
            return ExecutePowerShell(felixPs1, "version");
        });

        return cmd;
    }

    static Task<int> ExecutePowerShell(string felixPs1, params string[] args)
    {
        var quotedArgs = string.Join(" ", args.Select(a => a.Contains(' ') ? $"\"{a}\"" : a));

        var psi = new ProcessStartInfo
        {
            FileName = "pwsh",
            Arguments = $"-NoProfile -File \"{felixPs1}\" {quotedArgs}",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = false,
            CreateNoWindow = false
        };

        var process = new Process { StartInfo = psi };

        process.OutputDataReceived += (sender, e) =>
        {
            if (e.Data != null) Console.WriteLine(e.Data);
        };

        process.ErrorDataReceived += (sender, e) =>
        {
            if (e.Data != null) Console.Error.WriteLine(e.Data);
        };

        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        process.WaitForExit();

        return Task.FromResult(process.ExitCode);
    }
}
```

**Day 4: Build and Package**

```bash
# Test locally
dotnet run -- run S-0001
dotnet run -- list --status planned
dotnet run -- deps --incomplete

# Publish single-file exe
dotnet publish -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -o ../../.felix/bin

# Test installed version
.felix\bin\Felix.Cli.exe run S-0001
```

**Day 5: Installation Script**

```powershell
# scripts/install-cli-csharp.ps1

$ErrorActionPreference = "Stop"

$felixBin = Join-Path $PSScriptRoot ".." ".felix" "bin"
$exePath = Join-Path $felixBin "Felix.Cli.exe"

if (-not (Test-Path $exePath)) {
    Write-Error "felix.exe not found. Run: dotnet publish from src/Felix.Cli"
    exit 1
}

# Add to PATH
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$felixBin*") {
    Write-Host "Adding $felixBin to User PATH..."
    [Environment]::SetEnvironmentVariable("Path", "$currentPath;$felixBin", "User")
    Write-Host "PATH updated. Restart terminal or run: `$env:Path = [Environment]::GetEnvironmentVariable('Path', 'User')"
}

# Create alias (optional)
Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host "Usage: Felix.Cli.exe run S-0001" -ForegroundColor Cyan
Write-Host "  Or:  felix run S-0001 (after PATH reload)" -ForegroundColor Cyan
```

---

### Week 2: Enhancement and Polish

**Day 6-7: Tab Completion**

Generate completion scripts using System.CommandLine:

```bash
# Generate completions
Felix.Cli.exe --generate-completion-script pwsh > felix-completion.ps1
Felix.Cli.exe --generate-completion-script bash > felix-completion.bash

# Install PowerShell completion
# Add to $PROFILE
. $PSScriptRoot\.felix\bin\felix-completion.ps1
```

**Day 8-9: Testing and Documentation**

```powershell
# Test matrix
$commands = @(
    "run S-0001",
    "loop --max-iterations 5",
    "status",
    "status S-0001",
    "list --status planned",
    "list --blocked-by incomplete-deps --with-deps",
    "validate S-0001",
    "deps S-0018",
    "deps --incomplete",
    "spec create 'Test feature'",
    "spec fix",
    "spec fix --fix-duplicates",
    "spec delete S-9999",
    "version"
)

foreach ($cmd in $commands) {
    Write-Host "`nTesting: felix $cmd" -ForegroundColor Cyan
    Invoke-Expression "felix $cmd"
    Write-Host "Exit code: $LASTEXITCODE" -ForegroundColor Gray
}
```

**Day 10: Cross-Platform Build (Optional)**

```bash
# Linux
dotnet publish -c Release -r linux-x64 --self-contained false -p:PublishSingleFile=true

# macOS
dotnet publish -c Release -r osx-x64 --self-contained false -p:PublishSingleFile=true
```

---

## File Structure

```
c:\dev\Felix\
├── src/
│   └── Felix.Cli/
│       ├── Felix.Cli.csproj
│       ├── Program.cs
│       └── README.md
├── .felix/
│   ├── bin/
│   │   └── Felix.Cli.exe  ← Published here
│   ├── felix.ps1          ← Called by Felix.Cli.exe
│   ├── felix-agent.ps1
│   └── ... (unchanged)
└── scripts/
    └── install-cli-csharp.ps1
```

---

## Testing Strategy

### Behavior Validation

```powershell
# Test that felix.exe produces identical output to felix.ps1
$testCases = @("run S-0001", "status", "list")

foreach ($test in $testCases) {
    $ps1Output = & .felix\felix.ps1 $test.Split()
    $exeOutput = & .felix\bin\Felix.Cli.exe $test.Split()

    if ($ps1Output -ne $exeOutput) {
        Write-Error "Mismatch for: $test"
    }
}
```

### Exit Code Validation

```powershell
# Test exit codes match
felix.exe run S-9999  # Should exit 1 (not found)
$exeCode = $LASTEXITCODE

.felix\felix.ps1 run S-9999
$ps1Code = $LASTEXITCODE

if ($exeCode -ne $ps1Code) {
    Write-Error "Exit code mismatch: exe=$exeCode ps1=$ps1Code"
}
```

---

## Migration Path

### Phase 1: Coexistence (Week 1-2)

- Both felix.ps1 and Felix.Cli.exe work
- Users choose which to install
- Documentation shows both options

### Phase 2: Soft Promotion (Week 3-4)

- Default to Felix.Cli.exe in docs
- Keep felix.ps1 as fallback
- Monitor for issues

### Phase 3: Primary (Month 2+)

- Felix.Cli.exe is recommended
- felix.ps1 for troubleshooting
- No plans to remove felix.ps1

---

## Success Metrics

✅ **Performance**: Felix.Cli.exe launches within 100ms (vs ~2s for pwsh startup)  
✅ **Compatibility**: All 11 commands work identically to felix.ps1  
✅ **Distribution**: Single .exe file under 10MB  
✅ **Exit codes**: Match felix.ps1 exactly  
✅ **Cross-platform**: Works on Windows, Linux (stretch goal), macOS (stretch goal)

---

## Risk Mitigation

**Risk: felix.ps1 changes break Felix.Cli.exe**

- Mitigation: Integration tests run both CLIs on every commit
- If felix.ps1 adds new flags, just pass them through

**Risk: PowerShell not installed**

- Mitigation: Bundle pwsh.exe or detect and prompt to install
- Self-contained publish option (larger file)

**Risk: Path issues finding felix.ps1**

- Mitigation: Exe knows its location, calculates relative path
- Fallback to environment variable FELIX_ROOT

**Risk: Behavior drift between implementations**

- Mitigation: Felix.Cli.exe has ZERO business logic - impossible to drift
- All logic in felix.ps1 which is single source of truth

---

## Future Enhancements (Post-Week 2)

### Interactive Mode with Spectre.Console

```csharp
// Show live progress during agent runs
AnsiConsole.Status()
    .Start("Running requirement...", ctx =>
    {
        // Parse NDJSON from felix.ps1 stdout
        // Render with Spectre.Console
    });
```

### Better Error Messages

```csharp
// Catch common mistakes before calling PowerShell
if (requirementId == "S-001") {
    AnsiConsole.MarkupLine("[yellow]Did you mean S-0001? Requirement IDs need 4 digits.[/]");
}
```

### Self-Update Mechanism

```csharp
// felix update command
// Downloads latest Felix.Cli.exe from GitHub releases
```

---

## Comparison: Before vs After

### Before (PowerShell only)

```powershell
# Slower startup (~2s)
PS> .\.felix\felix.ps1 run S-0001

# Less discoverable
PS> Get-Help .\.felix\felix.ps1  # Doesn't show subcommands
```

### After (C# CLI)

```bash
# Faster startup (~100ms)
PS> felix run S-0001

# Better discoverability
PS> felix --help  # Shows all commands with descriptions
PS> felix run --help  # Shows run-specific help
PS> felix run S-0<TAB>  # Auto-completes requirement IDs
```

### Both Work (Fallback)

```powershell
# If felix.exe has issues, use felix.ps1 directly
PS> .\.felix\felix.ps1 run S-0001

# Both produce identical results
# Both use same scripts
# Both read same config
```

---

## Recommendation

**Start Week 1 immediately:**

1. ✅ Phase 1 CLI complete (felix.ps1 working perfectly)
2. ✅ All commands documented and tested
3. ✅ Clear thin-wrapper architecture
4. ✅ Minimal code (~200 lines)
5. ✅ Safe coexistence strategy

**Expected outcome:**

- Week 1: Working felix.exe with all commands
- Week 2: Polished, documented, installed
- Total effort: 5-7 days (not 1-2 weeks full-time)

Ready to proceed with project setup?
