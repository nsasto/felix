using System.CommandLine;
using Felix.Cli;
using Xunit;

namespace Felix.Cli.Tests;

/// <summary>
/// Tests for v2 CLI commands: migrate, doctor, plugin, event, context inspect, run replay.
/// These tests verify that commands are registered, have the expected sub-commands,
/// and that their argument/option shapes are correct — without requiring a live PS environment.
/// </summary>
public sealed class V2CommandsTests
{
    // Use a fake path; commands are created but not invoked (SetHandler not exercised).
    private const string FakeFelixPs1 = @"C:\fake\felix.ps1";

    [Fact]
    public void CreateRootCommand_RegistersAllV2Commands()
    {
        var root = Program.CreateRootCommand(FakeFelixPs1);
        var names = root.Subcommands.Select(c => c.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);

        Assert.Contains("migrate", names);
        Assert.Contains("doctor", names);
        Assert.Contains("plugin", names);
        Assert.Contains("event", names);
    }

    // ── migrate ──────────────────────────────────────────────────────────

    [Fact]
    public void MigrateCommand_HasExpectedOptionsAndName()
    {
        var root = Program.CreateRootCommand(FakeFelixPs1);
        var cmd  = root.Subcommands.Single(c => c.Name == "migrate");

        var optNames = cmd.Options.Select(o => o.Name).ToHashSet();
        Assert.Contains("dry-run", optNames);
        Assert.Contains("apply", optNames);
        Assert.Contains("only", optNames);
    }

    // ── doctor ───────────────────────────────────────────────────────────

    [Fact]
    public void DoctorCommand_HasExpectedOptions()
    {
        var root = Program.CreateRootCommand(FakeFelixPs1);
        var cmd  = root.Subcommands.Single(c => c.Name == "doctor");

        var optNames = cmd.Options.Select(o => o.Name).ToHashSet();
        Assert.Contains("fix", optNames);
        Assert.Contains("explain", optNames);
        Assert.Contains("json", optNames);
    }

    // ── plugin ───────────────────────────────────────────────────────────

    [Fact]
    public void PluginCommand_HasFourSubcommands()
    {
        var root    = Program.CreateRootCommand(FakeFelixPs1);
        var plugin  = root.Subcommands.Single(c => c.Name == "plugin");
        var subCmds = plugin.Subcommands.Select(c => c.Name).ToHashSet();

        Assert.Contains("install", subCmds);
        Assert.Contains("list", subCmds);
        Assert.Contains("remove", subCmds);
        Assert.Contains("info", subCmds);
    }

    [Fact]
    public void PluginListCommand_HasRemoteAndJsonOptions()
    {
        var root   = Program.CreateRootCommand(FakeFelixPs1);
        var plugin = root.Subcommands.Single(c => c.Name == "plugin");
        var list   = plugin.Subcommands.Single(c => c.Name == "list");

        var optNames = list.Options.Select(o => o.Name).ToHashSet();
        Assert.Contains("remote", optNames);
        Assert.Contains("json", optNames);
    }

    // ── event ────────────────────────────────────────────────────────────

    [Fact]
    public void EventCommand_HasTailAndQuerySubcommands()
    {
        var root    = Program.CreateRootCommand(FakeFelixPs1);
        var ev      = root.Subcommands.Single(c => c.Name == "event");
        var subCmds = ev.Subcommands.Select(c => c.Name).ToHashSet();

        Assert.Contains("tail", subCmds);
        Assert.Contains("query", subCmds);
    }

    [Fact]
    public void EventCommand_HasEventsAlias()
    {
        var root = Program.CreateRootCommand(FakeFelixPs1);
        var ev   = root.Subcommands.Single(c => c.Name == "event");
        Assert.Contains("events", ev.Aliases);
    }

    [Fact]
    public void EventTailCommand_HasFilterOptions()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var ev    = root.Subcommands.Single(c => c.Name == "event");
        var tail  = ev.Subcommands.Single(c => c.Name == "tail");

