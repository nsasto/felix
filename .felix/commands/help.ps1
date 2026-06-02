
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
                Write-Host "felix spec list [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "List requirements with optional filtering."
                Write-Host "The top-level 'felix list' alias is retained for compatibility."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --status <status>            Filter by status (planned, in-progress, done, blocked)"
                Write-Host "  --format <json|plain|rich>   Output format (default: rich)"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix spec list"
                Write-Host "  felix spec list --status planned"
                Write-Host "  felix spec list --status done --format json"
                Write-Host "  felix list --status planned"
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
                Write-Host "  list                    List requirements and specs"
                Write-Host "  create <description>       Create a new requirement spec"
                Write-Host "  fix [--fix-duplicates]     Reconcile specs/ folder with requirements.json"
                Write-Host "  delete <req-id> [--yes]    Delete a requirement spec"
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
                Write-Host "  felix spec list"
                Write-Host "  felix spec create ""Add user authentication"""
                Write-Host "  felix spec fix"
                Write-Host "  felix spec fix --fix-duplicates"
                Write-Host "  felix spec delete S-0001"
                Write-Host "  felix spec delete S-0001 --yes"
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
                Write-Host "  set-default <id|name> [--model <model>]  Set persistent default agent"
                Write-Host "  test <id|name>        Test agent connectivity"
                Write-Host "  setup                 Configure agents for this project"
                Write-Host "  install-help [name]   Show install/login guidance for one or all agents"
                Write-Host "  register              Register current agent with the sync server"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix agent list"
                Write-Host "  felix agent current"
                Write-Host "  felix agent use codex"
                Write-Host "  felix agent use copilot --model claude-haiku-4.5"
                Write-Host "  felix agent set-default claude"
                Write-Host "  felix agent test claude"
                Write-Host "  felix agent setup"
                Write-Host "  felix agent install-help"
                Write-Host "  felix agent install-help copilot"
                Write-Host "  felix agent register"
                Write-Host ""
                Write-Host "Notes:" -ForegroundColor Yellow
                Write-Host "  agent test verifies the executable and attempts a short version probe." -ForegroundColor Gray
                Write-Host "  use/set-default may update agents.json when --model changes the deterministic agent key." -ForegroundColor Gray
                Write-Host "  register can continue non-interactively with configured sync values." -ForegroundColor Gray
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
                Write-Host "Notes:" -ForegroundColor Yellow
                Write-Host "  procs kill force-terminates the tracked process tree and removes the session record." -ForegroundColor Gray
                Write-Host ""
            }
            "doctor" {
                Write-Host ""
                Write-Host "felix doctor [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Run health checks on the Felix project configuration."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --fix                Auto-repair non-destructive issues"
                Write-Host "  --explain <path>     Report which .felixignore rule matched a path"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix doctor"
                Write-Host "  felix doctor --fix"
                Write-Host "  felix doctor --explain src/main.js"
                Write-Host ""
            }
            "event" {
                Write-Host ""
                Write-Host "felix event <subcommand> [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Inspect the Felix event stream."
                Write-Host ""
                Write-Host "Subcommands:" -ForegroundColor Yellow
                Write-Host "  tail                         Stream recent events live"
                Write-Host "  query [--kind <type>] [--run-id <id>] [--since <duration>]  Filter events"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix event tail"
                Write-Host "  felix event query --kind backpressure.fail"
                Write-Host "  felix event query --run-id S-0001-20260601 --since 1h"
                Write-Host ""
            }
            "gc" {
                Write-Host ""
                Write-Host "felix gc [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Garbage-collect stale runs, rotated events, and orphaned worktrees."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --dry-run    Show what would be pruned without deleting"
                Write-Host "  --yes        Skip interactive confirmation"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix gc"
                Write-Host "  felix gc --dry-run"
                Write-Host "  felix gc --yes"
                Write-Host ""
            }
            "memory" {
                Write-Host ""
                Write-Host "felix memory <subcommand> [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Manage persistent agent memory stored in .felix/memory/."
                Write-Host ""
                Write-Host "Subcommands:" -ForegroundColor Yellow
                Write-Host "  view  [--scope global|repo|requirement] [--req <id>]   Display memories"
                Write-Host "  add   --scope <scope> --title <t> --body <b> [--req <id>]  Add a memory"
                Write-Host "  edit  <id>                                              Edit a memory entry"
                Write-Host "  prune [--older-than <days>] [--dry-run]                Remove stale memories"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix memory view"
                Write-Host "  felix memory view --scope repo"
                Write-Host "  felix memory add --scope global --title ""Always use UTF-8"" --body ""..."""
                Write-Host "  felix memory prune --older-than 30 --dry-run"
                Write-Host ""
            }
            "migrate" {
                Write-Host ""
                Write-Host "felix migrate [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Run schema migrations on requirements.json, config.json, and spec files."
                Write-Host "Preview mode by default; --apply is required to write changes."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --dry-run            Preview changes without writing (default)"
                Write-Host "  --apply              Write changes to disk"
                Write-Host "  --only <migration>   Run a single named migration"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix migrate"
                Write-Host "  felix migrate --apply"
                Write-Host "  felix migrate --apply --only spec-frontmatter"
                Write-Host ""
            }
            "plugin" {
                Write-Host ""
                Write-Host "felix plugin <subcommand> [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Manage Felix plugins."
                Write-Host ""
                Write-Host "Subcommands:" -ForegroundColor Yellow
                Write-Host "  list   [--remote] [--channel stable|beta] [--json]   List installed/available plugins"
                Write-Host "  install <name|url|path> [--channel stable|beta]      Install a plugin"
                Write-Host "  remove  <id>                                          Remove a plugin"
                Write-Host "  info    <id>                                          Show plugin details"
                Write-Host "  update  [<id>|--all] [--dry-run] [--channel stable]  Update plugin(s)"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix plugin list"
                Write-Host "  felix plugin list --remote"
                Write-Host "  felix plugin install sync-http"
                Write-Host "  felix plugin update --all --dry-run"
                Write-Host "  felix plugin remove my-plugin"
                Write-Host ""
            }
            "query" {
                Write-Host ""
                Write-Host "felix query <target> [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Structured query over Felix state."
                Write-Host ""
                Write-Host "Targets:" -ForegroundColor Yellow
                Write-Host "  requirements   Query requirements.json"
                Write-Host "  runs           Query run history"
                Write-Host "  state          Show agent state.json"
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --status <status>        Filter requirements by status"
                Write-Host "  --since <duration>       Filter runs by age (e.g. 24h, 7d)"
                Write-Host "  --requirement <id>       Filter runs by requirement ID"
                Write-Host "  --json                   Machine-readable output"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix query requirements --status planned"
                Write-Host "  felix query runs --since 24h --requirement S-0042"
                Write-Host "  felix query state --json"
                Write-Host ""
            }
            "recover" {
                Write-Host ""
                Write-Host "felix recover [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Recover from crashed parallel workers — inspect orphaned leases and worktrees."
                Write-Host "Also available as: felix run recover"
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --run <run-id>   Recover a specific run"
                Write-Host "  --all            Enumerate all orphaned runs"
                Write-Host "  --yes            Apply without interactive confirmation"
                Write-Host "  --dry-run        Show plan but make no changes"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix recover --all"
                Write-Host "  felix recover --run S-0042-20260601"
                Write-Host "  felix recover --all --yes"
                Write-Host "  felix recover --all --dry-run"
                Write-Host ""
            }
            "review" {
                Write-Host ""
                Write-Host "felix review [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Review and accept/reject agent learning proposals."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --learnings      Walk agents-md-suggestions.md proposals; accept/reject/defer"
                Write-Host "  --prompts        Audit prompts/skills for model-workaround heuristics"
                Write-Host "  --all            Both --learnings and --prompts in sequence"
                Write-Host "  --acknowledge    Stamp state.json#last_review (silences staleness warning)"
                Write-Host "  --dry-run        Preview without writing or committing"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix review --learnings"
                Write-Host "  felix review --all --dry-run"
                Write-Host "  felix review --acknowledge"
                Write-Host ""
            }
            "search" {
                Write-Host ""
                Write-Host "felix search <pattern> [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Full-text search across specs, runs, and project context."
                Write-Host ""
                Write-Host "Options:" -ForegroundColor Yellow
                Write-Host "  --scope file|symbol      Search scope (default: file)"
                Write-Host "  --in code|specs|runs|all Target corpus (default: all)"
                Write-Host "  --max <n>                Max results to return"
                Write-Host "  --json                   Machine-readable output"
                Write-Host "  --related-to <req-id>    Find content related to a requirement"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix search ""authentication"""
                Write-Host "  felix search ""token expiry"" --in specs"
                Write-Host "  felix search ""UserService"" --scope symbol"
                Write-Host "  felix search ""login"" --related-to S-0001 --json"
                Write-Host ""
            }
            "skill" {
                Write-Host ""
                Write-Host "felix skill <subcommand> [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Manage Felix skills (reusable agent capabilities)."
                Write-Host ""
                Write-Host "Subcommands:" -ForegroundColor Yellow
                Write-Host "  list    [--remote] [--json]                         List installed/available skills"
                Write-Host "  show    <id>                                        Show skill details"
                Write-Host "  enable  <id>                                        Enable a skill"
                Write-Host "  disable <id>                                        Disable a skill"
                Write-Host "  install <name|url|path> [--scope repo|user] [--channel stable|beta]  Install a skill"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix skill list"
                Write-Host "  felix skill list --remote"
                Write-Host "  felix skill show code-review"
                Write-Host "  felix skill install code-review --scope repo"
                Write-Host "  felix skill enable code-review"
                Write-Host "  felix skill disable code-review"
                Write-Host ""
            }
            "tool" {
                Write-Host ""
                Write-Host "felix tool <subcommand> [options]" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Manage the agent tool allowlist (which tools agents are permitted to call)."
                Write-Host ""
                Write-Host "Subcommands:" -ForegroundColor Yellow
                Write-Host "  list                             Show current allowlist config"
                Write-Host "  enable  <tool>                   Add a tool to the allowlist"
                Write-Host "  disable <tool>                   Block a tool"
                Write-Host "  harden  [--yes] [--dry-run]      Switch to deny-by-default; infer allowlist from audit log"
                Write-Host ""
                Write-Host "Examples:"
                Write-Host "  felix tool list"
                Write-Host "  felix tool enable bash"
                Write-Host "  felix tool disable browser"
                Write-Host "  felix tool harden --dry-run"
                Write-Host "  felix tool harden --yes"
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
        Write-Host "  recover               Recover from crashed parallel workers"
        Write-Host "  status [req-id]       Show requirement status"
        Write-Host "  list                  List all requirements with filters"
        Write-Host "  validate <req-id>     Run validation checks"
        Write-Host "  deps [req-id]         Show dependencies and validate status"
        Write-Host "  spec <subcommand>     Manage requirement specifications"
        Write-Host "  context <subcommand>  Generate/view project context documentation"
        Write-Host "  search <pattern>      Full-text search across specs, runs, and project code"
        Write-Host "  query <target>        Structured query over Felix state"
        Write-Host "  memory <subcommand>   Manage persistent agent memory"
        Write-Host "  skill <subcommand>    Manage Felix skills (reusable agent capabilities)"
        Write-Host "  plugin <subcommand>   Manage Felix plugins"
        Write-Host "  tool <subcommand>     Manage agent tool allowlist"
        Write-Host "  review [options]      Review and accept/reject agent learning proposals"
        Write-Host "  event <subcommand>    Inspect the Felix event stream"
        Write-Host "  migrate               Run schema migrations on project files"
        Write-Host "  gc                    Garbage-collect stale runs and orphaned worktrees"
        Write-Host "  doctor                Run health checks on the Felix project"
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
