# Felix CLI Migration Guide

## Implementation Strategy

This document provides detailed implementation steps, code examples, and migration strategies for transitioning from PowerShell scripts to the unified `felix.exe` CLI.

## Phase 1: PowerShell CLI Enhancement

**Goal:** Polish the existing PowerShell CLI experience before building C# version.

**Timeline:** 1-2 weeks

**Status:** 🔜 Next

### 1.1: Enhance test-cli.ps1 → felix-cli.ps1

**Current State:**

```powershell
# test-cli.ps1 - Basic NDJSON consumer
# - Reads events from stdin
# - Renders with Write-Host
# - No format options
# - Limited filtering
```

**Target State:**

```powershell
# felix-cli.ps1 - Enhanced NDJSON consumer
# - Multiple format modes (json, plain, rich)
# - Event filtering by type/level
# - Statistics and summaries
# - Better error handling
# - Progress indicators
```

**Implementation Tasks:**

1. **Copy and Rename:**

   ```powershell
   Copy-Item .felix/test-cli.ps1 .felix/felix-cli.ps1
   ```

2. **Add Format Parameter:**

   ```powershell
   param(
       [Parameter(Mandatory=$true)]
       [string]$RepositoryPath,

       [Parameter(Mandatory=$false)]
       [string]$RequirementId,

       [Parameter(Mandatory=$false)]
       [int]$MaxIterations = 0,

       [Parameter(Mandatory=$false)]
       [ValidateSet("json", "plain", "rich")]
       [string]$Format = "rich"
   )
   ```

3. **Implement Format Renderers:**

   **JSON Mode (passthrough):**

   ```powershell
   function Render-Json {
       param([string]$Line)
       Write-Output $Line  # Pass through unchanged
   }
   ```

   **Plain Mode (colored text):**

   ```powershell
   function Render-Plain {
       param([PSCustomObject]$Event)

       $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
       $level = $Event.level ?? $Event.event
       $message = $Event.message ?? $Event.event

       switch ($level) {
           "error" { Write-Host "[$timestamp] ERROR  $message" -ForegroundColor Red }
           "warn"  { Write-Host "[$timestamp] WARN   $message" -ForegroundColor Yellow }
           "info"  { Write-Host "[$timestamp] INFO   $message" -ForegroundColor Cyan }
           default { Write-Host "[$timestamp] $level $message" }
       }
   }
   ```

   **Rich Mode (enhanced visuals):**

   ```powershell
   function Render-Rich {
       param([PSCustomObject]$Event)

       switch ($Event.event) {
           "run_started" {
               Write-Host "`n========================================" -ForegroundColor Cyan
               Write-Host "Running Requirement: $($Event.requirement_id)" -ForegroundColor Cyan
               Write-Host "========================================`n" -ForegroundColor Cyan
           }
           "task_started" {
               Write-Host "[TASK] $($Event.task) - Started" -ForegroundColor Yellow
           }
           "task_completed" {
               $color = if ($Event.status -eq "success") { "Green" } else { "Red" }
               Write-Host "[TASK] $($Event.task) - $($Event.status)" -ForegroundColor $color
           }
           "validation_passed" {
               Write-Host "  ✅ $($Event.criterion)" -ForegroundColor Green
           }
           "validation_failed" {
               Write-Host "  ❌ $($Event.criterion)" -ForegroundColor Red
           }
           "log" {
               Render-Plain -Event $Event
           }
           "error_occurred" {
               Write-Host "`n[ERROR] $($Event.message)" -ForegroundColor Red
               Write-Host "  Component: $($Event.component)" -ForegroundColor Gray
               if ($Event.details) {
                   Write-Host "  Details: $($Event.details)" -ForegroundColor Gray
               }
           }
       }
   }
   ```

4. **Add Event Filtering:**

   ```powershell
   param(
       # ... existing params ...

       [Parameter(Mandatory=$false)]
       [string[]]$EventTypes,

       [Parameter(Mandatory=$false)]
       [ValidateSet("error", "warn", "info", "debug")]
       [string]$MinLevel = "info"
   )

   function Should-Display-Event {
       param([PSCustomObject]$Event)

       # Filter by event type
       if ($EventTypes -and $Event.event -notin $EventTypes) {
           return $false
       }

       # Filter by log level
       if ($Event.level) {
           $levelOrder = @{ debug = 0; info = 1; warn = 2; error = 3 }
           $eventLevel = $levelOrder[$Event.level] ?? 1
           $minLevelValue = $levelOrder[$MinLevel]
           if ($eventLevel -lt $minLevelValue) {
               return $false
           }
       }

       return $true
   }
   ```

5. **Add Statistics:**

   ```powershell
   $stats = @{
       events = 0
       errors = 0
       warnings = 0
       tasks_completed = 0
       tasks_failed = 0
       validations_passed = 0
       validations_failed = 0
   }

   function Update-Stats {
       param([PSCustomObject]$Event)

       $stats.events++

       switch ($Event.event) {
           "error_occurred" { $stats.errors++ }
           "log" {
               if ($Event.level -eq "warn") { $stats.warnings++ }
               if ($Event.level -eq "error") { $stats.errors++ }
           }
           "task_completed" {
               if ($Event.status -eq "success") { $stats.tasks_completed++ }
               else { $stats.tasks_failed++ }
           }
           "validation_passed" { $stats.validations_passed++ }
           "validation_failed" { $stats.validations_failed++ }
       }
   }

   function Show-Stats {
       Write-Host "`n========================================" -ForegroundColor Cyan
       Write-Host "Execution Summary" -ForegroundColor Cyan
       Write-Host "========================================" -ForegroundColor Cyan
       Write-Host "Events Processed: $($stats.events)"
       Write-Host "Errors: $($stats.errors)" -ForegroundColor $(if ($stats.errors -gt 0) { "Red" } else { "Green" })
       Write-Host "Warnings: $($stats.warnings)" -ForegroundColor $(if ($stats.warnings -gt 0) { "Yellow" } else { "Green" })
       Write-Host "Tasks Completed: $($stats.tasks_completed)" -ForegroundColor Green
       Write-Host "Tasks Failed: $($stats.tasks_failed)" -ForegroundColor $(if ($stats.tasks_failed -gt 0) { "Red" } else { "Green" })
       Write-Host "Validations Passed: $($stats.validations_passed)" -ForegroundColor Green
       Write-Host "Validations Failed: $($stats.validations_failed)" -ForegroundColor $(if ($stats.validations_failed -gt 0) { "Red" } else { "Green" })
       Write-Host "========================================`n" -ForegroundColor Cyan
   }
   ```

### 1.2: Create felix.ps1 Dispatcher

**Purpose:** Command router that provides unified CLI interface

**Location:** `felix.ps1` (repository root)

**Implementation:**

```powershell
<#
.SYNOPSIS
Felix CLI dispatcher - unified command interface

