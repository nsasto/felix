
function Show-Help {
    param([string]$SubCommand)

    if ($SubCommand) {
        switch ($SubCommand) {
            "run" {
                Write-Host ""
                Write-Host "felix run <requirement-id> [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Execute a single requirement to completion."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --format <json|plain|rich>   Output format (default: rich)"
                Write-Host "  --no-stats                   Suppress statistics summary"
                Write-Host "  --sync                       Temporarily enable sync (overrides config)"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix run S-0001"
                Write-Host "  felix run S-0001 --format json"
                Write-Host "  felix run S-0001 --sync"
                Write-Host "  felix run S-0001 --format plain --no-stats"
                Write-Host ""
            }
            "run-next" {
                Write-Host ""
                Write-Host "felix run-next [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Claim and run the next available requirement (one only)."
                Write-Host ""
                Write-Host "  Remote mode (sync enabled): claims from server via GET /api/sync/work/next"
                Write-Host "  Local mode:                 picks next in_progress then planned from requirements.json"
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --format <json|plain|rich>   Output format (default: rich)"
                Write-Host "  --sync                       Temporarily enable sync (overrides config)"
                Write-Host ""
                Write-Host "Exit codes:"
                Write-Host "  0   Requirement completed successfully"
                Write-Host "  5   No work available"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix run-next"
                Write-Host "  felix run-next --sync"
                Write-Host "  felix run-next --format json"
                Write-Host ""
            }
            "loop" {
                Write-Host ""
                Write-Host "felix loop [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Run agent in continuous loop mode (processes all planned requirements)."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --max-iterations <n>   Maximum iterations to run"
                Write-Host "  --sync                 Temporarily enable sync (overrides config)"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix loop"
                Write-Host "  felix loop --max-iterations 10"
                Write-Host "  felix loop --sync"
                Write-Host ""
            }
            "status" {
                Write-Host ""
                Write-Host "felix status [requirement-id] [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Show current status of requirements."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --format <json|plain|rich>   Output format (default: rich)"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix status"
                Write-Host "  felix status S-0001"
                Write-Host "  felix status --format json"
                Write-Host ""
            }
            "list" {
                Write-Host ""
                Write-Host "felix list [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "List requirements with optional filtering."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --status <status>            Filter by status (planned, in-progress, done, blocked)"
                Write-Host "  --format <json|plain|rich>   Output format (default: rich)"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix list"
                Write-Host "  felix list --status planned"
                Write-Host "  felix list --status done --format json"
                Write-Host ""
            }
            "validate" {
                Write-Host ""
                Write-Host "felix validate <requirement-id> [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Run validation checks for a requirement."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --json               Emit machine-readable validation result"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix validate S-0001"
                Write-Host "  felix validate S-0001 --json"
                Write-Host ""
            }
            "deps" {
                Write-Host ""
                Write-Host "felix deps [requirement-id] [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Show dependency information and validation status."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --check              Check if dependencies are satisfied"
                Write-Host "  --tree               Show dependency tree"
                Write-Host "  --incomplete         Show incomplete dependencies only"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix deps S-0001"
                Write-Host "  felix deps S-0001 --check"
                Write-Host "  felix deps --incomplete"
                Write-Host "  felix deps --tree"
                Write-Host ""
            }
            "spec" {
                Write-Host ""
                Write-Host "felix spec <subcommand> [arguments]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Manage requirement specifications."
                Write-Host ""
                Write-Host "Subcommands:" -ForegroundColor Yellow
                Write-Host "  create <description>       Create a new requirement spec"
                Write-Host "  fix [--fix-duplicates]     Reconcile specs/ folder with requirements.json"
                Write-Host "  delete <req-id>            Delete a requirement spec"
                Write-Host "  status <req-id> <status>   Update a requirement status"
                Write-Host "  pull [options]             Download changed specs from server"
                Write-Host "  push [options]             Upload local spec files to server"
                Write-Host ""
                Write-Host "Options for 'pull':" -ForegroundColor Yellow
                Write-Host "  --dry-run             Show what would be pulled without writing"
                Write-Host "  --delete              Also delete local specs removed from server"
                Write-Host "  --force               Overwrite local files not in manifest"
                Write-Host ""
                Write-Host "Options for 'push':" -ForegroundColor Yellow
                Write-Host "  --dry-run             Show what would be uploaded without sending"
                Write-Host "  --force               Re-upload and request create-if-missing requirement mappings"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix spec create ""Add user authentication"""
                Write-Host "  felix spec fix"
                Write-Host "  felix spec fix --fix-duplicates"
                Write-Host "  felix spec delete S-0001"
                Write-Host "  felix spec status S-0001 planned"
                Write-Host "  felix spec pull"
                Write-Host "  felix spec pull --dry-run"
                Write-Host "  felix spec push"
                Write-Host ""
            }
            "context" {
                Write-Host ""
                Write-Host "felix context <subcommand> [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Generate, view, and sync project context documentation."
                Write-Host ""
                Write-Host "Subcommands:" -ForegroundColor Yellow
                Write-Host "  build [options]       Analyze project and generate CONTEXT.md"
                Write-Host "  show                  Display current CONTEXT.md content"
                Write-Host "  push [options]        Upload README.md, CONTEXT.md, AGENTS.md to server"
                Write-Host "  pull [options]        Download README.md, CONTEXT.md, AGENTS.md from server"
                Write-Host ""
                Write-Host "Options for 'build':" -ForegroundColor Yellow
                Write-Host "  --include-hidden      Include hidden files/folders in analysis"
                Write-Host "  --force               Skip overwrite confirmation"
                Write-Host ""
                Write-Host "Options for 'push':" -ForegroundColor Yellow
                Write-Host "  --dry-run             Show what would be pushed without uploading"
                Write-Host "  --force               Re-upload even unchanged files"
                Write-Host ""
                Write-Host "Options for 'pull':" -ForegroundColor Yellow
                Write-Host "  --dry-run             Show what would be pulled without writing files"
                Write-Host "  --force               Overwrite local files not in manifest"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix context build"
                Write-Host "  felix context build --include-hidden"
                Write-Host "  felix context build --force"
                Write-Host "  felix context show"
                Write-Host "  felix context push"
                Write-Host "  felix context push --dry-run"
                Write-Host "  felix context pull"
                Write-Host "  felix context pull --force"
                Write-Host ""
            }
            "update" {
                Write-Host ""
                Write-Host "felix update [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Check GitHub Releases and update the installed Felix CLI."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --check              Check for updates without installing"
                Write-Host "  --yes                Skip confirmation and install immediately"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix update"
                Write-Host "  felix update --check"
                Write-Host "  felix update --yes"
                Write-Host ""
            }
            "agent" {
                Write-Host ""
                Write-Host "felix agent <subcommand> [args]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Manage local CLI agents."
                Write-Host ""
                Write-Host "Subcommands:" -ForegroundColor Yellow
                Write-Host "  list                  List available agents"
                Write-Host "  current               Show current active agent"
                Write-Host "  use <id|name> [--model <model>]  Switch active agent"
                Write-Host "  test <id|name>        Test agent connectivity"
                Write-Host "  setup                 Configure agents for this project"
                Write-Host "  install-help [name]   Show install/login guidance for one or all agents"
                Write-Host "  register              Register current agent with the sync server"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix agent list"
                Write-Host "  felix agent current"
                Write-Host "  felix agent use codex"
                Write-Host "  felix agent use copilot --model gpt-5.4"
                Write-Host "  felix agent test claude"
                Write-Host "  felix agent setup"
                Write-Host "  felix agent install-help"
                Write-Host "  felix agent install-help copilot"
                Write-Host "  felix agent register"
                Write-Host ""
            }
            "tui" {
                Write-Host ""
                Write-Host "felix tui" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Launch interactive Terminal UI dashboard with:"
                Write-Host "  - Visual requirement status and progress tracking"
                Write-Host "  - Interactive command menu"
                Write-Host "  - Real-time status visualization"
                Write-Host ""
                Write-Host "Requirements:" -ForegroundColor Yellow
                Write-Host "  - .NET SDK (dotnet CLI)"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix tui"
                Write-Host ""
                Write-Host "Navigation:" -ForegroundColor Yellow
                Write-Host "  1-5     Quick actions"
                Write-Host "  /       Show all commands"
                Write-Host "  ?       Help screen"
                Write-Host "  q       Quit dashboard"
                Write-Host ""
            }
            "procs" {
                Write-Host ""
                Write-Host "felix procs [subcommand]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Manage active agent execution sessions."
                Write-Host ""
                Write-Host "Subcommands:" -ForegroundColor Yellow
                Write-Host "  list                   List all active sessions (default)"
                Write-Host "  kill <session-id>      Terminate a running session"
                Write-Host "  kill all               Terminate all running sessions"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix procs"
                Write-Host "  felix procs list"
                Write-Host "  felix procs kill S-0001-20260208-133511-it1"
                Write-Host "  felix procs kill all"
                Write-Host ""
                Write-Host "Session Info:" -ForegroundColor Yellow
                Write-Host "  - Session ID (run ID)"
                Write-Host "  - Requirement being executed"
                Write-Host "  - Agent name"
                Write-Host "  - Process ID (PID)"
                Write-Host "  - Running duration"
                Write-Host ""
            }
            default {
                Write-Host "Unknown command: $SubCommand" -ForegroundColor Red
                Show-Help
            }
        }
    }
    else {
        Write-Host ""
        Write-Host "Felix CLI - Development Workflow Automation" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Usage:" -ForegroundColor Yellow
        Write-Host "  felix <command> [arguments] [options]"
        Write-Host ""
        Write-Host "Commands:" -ForegroundColor Yellow
        Write-Host "  run <req-id>          Execute a single requirement"
        Write-Host "  run-next              Claim and run next available requirement (local or server)"
        Write-Host "  loop                  Run agent in continuous loop mode"
        Write-Host "  status [req-id]       Show requirement status"
        Write-Host "  list                  List all requirements with filters"
        Write-Host "  validate <req-id>     Run validation checks"
        Write-Host "  deps [req-id]         Show dependencies and validate status"
        Write-Host "  spec <subcommand>     Manage requirement specifications"
        Write-Host "  context <subcommand>  Generate/view project context documentation"
        Write-Host "  update                Update the installed Felix CLI from GitHub Releases"
        Write-Host "  agent <subcommand>    Manage and switch agents"
        Write-Host "  procs [subcommand]    Manage active execution sessions"
        Write-Host "  tui                   Launch interactive terminal UI"
        Write-Host "  dashboard             Interactive TUI dashboard"
        Write-Host "  setup                 Scaffold project, configure agents and sync"
        Write-Host "  version               Show version information"
        Write-Host "  help [command]        Show help for a command"
        Write-Host ""
        Write-Host "Global Options:" -ForegroundColor Yellow
        Write-Host "  --format <mode>       Output format: json, plain, rich (default: rich)"
        Write-Host "  --verbose             Enable verbose logging"
        Write-Host "  --quiet               Suppress non-essential output"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  felix run S-0001"
        Write-Host "  felix loop --max-iterations 5"
        Write-Host "  felix status S-0001 --format json"
        Write-Host "  felix list --status planned"
        Write-Host "  felix validate S-0001"
        Write-Host "  felix deps S-0001 --check"
        Write-Host "  felix spec create ""Add user authentication"""
        Write-Host "  felix context build"
        Write-Host "  felix update --check"
        Write-Host "  felix setup"
        Write-Host "  felix help run"
        Write-Host ""
    }
}