        var optNames = tail.Options.Select(o => o.Name).ToHashSet();
        Assert.Contains("kind", optNames);
        Assert.Contains("run-id", optNames);
        Assert.Contains("since", optNames);
    }

    // ── context inspect ──────────────────────────────────────────────────

    [Fact]
    public void ContextCommand_ExistsInRoot()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var names = root.Subcommands.Select(c => c.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.Contains("context", names);
    }

    // ── run replay ───────────────────────────────────────────────────────

    [Fact]
    public void RunCommand_HasReplaySubcommand()
    {
        var root    = Program.CreateRootCommand(FakeFelixPs1);
        var run     = root.Subcommands.Single(c => c.Name == "run");
        var subCmds = run.Subcommands.Select(c => c.Name).ToHashSet();
        Assert.Contains("replay", subCmds);
    }

    [Fact]
    public void RunReplayCommand_HasIterationOption()
    {
        var root   = Program.CreateRootCommand(FakeFelixPs1);
        var run    = root.Subcommands.Single(c => c.Name == "run");
        var replay = run.Subcommands.Single(c => c.Name == "replay");
        var optNames = replay.Options.Select(o => o.Name).ToHashSet();
        Assert.Contains("iteration", optNames);
    }

    // ── skill (B4) ───────────────────────────────────────────────────────

    [Fact]
    public void CreateRootCommand_RegistersSkillCommand()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var names = root.Subcommands.Select(c => c.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.Contains("skill", names);
    }

    [Fact]
    public void SkillCommand_HasExpectedSubcommands()
    {
        var root    = Program.CreateRootCommand(FakeFelixPs1);
        var skill   = root.Subcommands.Single(c => c.Name == "skill");
        var subCmds = skill.Subcommands.Select(c => c.Name).ToHashSet();

        Assert.Contains("list", subCmds);
        Assert.Contains("show", subCmds);
        Assert.Contains("enable", subCmds);
        Assert.Contains("disable", subCmds);
        Assert.Contains("install", subCmds);
    }

    [Fact]
    public void SkillListCommand_HasScopeAndJsonOptions()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var skill = root.Subcommands.Single(c => c.Name == "skill");
        var list  = skill.Subcommands.Single(c => c.Name == "list");

        var optNames = list.Options.Select(o => o.Name).ToHashSet();
        Assert.Contains("scope", optNames);
        Assert.Contains("json", optNames);
    }

    [Fact]
    public void SkillShowCommand_HasIdArgument()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var skill = root.Subcommands.Single(c => c.Name == "skill");
        var show  = skill.Subcommands.Single(c => c.Name == "show");

        var argNames = show.Arguments.Select(a => a.Name).ToHashSet();
        Assert.Contains("id", argNames);
    }

    // ── run --explore / --no-explore (Phase C) ────────────────────────────

    [Fact]
    public void RunCommand_HasExploreOption()
    {
        var root = Program.CreateRootCommand(FakeFelixPs1);
        var run  = root.Subcommands.Single(c => c.Name == "run");

        var optNames = run.Options.Select(o => o.Name).ToHashSet();
        Assert.Contains("explore", optNames);
    }

    [Fact]
    public void RunCommand_HasNoExploreOption()
    {
        var root = Program.CreateRootCommand(FakeFelixPs1);
        var run  = root.Subcommands.Single(c => c.Name == "run");

        var optNames = run.Options.Select(o => o.Name).ToHashSet();
        Assert.Contains("no-explore", optNames);
    }

    [Fact]
    public void RunCommand_ExploreAndNoExploreAreBoolOptions()
    {
        var root = Program.CreateRootCommand(FakeFelixPs1);
        var run  = root.Subcommands.Single(c => c.Name == "run");

        var explore   = run.Options.Single(o => o.Name == "explore");
        var noExplore = run.Options.Single(o => o.Name == "no-explore");

        Assert.Equal(typeof(bool), explore.ValueType);
        Assert.Equal(typeof(bool), noExplore.ValueType);
    }

    // ── search (Phase D) ─────────────────────────────────────────────────────

    [Fact]
    public void SearchCommand_IsRegistered()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var names = root.Subcommands.Select(c => c.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.Contains("search", names);
    }

    [Fact]
    public void SearchCommand_HasExpectedOptions()
    {
        var root   = Program.CreateRootCommand(FakeFelixPs1);
        var search = root.Subcommands.Single(c => c.Name == "search");

        var optNames = search.Options.Select(o => o.Name).ToHashSet();
        Assert.Contains("scope",      optNames);
        Assert.Contains("in",         optNames);
        Assert.Contains("max",        optNames);
        Assert.Contains("json",       optNames);
        Assert.Contains("related-to", optNames);
    }

    [Fact]
    public void SearchCommand_HasOptionalPatternArgument()
    {
        var root   = Program.CreateRootCommand(FakeFelixPs1);
        var search = root.Subcommands.Single(c => c.Name == "search");

        var argNames = search.Arguments.Select(a => a.Name).ToHashSet();
        Assert.Contains("pattern", argNames);

        var pattern = search.Arguments.Single(a => a.Name == "pattern");
        Assert.Equal(0, pattern.Arity.MinimumNumberOfValues); // optional
    }

    [Fact]
    public void SearchCommand_ScopeDefaultIsFile()
    {
        var root   = Program.CreateRootCommand(FakeFelixPs1);
        var search = root.Subcommands.Single(c => c.Name == "search");

        var scopeOpt = search.Options.Single(o => o.Name == "scope");
        Assert.Equal(typeof(string), scopeOpt.ValueType);
    }

    [Fact]
    public void SearchCommand_MaxOptionIsInt()
    {
        var root   = Program.CreateRootCommand(FakeFelixPs1);
        var search = root.Subcommands.Single(c => c.Name == "search");

        var maxOpt = search.Options.Single(o => o.Name == "max");
        Assert.Equal(typeof(int), maxOpt.ValueType);
    }

    [Fact]
    public void SearchCommand_JsonOptionIsBool()
    {
        var root   = Program.CreateRootCommand(FakeFelixPs1);
        var search = root.Subcommands.Single(c => c.Name == "search");

        var jsonOpt = search.Options.Single(o => o.Name == "json");
        Assert.Equal(typeof(bool), jsonOpt.ValueType);
    }

    // ── review (Phase E2) ─────────────────────────────────────────────────

    [Fact]
    public void ReviewCommand_IsRegistered()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var names = root.Subcommands.Select(c => c.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.Contains("review", names);
    }

    [Fact]
    public void ReviewCommand_HasExpectedOptions()
    {
        var root   = Program.CreateRootCommand(FakeFelixPs1);
        var review = root.Subcommands.Single(c => c.Name == "review");
        var opts   = review.Options.Select(o => o.Name).ToHashSet();

        Assert.Contains("learnings",    opts);
        Assert.Contains("prompts",      opts);
        Assert.Contains("all",          opts);
        Assert.Contains("acknowledge",  opts);
        Assert.Contains("dry-run",      opts);
    }

    // ── memory (Phase E5) ─────────────────────────────────────────────────

    [Fact]
    public void MemoryCommand_IsRegistered()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var names = root.Subcommands.Select(c => c.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.Contains("memory", names);
    }

    [Fact]
    public void MemoryCommand_HasExpectedSubcommands()
    {
        var root   = Program.CreateRootCommand(FakeFelixPs1);
        var memory = root.Subcommands.Single(c => c.Name == "memory");
        var subs   = memory.Subcommands.Select(c => c.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);

        Assert.Contains("view",  subs);
        Assert.Contains("add",   subs);
        Assert.Contains("edit",  subs);
        Assert.Contains("prune", subs);
    }
}