.DESCRIPTION
Routes commands to appropriate Felix scripts with consistent interface.

.EXAMPLE
felix run S-0001
felix loop --max-iterations 5
felix status
felix list --status planned
felix validate S-0001
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("run", "loop", "status", "list", "validate", "version", "help")]
    [string]$Command,

    [Parameter(Mandatory=$false, Position=1, ValueFromRemainingArguments=$true)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"

# Determine repository root
$RepoRoot = $PSScriptRoot

# Parse global flags
$Format = "rich"
$Verbose = $false
$Quiet = $false

$remainingArgs = @()
for ($i = 0; $i -lt $Arguments.Count; $i++) {
    switch ($Arguments[$i]) {
        "--format" {
            $Format = $Arguments[++$i]
        }
        "--verbose" {
            $Verbose = $true
        }
        "--quiet" {
            $Quiet = $true
        }
        default {
            $remainingArgs += $Arguments[$i]
        }
    }
}

function Invoke-Run {
    param([string[]]$Args)

    if ($Args.Count -eq 0) {
        Write-Error "Usage: felix run <requirement-id> [--format <json|plain|rich>]"
        exit 1
    }

    $requirementId = $Args[0]

    # Start agent process
    $agentArgs = @(
        "-NoProfile",
        "-File", "$RepoRoot\.felix\felix-agent.ps1",
        $RepoRoot,
        "-RequirementId", $requirementId
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = $agentArgs -join " "
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.Start() | Out-Null

    # Pipe to felix-cli.ps1
    $cliArgs = @(
        "-NoProfile",
        "-File", "$RepoRoot\.felix\felix-cli.ps1",
        $RepoRoot,
        "-RequirementId", $requirementId,
        "-Format", $Format
    )

    $cliPsi = New-Object System.Diagnostics.ProcessStartInfo
    $cliPsi.FileName = "powershell.exe"
    $cliPsi.Arguments = $cliArgs -join " "
    $cliPsi.RedirectStandardInput = $true
    $cliPsi.UseShellExecute = $false
    $cliPsi.CreateNoWindow = $true

    $cliProcess = New-Object System.Diagnostics.Process
    $cliProcess.StartInfo = $cliPsi
    $cliProcess.Start() | Out-Null

    # Pipe agent stdout to CLI stdin
    while (!$process.StandardOutput.EndOfStream) {
        $line = $process.StandardOutput.ReadLine()
        $cliProcess.StandardInput.WriteLine($line)
    }

    $cliProcess.StandardInput.Close()
    $process.WaitForExit()
    $cliProcess.WaitForExit()

    exit $process.ExitCode
}

function Invoke-Loop {
    param([string[]]$Args)

    # Parse max-iterations flag
    $maxIterations = 0
    for ($i = 0; $i -lt $Args.Count; $i++) {
        if ($Args[$i] -eq "--max-iterations") {
            $maxIterations = [int]$Args[++$i]
        }
    }

    # Start loop process
    $loopArgs = @(
        "-NoProfile",
        "-File", "$RepoRoot\.felix\felix-loop.ps1",
        $RepoRoot
    )
    if ($maxIterations -gt 0) {
        $loopArgs += @("-MaxIterations", $maxIterations)
    }

    # Pipe to CLI (similar to run)
    # ... implementation similar to Invoke-Run ...
}

function Invoke-Status {
    param([string[]]$Args)

    $requirementId = if ($Args.Count -gt 0) { $Args[0] } else { $null }

    # Load requirements.json
    $requirementsPath = "$RepoRoot\.felix\requirements.json"
    if (-not (Test-Path $requirementsPath)) {
        Write-Error "Requirements file not found: $requirementsPath"
        exit 1
    }

    $requirements = Get-Content $requirementsPath | ConvertFrom-Json

    if ($requirementId) {
        # Show specific requirement
        $req = $requirements.requirements | Where-Object { $_.id -eq $requirementId }
        if (-not $req) {
            Write-Error "Requirement not found: $requirementId"
            exit 1
        }

        if ($Format -eq "json") {
            $req | ConvertTo-Json
        } else {
            Write-Host "Requirement: $($req.id)" -ForegroundColor Cyan
            Write-Host "Title: $($req.title)"
            Write-Host "Status: $($req.status)"
            Write-Host "Priority: $($req.priority)"
            Write-Host "Dependencies: $($req.dependencies -join ', ')"
        }
    } else {
        # Show all requirements
        if ($Format -eq "json") {
            $requirements.requirements | ConvertTo-Json
        } else {
            foreach ($req in $requirements.requirements) {
                $color = switch ($req.status) {
                    "done" { "Green" }
                    "in-progress" { "Yellow" }
                    "planned" { "Cyan" }
                    "blocked" { "Red" }
                    default { "White" }
                }
                Write-Host "$($req.id): $($req.title) [$($req.status)]" -ForegroundColor $color
            }
        }
    }
}

function Invoke-List {
    param([string[]]$Args)

    # Parse status filter
    $statusFilter = $null
    for ($i = 0; $i -lt $Args.Count; $i++) {
        if ($Args[$i] -eq "--status") {
            $statusFilter = $Args[++$i]
        }
    }

    # Load requirements.json
    $requirementsPath = "$RepoRoot\.felix\requirements.json"
    $requirements = Get-Content $requirementsPath | ConvertFrom-Json

    # Filter by status
    $filtered = if ($statusFilter) {
        $requirements.requirements | Where-Object { $_.status -eq $statusFilter }
    } else {
        $requirements.requirements
    }

    if ($Format -eq "json") {
        $filtered | ConvertTo-Json
    } else {
        Write-Host "`nRequirements:" -ForegroundColor Cyan
        foreach ($req in $filtered) {
            Write-Host "  $($req.id): $($req.title) [$($req.status)]"
        }
        Write-Host ""
    }
}

function Invoke-Validate {
    param([string[]]$Args)

    if ($Args.Count -eq 0) {
        Write-Error "Usage: felix validate <requirement-id>"
        exit 1
    }

    $requirementId = $Args[0]

    # Call validate-requirement.py
    $pythonExe = "python"
    $validateScript = "$RepoRoot\scripts\validate-requirement.py"

    & $pythonExe $validateScript $requirementId
    exit $LASTEXITCODE
}

function Show-Version {
    Write-Host "Felix CLI v0.2.0"
    Write-Host "PowerShell dispatcher"
}

function Show-Help {
    param([string]$CommandName)

    if ($CommandName) {
        switch ($CommandName) {
            "run" {
                Write-Host "Usage: felix run <requirement-id> [options]"
                Write-Host ""
                Write-Host "Run a single requirement to completion."
                Write-Host ""
                Write-Host "Options:"
                Write-Host "  --format <json|plain|rich>  Output format (default: rich)"
                Write-Host "  --verbose                   Enable verbose logging"
                Write-Host "  --quiet                     Suppress non-essential output"
            }
            "loop" {
                Write-Host "Usage: felix loop [options]"
                Write-Host ""
                Write-Host "Run agent in continuous loop mode."
                Write-Host ""
                Write-Host "Options:"
                Write-Host "  --max-iterations <n>        Maximum iterations (default: unlimited)"
                Write-Host "  --format <json|plain|rich>  Output format (default: rich)"
            }
            # ... other commands ...
        }
    } else {
        Write-Host "Felix CLI - Development workflow automation"
        Write-Host ""
        Write-Host "Usage: felix <command> [options]"
        Write-Host ""
        Write-Host "Commands:"
        Write-Host "  run <req-id>     Run a single requirement"
        Write-Host "  loop             Run agent in continuous loop"
        Write-Host "  status [req-id]  Show requirement status"
        Write-Host "  list             List requirements"
        Write-Host "  validate <id>    Validate requirement"
        Write-Host "  version          Show version"
        Write-Host "  help [command]   Show help"
        Write-Host ""
        Write-Host "Global Options:"
        Write-Host "  --format <json|plain|rich>  Output format"
        Write-Host "  --verbose                   Enable verbose logging"
        Write-Host "  --quiet                     Suppress non-essential output"
    }
}

# Route command
switch ($Command) {
    "run"      { Invoke-Run $remainingArgs }
    "loop"     { Invoke-Loop $remainingArgs }
    "status"   { Invoke-Status $remainingArgs }
    "list"     { Invoke-List $remainingArgs }
    "validate" { Invoke-Validate $remainingArgs }
    "version"  { Show-Version }
    "help"     { Show-Help $remainingArgs[0] }
}
```

### 1.3: Create Installation Script

**Purpose:** Add felix.ps1 to PATH and create convenient aliases

**Location:** `scripts/install-felix-cli.ps1`

**Implementation:**

```powershell
<#
.SYNOPSIS
Install Felix CLI to system PATH

.DESCRIPTION
Adds the Felix repository root to user PATH so 'felix' command is available globally.
#>

param(
    [Parameter(Mandatory=$false)]
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot

function Add-ToPath {
    param([string]$Path)

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")

    if ($userPath -notlike "*$Path*") {
        $newPath = "$userPath;$Path"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "✅ Added to PATH: $Path" -ForegroundColor Green
        Write-Host "⚠️  Restart your terminal for changes to take effect" -ForegroundColor Yellow
    } else {
        Write-Host "✅ Already in PATH: $Path" -ForegroundColor Green
    }
}

function Remove-FromPath {
    param([string]$Path)

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")

    if ($userPath -like "*$Path*") {
        $newPath = $userPath -replace [regex]::Escape(";$Path"), ""
        $newPath = $newPath -replace [regex]::Escape("$Path;"), ""
        $newPath = $newPath -replace [regex]::Escape($Path), ""
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "✅ Removed from PATH: $Path" -ForegroundColor Green
    } else {
        Write-Host "ℹ️  Not in PATH: $Path"
    }
}

if ($Uninstall) {
    Write-Host "Uninstalling Felix CLI..." -ForegroundColor Cyan
    Remove-FromPath $RepoRoot
    Write-Host "✅ Felix CLI uninstalled" -ForegroundColor Green
} else {
    Write-Host "Installing Felix CLI..." -ForegroundColor Cyan
    Add-ToPath $RepoRoot
    Write-Host "✅ Felix CLI installed" -ForegroundColor Green
    Write-Host ""
    Write-Host "Try: felix help" -ForegroundColor Cyan
}
```

**Usage:**

```powershell
# Install
.\scripts\install-felix-cli.ps1

# Uninstall
.\scripts\install-felix-cli.ps1 -Uninstall
```

## Phase 2: C# CLI Development

**Goal:** Build cross-platform felix.exe with rich TUI

**Timeline:** 2-4 weeks

**Status:** 📅 Planned

### 2.1: Project Structure

```
felix-cli/
├── Felix.CLI.csproj
├── Program.cs                 # Entry point, command routing
├── Commands/
│   ├── RunCommand.cs          # felix run
│   ├── LoopCommand.cs         # felix loop
│   ├── StatusCommand.cs       # felix status
│   ├── ListCommand.cs         # felix list
│   ├── ValidateCommand.cs     # felix validate
│   └── BaseCommand.cs         # Shared command logic
├── Core/
│   ├── AgentProcess.cs        # Process management
│   ├── EventParser.cs         # NDJSON parsing
│   ├── OutputSelector.cs      # Format selection logic
│   └── Models/
│       ├── Event.cs           # Event models
│       ├── Requirement.cs     # Requirement models
│       └── Configuration.cs   # Config models
├── Renderers/
│   ├── IRenderer.cs           # Renderer interface
│   ├── JsonRenderer.cs        # JSON passthrough
│   ├── PlainRenderer.cs       # Plain text
│   └── TuiRenderer.cs         # Spectre.Console TUI
└── Tests/
    ├── CommandTests.cs
    ├── ParserTests.cs
    └── RendererTests.cs
```

### 2.2: Project Setup

**Felix.CLI.csproj:**

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <AssemblyName>felix</AssemblyName>
    <RootNamespace>Felix.CLI</RootNamespace>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>

    <!-- Self-contained publish -->
    <PublishSingleFile>true</PublishSingleFile>
    <SelfContained>true</SelfContained>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
    <IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Spectre.Console" Version="0.48.0" />
    <PackageReference Include="Spectre.Console.Cli" Version="0.48.0" />
    <PackageReference Include="System.Text.Json" Version="8.0.0" />
  </ItemGroup>
</Project>
```

### 2.3: Core Implementation

**Program.cs:**

```csharp
using Spectre.Console.Cli;
using Felix.CLI.Commands;

namespace Felix.CLI;

class Program
{
    static int Main(string[] args)
    {
        var app = new CommandApp();

        app.Configure(config =>
        {
            config.SetApplicationName("felix");

            config.AddCommand<RunCommand>("run")
                .WithDescription("Run a single requirement to completion")
                .WithExample(new[] { "run", "S-0001" })
                .WithExample(new[] { "run", "S-0001", "--format", "json" });

            config.AddCommand<LoopCommand>("loop")
                .WithDescription("Run agent in continuous loop mode")
                .WithExample(new[] { "loop" })
                .WithExample(new[] { "loop", "--max-iterations", "10" });

            config.AddCommand<StatusCommand>("status")
                .WithDescription("Show requirement status")
                .WithExample(new[] { "status" })
                .WithExample(new[] { "status", "S-0001" });

            config.AddCommand<ListCommand>("list")
                .WithDescription("List requirements")
                .WithExample(new[] { "list" })
                .WithExample(new[] { "list", "--status", "planned" });

            config.AddCommand<ValidateCommand>("validate")
                .WithDescription("Run validation checks")
                .WithExample(new[] { "validate", "S-0001" });
        });

        return app.Run(args);
    }
}
```

**Commands/BaseCommand.cs:**

```csharp
using Spectre.Console;
using Spectre.Console.Cli;
using System.ComponentModel;

namespace Felix.CLI.Commands;

public abstract class BaseCommand<TSettings> : Command<TSettings>
    where TSettings : CommandSettings
{
    protected string GetRepositoryPath()
    {
        // Try to find .felix directory walking up from current directory
        var current = Directory.GetCurrentDirectory();
        while (current != null)
        {
            if (Directory.Exists(Path.Combine(current, ".felix")))
                return current;

            current = Directory.GetParent(current)?.FullName;
        }

        throw new InvalidOperationException(
            "Could not find Felix repository. Run from within a Felix-managed directory.");
    }

    protected string GetFelixDirectory() =>
        Path.Combine(GetRepositoryPath(), ".felix");
}

public class GlobalSettings : CommandSettings
{
    [Description("Output format (tui, json, plain)")]
    [CommandOption("--format")]
    public string Format { get; set; } = "tui";

    [Description("Enable verbose logging")]
    [CommandOption("--verbose")]
    public bool Verbose { get; set; }

    [Description("Suppress non-essential output")]
    [CommandOption("--quiet")]
    public bool Quiet { get; set; }

    [Description("Repository path (auto-detected if not specified)")]
    [CommandOption("--repo")]
    public string? RepositoryPath { get; set; }
}
```

**Commands/RunCommand.cs:**

```csharp
using Spectre.Console;
using Spectre.Console.Cli;
using System.ComponentModel;
using Felix.CLI.Core;
using Felix.CLI.Renderers;

namespace Felix.CLI.Commands;

public class RunSettings : GlobalSettings
{
    [Description("Requirement ID to run")]
    [CommandArgument(0, "<requirement-id>")]
    public string RequirementId { get; set; } = string.Empty;
}

public class RunCommand : BaseCommand<RunSettings>
{
    public override int Execute(CommandContext context, RunSettings settings)
    {
        var repoPath = settings.RepositoryPath ?? GetRepositoryPath();
        var felixDir = Path.Combine(repoPath, ".felix");

        // Select renderer based on format
        var renderer = OutputSelector.GetRenderer(settings.Format);

        // Create agent process
        var agentPath = Path.Combine(felixDir, "felix-agent.ps1");
        var agent = new AgentProcess(agentPath, repoPath, settings.RequirementId);

        // Start agent and process events
        try
        {
            agent.Start();

            foreach (var eventData in agent.ReadEvents())
            {
                renderer.Render(eventData);
            }

            agent.WaitForExit();
            return agent.ExitCode;
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]Error:[/] {ex.Message}");
            return 1;
        }
    }
}
```

**Core/AgentProcess.cs:**

```csharp
using System.Diagnostics;
using System.Text.Json;

namespace Felix.CLI.Core;

public class AgentProcess : IDisposable
{
    private readonly string _agentPath;
    private readonly string _repoPath;
    private readonly string? _requirementId;
    private readonly int? _maxIterations;
    private Process? _process;

    public int ExitCode => _process?.ExitCode ?? -1;

    public AgentProcess(string agentPath, string repoPath,
        string? requirementId = null, int? maxIterations = null)
    {
        _agentPath = agentPath;
        _repoPath = repoPath;
        _requirementId = requirementId;
        _maxIterations = maxIterations;
    }

    public void Start()
    {
        var args = new List<string>
        {
            "-NoProfile",
            "-File", _agentPath,
            _repoPath
        };

        if (_requirementId != null)
        {
            args.Add("-RequirementId");
            args.Add(_requirementId);
        }

        if (_maxIterations != null)
        {
            args.Add("-MaxIterations");
            args.Add(_maxIterations.Value.ToString());
        }

        _process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = string.Join(" ", args),
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            }
        };

        _process.Start();
    }

    public IEnumerable<Event> ReadEvents()
    {
        if (_process == null)
            throw new InvalidOperationException("Process not started");

        var parser = new EventParser();

        while (!_process.StandardOutput.EndOfStream)
        {
            var line = _process.StandardOutput.ReadLine();
            if (line == null) continue;

            var eventData = parser.Parse(line);
            if (eventData != null)
                yield return eventData;
        }
    }

    public void WaitForExit() => _process?.WaitForExit();

    public void Dispose()
    {
        _process?.Dispose();
    }
}
```

**Core/EventParser.cs:**

```csharp
using System.Text.Json;
using Felix.CLI.Core.Models;

namespace Felix.CLI.Core;

public class EventParser
{
    private readonly JsonSerializerOptions _options;

    public EventParser()
    {
        _options = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            AllowTrailingCommas = true
        };
    }

    public Event? Parse(string line)
    {
        try
        {
            return JsonSerializer.Deserialize<Event>(line, _options);
        }
        catch (JsonException)
        {
            // Invalid JSON, skip
            return null;
        }
    }
}
```

**Core/Models/Event.cs:**

```csharp
using System.Text.Json.Serialization;

namespace Felix.CLI.Core.Models;

public class Event
{
    [JsonPropertyName("event")]
    public string EventType { get; set; } = string.Empty;

    [JsonPropertyName("timestamp")]
    public DateTime Timestamp { get; set; }

    [JsonPropertyName("requirement_id")]
    public string? RequirementId { get; set; }

    [JsonPropertyName("iteration")]
    public int? Iteration { get; set; }

    [JsonPropertyName("message")]
    public string? Message { get; set; }

    [JsonPropertyName("level")]
    public string? Level { get; set; }

    [JsonPropertyName("component")]
    public string? Component { get; set; }

    [JsonPropertyName("details")]
    public string? Details { get; set; }

    [JsonPropertyName("task")]
    public string? Task { get; set; }

    [JsonPropertyName("status")]
    public string? Status { get; set; }

    [JsonPropertyName("criterion")]
    public string? Criterion { get; set; }

    [JsonPropertyName("command")]
    public string? Command { get; set; }

    [JsonPropertyName("exit_code")]
    public int? ExitCode { get; set; }

    [JsonPropertyName("file_path")]
    public string? FilePath { get; set; }

    // Add other event-specific properties as needed
}
```

**Core/OutputSelector.cs:**

```csharp
using Felix.CLI.Renderers;

namespace Felix.CLI.Core;

public static class OutputSelector
{
    public static IRenderer GetRenderer(string format)
    {
        // Check if terminal supports rich rendering
        var supportsRich = !Console.IsOutputRedirected &&
                          !Console.IsErrorRedirected &&
                          Environment.GetEnvironmentVariable("TERM") != "dumb";

        return format.ToLowerInvariant() switch
        {
            "json" => new JsonRenderer(),
            "plain" => new PlainRenderer(),
            "tui" when supportsRich => new TuiRenderer(),
            "tui" => new PlainRenderer(), // Fallback
            _ => supportsRich ? new TuiRenderer() : new PlainRenderer()
        };
    }
}
```

**Renderers/IRenderer.cs:**

```csharp
using Felix.CLI.Core.Models;

namespace Felix.CLI.Renderers;

public interface IRenderer
{
    void Render(Event eventData);
    void Flush(); // Called at end of stream
}
```

**Renderers/JsonRenderer.cs:**

```csharp
using System.Text.Json;
using Felix.CLI.Core.Models;

namespace Felix.CLI.Renderers;

public class JsonRenderer : IRenderer
{
    private readonly JsonSerializerOptions _options = new()
    {
        WriteIndented = false
    };

    public void Render(Event eventData)
    {
        var json = JsonSerializer.Serialize(eventData, _options);
        Console.WriteLine(json);
    }

    public void Flush()
    {
        // No buffering, nothing to flush
    }
}
```

**Renderers/PlainRenderer.cs:**

```csharp
using Spectre.Console;
using Felix.CLI.Core.Models;

namespace Felix.CLI.Renderers;

public class PlainRenderer : IRenderer
{
    public void Render(Event eventData)
    {
        var timestamp = eventData.Timestamp.ToString("yyyy-MM-dd HH:mm:ss");
        var level = eventData.Level ?? eventData.EventType;
        var message = eventData.Message ?? eventData.EventType;

        var color = GetColor(eventData);
        AnsiConsole.MarkupLine($"[{color}][{timestamp}] {level.ToUpper().PadRight(8)} {message}[/]");
    }

    public void Flush()
    {
        // No buffering
    }

    private string GetColor(Event eventData) =>
        (eventData.Level ?? eventData.EventType) switch
        {
            "error" => "red",
            "warn" => "yellow",
            "info" => "cyan",
            "debug" => "grey",
            "error_occurred" => "red",
            "validation_failed" => "red",
            "validation_passed" => "green",
            "task_completed" => eventData.Status == "success" ? "green" : "red",
            _ => "white"
        };
}
```

**Renderers/TuiRenderer.cs:**

```csharp
using Spectre.Console;
using Felix.CLI.Core.Models;

namespace Felix.CLI.Renderers;

public class TuiRenderer : IRenderer
{
    private readonly Layout _layout;
    private readonly Table _logTable;
    private readonly Table _tasksTable;
    private readonly Panel _statusPanel;
    private string _currentStatus = "Starting...";
    private DateTime _startTime = DateTime.Now;
    private int _currentIteration = 0;

    public TuiRenderer()
    {
        // Create layout
        _layout = new Layout("Root")
            .SplitRows(
                new Layout("Header").Size(3),
                new Layout("Body").SplitColumns(
                    new Layout("Tasks").Size(40),
                    new Layout("Logs")
                ),
                new Layout("Footer").Size(5)
            );

        _statusPanel = new Panel($"[cyan]Status:[/] {_currentStatus}")
            .Border(BoxBorder.Rounded)
            .BorderColor(Color.Cyan);

        _tasksTable = new Table()
            .AddColumn("Task")
            .AddColumn("Status")
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Blue);

        _logTable = new Table()
            .AddColumn("Time")
            .AddColumn("Level")
            .AddColumn("Message")
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey);

        _layout["Header"].Update(_statusPanel);
        _layout["Tasks"].Update(_tasksTable);
        _layout["Logs"].Update(_logTable);

        AnsiConsole.Clear();
        AnsiConsole.Live(_layout).Start(ctx =>
        {
            ctx.Refresh();
        });
    }

    public void Render(Event eventData)
    {
        switch (eventData.EventType)
        {
            case "run_started":
                _currentStatus = $"Running {eventData.RequirementId}";
                _startTime = eventData.Timestamp;
                UpdateHeader();
                break;

            case "iteration_started":
                _currentIteration = eventData.Iteration ?? 0;
                UpdateHeader();
                break;

            case "task_started":
                AddTask(eventData.Task ?? "", "🔄 Running");
                break;

            case "task_completed":
                UpdateTask(eventData.Task ?? "",
                    eventData.Status == "success" ? "✅ Complete" : "❌ Failed");
                break;

            case "log":
                AddLog(eventData);
                break;

            case "validation_passed":
                AddLog(eventData, "✅", "green");
                break;

            case "validation_failed":
                AddLog(eventData, "❌", "red");
                break;
        }
    }

    public void Flush()
    {
        // Final update
    }

    private void UpdateHeader()
    {
        var elapsed = DateTime.Now - _startTime;
        var header = new Panel(
            $"[cyan]Status:[/] {_currentStatus} | " +
            $"[yellow]Time:[/] {elapsed:mm\\:ss} | " +
            $"[blue]Iteration:[/] {_currentIteration}")
            .Border(BoxBorder.Rounded)
            .BorderColor(Color.Cyan);

        _layout["Header"].Update(header);
    }

    private void AddTask(string task, string status)
    {
        _tasksTable.AddRow(task, status);
        _layout["Tasks"].Update(_tasksTable);
    }

    private void UpdateTask(string task, string newStatus)
    {
        // TODO: Update existing row (Spectre.Console limitation: can't easily update rows)
        // For now, just add to logs
        AddLog(new Event
        {
            Message = $"Task {task}: {newStatus}",
            Level = "info"
        });
    }

    private void AddLog(Event eventData, string icon = "", string color = "white")
    {
        var time = eventData.Timestamp.ToString("HH:mm:ss");
        var level = eventData.Level ?? "info";
        var message = eventData.Message ?? "";

        if (string.IsNullOrEmpty(icon))
        {
            icon = level switch
            {
                "error" => "❌",
                "warn" => "⚠️",
                "info" => "ℹ️",
                _ => "•"
            };
        }

        _logTable.AddRow(time, $"[{color}]{icon}[/]", message);

        // Keep only last 20 logs
        while (_logTable.Rows.Count > 20)
        {
            _logTable.Rows.RemoveAt(0);
        }

        _layout["Logs"].Update(_logTable);
    }
}
```

### 2.4: Build and Distribution

**Build Script (build-felix.ps1):**

```powershell
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("win-x64", "linux-x64", "osx-x64", "osx-arm64")]
    [string]$Runtime = "win-x64"
)

$projectPath = "felix-cli/Felix.CLI.csproj"
$outputPath = "dist/$Runtime"

Write-Host "Building Felix CLI for $Runtime..." -ForegroundColor Cyan

dotnet publish $projectPath `
    -c Release `
    -r $Runtime `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -o $outputPath

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Build successful: $outputPath/felix" -ForegroundColor Green
} else {
    Write-Host "❌ Build failed" -ForegroundColor Red
    exit 1
}
```

**Usage:**

```powershell
# Build for Windows
.\build-felix.ps1 -Runtime win-x64

# Build for Linux
.\build-felix.ps1 -Runtime linux-x64

# Build for macOS (Intel)
.\build-felix.ps1 -Runtime osx-x64

# Build for macOS (ARM)
.\build-felix.ps1 -Runtime osx-arm64
```

## Phase 3: Integration Updates

### 3.1: Tray Application

**Before:**

```csharp
var psi = new ProcessStartInfo {
    FileName = "powershell.exe",
    Arguments = $"-NoProfile -File \"{felixLoopPath}\" \"{repoPath}\"",
    RedirectStandardOutput = true,
    UseShellExecute = false,
    CreateNoWindow = true
};
```

**After:**

```csharp
var psi = new ProcessStartInfo {
    FileName = "felix",  // Assumes felix.exe in PATH
    Arguments = $"loop --format json",
    RedirectStandardOutput = true,
    UseShellExecute = false,
    CreateNoWindow = true
};
```

### 3.2: Backend API

**Before:**

```python
process = subprocess.Popen(
    ["powershell", "-File", agent_path, repo_path, "-RequirementId", req_id],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
)
```

**After:**

```python
process = subprocess.Popen(
    ["felix", "run", req_id, "--format", "json"],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    cwd=repo_path
)
```

### 3.3: CI/CD Workflows

**Before (.github/workflows/requirements.yml):**

```yaml
- name: Run requirement
  shell: powershell
  run: |
    .\.felix\felix-agent.ps1 ${{ github.workspace }} -RequirementId S-0001
```

**After:**

```yaml
- name: Setup Felix
  run: |
    # Download felix executable for runner OS
    curl -L https://github.com/user/felix/releases/download/v0.3.0/felix-${{ runner.os }}.tar.gz | tar xz
    chmod +x felix
    mv felix /usr/local/bin/

- name: Run requirement
  run: felix run S-0001 --format json
```

## Testing Strategy

### Unit Tests

```csharp
[TestClass]
public class EventParserTests
{
    [TestMethod]
    public void Parse_ValidEvent_ReturnsEvent()
    {
        var json = @"{""event"":""run_started"",""requirement_id"":""S-0001"",""timestamp"":""2026-02-05T10:00:00Z""}";
        var parser = new EventParser();

        var result = parser.Parse(json);

        Assert.IsNotNull(result);
        Assert.AreEqual("run_started", result.EventType);
        Assert.AreEqual("S-0001", result.RequirementId);
    }

    [TestMethod]
    public void Parse_InvalidJson_ReturnsNull()
    {
        var invalid = "not json";
        var parser = new EventParser();

        var result = parser.Parse(invalid);

        Assert.IsNull(result);
    }
}
```

### Integration Tests

```csharp
[TestClass]
public class RunCommandTests
{
    [TestMethod]
    public void Execute_ValidRequirement_ReturnsZero()
    {
        var settings = new RunSettings
        {
            RequirementId = "S-0000",  // Test requirement
            Format = "json",
            RepositoryPath = TestHelper.GetTestRepoPath()
        };

        var command = new RunCommand();
        var result = command.Execute(new CommandContext(), settings);

        Assert.AreEqual(0, result);
    }
}
```

### End-to-End Tests

```powershell
# Test script: test-felix-cli.ps1

# Test run command
$output = felix run S-0000 --format json | ConvertFrom-Json
if ($output.event -ne "run_started") {
    Write-Error "Run command failed"
    exit 1
}

# Test status command
$status = felix status S-0000 --format json | ConvertFrom-Json
if (-not $status.id) {
    Write-Error "Status command failed"
    exit 1
}

# Test list command
$list = felix list --format json | ConvertFrom-Json
if ($list.Count -eq 0) {
    Write-Error "List command failed"
    exit 1
}

Write-Host "✅ All tests passed" -ForegroundColor Green
```

## Migration Checklist

### Phase 1 Checklist

- [ ] Copy test-cli.ps1 to felix-cli.ps1
- [ ] Add format parameter (json, plain, rich)
- [ ] Implement JSON renderer (passthrough)
- [ ] Implement Plain renderer (colored text)
- [ ] Implement Rich renderer (enhanced visuals)
- [ ] Add event filtering (by type, by level)
- [ ] Add statistics tracking
- [ ] Create felix.ps1 dispatcher
- [ ] Implement run command routing
- [ ] Implement loop command routing
- [ ] Implement status command
- [ ] Implement list command
- [ ] Implement validate command
- [ ] Add help command
- [ ] Add version command
- [ ] Create installation script
- [ ] Test all commands
- [ ] Update documentation

### Phase 2 Checklist

- [ ] Create felix-cli/ project
- [ ] Add Spectre.Console packages
- [ ] Implement Program.cs entry point
- [ ] Implement BaseCommand
- [ ] Implement RunCommand
- [ ] Implement LoopCommand
- [ ] Implement StatusCommand
- [ ] Implement ListCommand
- [ ] Implement ValidateCommand
- [ ] Implement AgentProcess
- [ ] Implement EventParser
- [ ] Implement Event models
- [ ] Implement OutputSelector
- [ ] Implement JsonRenderer
- [ ] Implement PlainRenderer
- [ ] Implement TuiRenderer
- [ ] Add unit tests
- [ ] Add integration tests
- [ ] Build for Windows
- [ ] Build for Linux
- [ ] Build for macOS
- [ ] Create distribution packages
- [ ] Test cross-platform

### Phase 3 Checklist

- [ ] Update tray app to use felix.exe
- [ ] Update backend to use felix.exe
- [ ] Update CI/CD workflows
- [ ] Test tray integration
- [ ] Test backend integration
- [ ] Test CI/CD integration
- [ ] Update user documentation
- [ ] Create migration guide
- [ ] Release v0.3

## Rollback Strategy

If issues are encountered:

1. **Phase 1:** PowerShell scripts remain unchanged, can continue using felix-agent.ps1 directly
2. **Phase 2:** felix.exe is additive, doesn't replace anything initially
3. **Phase 3:** Keep PowerShell fallback code paths during transition

**Rollback Steps:**

1. Remove felix.exe from PATH
2. Revert tray app process spawning
3. Revert backend process spawning
4. Revert CI/CD workflow changes
5. Continue using PowerShell scripts

## Success Criteria

### Phase 1 Success

- ✅ felix.ps1 dispatcher routes commands correctly
- ✅ felix-cli.ps1 renders in all three formats
- ✅ Statistics and filtering work
- ✅ Installation script adds to PATH
- ✅ All commands (run, loop, status, list, validate) functional

### Phase 2 Success

- ✅ felix.exe builds for Windows, Linux, macOS
- ✅ All commands work identically to PowerShell version
- ✅ TUI renders correctly in interactive terminals
- ✅ JSON mode provides NDJSON passthrough
- ✅ Plain mode works in non-interactive environments
- ✅ Unit tests pass
- ✅ Integration tests pass
- ✅ Self-contained executable (no .NET install required)

### Phase 3 Success

- ✅ Tray app uses felix.exe without issues
- ✅ Backend uses felix.exe without issues
- ✅ CI/CD uses felix.exe without issues
- ✅ All integration tests pass
- ✅ Documentation updated
- ✅ v0.3 released

## Conclusion

This migration strategy provides:

1. **Incremental Path:** Two phases, each independently valuable
2. **Low Risk:** PowerShell scripts remain as fallback
3. **High Value:** Professional CLI with rich UX
4. **Cross-Platform:** Works on Windows, macOS, Linux
5. **Clean Architecture:** Renderer separation, process isolation
6. **Future-Proof:** Extensible command structure

The end result is a professional, modern CLI tool that integrates seamlessly with all Felix components while providing an excellent user experience.

---

**Next Steps:**

1. Begin Phase 1 implementation
2. Test PowerShell CLI enhancements
3. Gather feedback before starting Phase 2
4. Plan C# CLI development sprint

**Related Documents:**

- [CLI.md](./CLI.md) - Architectural overview and design decisions
- [RELEASE_NOTES_v0.2.md](../RELEASE_NOTES_v0.2.md) - NDJSON event system
- [NDJSON_MIGRATION_COMPLETE.md](./NDJSON_MIGRATION_COMPLETE.md) - Event format specifications
- [AGENTS.md](../AGENTS.md) - How to run Felix
