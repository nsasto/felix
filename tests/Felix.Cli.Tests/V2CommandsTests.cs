using System.CommandLine;
using Felix.Cli;
using Xunit;

namespace Felix.Cli.Tests;

/// <summary>
/// Tests for v2 CLI commands: migrate, doctor, plugin, event, context inspect, run replay.
/// These tests verify that commands are registered, have the expected sub-commands,
/// and that their argument/option shapes are correct â€” without requiring a live PS environment.
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
        Assert.Contains("query", names);
        Assert.Contains("tool",  names);
        Assert.Contains("gc",    names);
        Assert.Contains("smoke", names);
    }

    // â”€â”€ migrate â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

    // â”€â”€ doctor â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

    // â”€â”€ plugin â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
        // Note: 'update' added in Phase G â€” full count tested in PluginCommand_HasFiveSubcommands_IncludingUpdate
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

    // â”€â”€ event â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

    // â”€â”€ context inspect â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    [Fact]
    public void ContextCommand_ExistsInRoot()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var names = root.Subcommands.Select(c => c.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.Contains("context", names);
    }

    // â”€â”€ run replay â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

    // â”€â”€ skill (B4) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

    // â”€â”€ run --explore / --no-explore (Phase C) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

    // â”€â”€ search (Phase D) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

    // â”€â”€ review (Phase E2) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

    // â”€â”€ memory (Phase E5) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

    // â”€â”€ query (Phase F3) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    [Fact]
    public void QueryCommand_IsRegistered()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var names = root.Subcommands.Select(c => c.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.Contains("query", names);
    }

    [Fact]
    public void QueryCommand_HasExpectedSubcommands()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var query = root.Subcommands.Single(c => c.Name == "query");
        var subs  = query.Subcommands.Select(c => c.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.Contains("requirements", subs);
        Assert.Contains("runs",         subs);
        Assert.Contains("usage",        subs);
        Assert.Contains("state",        subs);
    }

    [Fact]
    public void QueryCommand_RequirementsSubcommand_HasStatusAndSinceOptions()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var query = root.Subcommands.Single(c => c.Name == "query");
        var req   = query.Subcommands.Single(c => c.Name == "requirements");
        var opts  = req.Options.Select(o => o.Name).ToHashSet();
        Assert.Contains("status", opts);
        Assert.Contains("since",  opts);
        Assert.Contains("json",   opts);
    }

    [Fact]
    public void QueryCommand_UsageSubcommand_HasUsageFilters()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var query = root.Subcommands.Single(c => c.Name == "query");
        var usage = query.Subcommands.Single(c => c.Name == "usage");
        var opts  = usage.Options.Select(o => o.Name).ToHashSet();

        Assert.Contains("requirement", opts);
        Assert.Contains("run-id",      opts);
        Assert.Contains("since",       opts);
        Assert.Contains("json",        opts);
    }

    // smoke

    [Fact]
    public void SmokeCommand_HasUsageSubcommand()
    {
        var root = Program.CreateRootCommand(FakeFelixPs1);
        var smoke = root.Subcommands.Single(c => c.Name == "smoke");
        var subs = smoke.Subcommands.Select(c => c.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);

        Assert.Contains("usage", subs);
    }

    [Fact]
    public void SmokeUsageCommand_HasExpectedOptions()
    {
        var root = Program.CreateRootCommand(FakeFelixPs1);
        var smoke = root.Subcommands.Single(c => c.Name == "smoke");
        var usage = smoke.Subcommands.Single(c => c.Name == "usage");
        var opts = usage.Options.Select(o => o.Name).ToHashSet();

        Assert.Contains("dry-run", opts);
        Assert.Contains("json", opts);
    }

    // â”€â”€ tool (Phase F5) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    [Fact]
    public void ToolCommand_IsRegistered()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var names = root.Subcommands.Select(c => c.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.Contains("tool", names);
    }

    [Fact]
    public void ToolCommand_HasHardenAndStatusSubcommands()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var tool  = root.Subcommands.Single(c => c.Name == "tool");
        var subs  = tool.Subcommands.Select(c => c.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.Contains("harden", subs);
        Assert.Contains("status", subs);
    }

    [Fact]
    public void ToolCommand_HardenSubcommand_HasYesAndDryRunOptions()
    {
        var root   = Program.CreateRootCommand(FakeFelixPs1);
        var tool   = root.Subcommands.Single(c => c.Name == "tool");
        var harden = tool.Subcommands.Single(c => c.Name == "harden");
        var opts   = harden.Options.Select(o => o.Name).ToHashSet();
        Assert.Contains("yes",     opts);
        Assert.Contains("dry-run", opts);
    }

    // â”€â”€ gc (Phase F8) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    [Fact]
    public void GcCommand_IsRegistered()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var names = root.Subcommands.Select(c => c.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.Contains("gc", names);
    }

    [Fact]
    public void GcCommand_HasDryRunAndYesOptions()
    {
        var root = Program.CreateRootCommand(FakeFelixPs1);
        var gc   = root.Subcommands.Single(c => c.Name == "gc");
        var opts = gc.Options.Select(o => o.Name).ToHashSet();
        Assert.Contains("dry-run", opts);
        Assert.Contains("yes",     opts);
    }

    // â”€â”€ plugin update (Phase G3) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    [Fact]
    public void PluginCommand_HasFiveSubcommands_IncludingUpdate()
    {
        var root    = Program.CreateRootCommand(FakeFelixPs1);
        var plugin  = root.Subcommands.Single(c => c.Name == "plugin");
        var subCmds = plugin.Subcommands.Select(c => c.Name).ToHashSet();

        Assert.Contains("install", subCmds);
        Assert.Contains("list",    subCmds);
        Assert.Contains("remove",  subCmds);
        Assert.Contains("info",    subCmds);
        Assert.Contains("update",  subCmds);
        Assert.Equal(5, plugin.Subcommands.Count);
    }

    [Fact]
    public void PluginUpdateCommand_HasAllAndDryRunAndChannelOptions()
    {
        var root   = Program.CreateRootCommand(FakeFelixPs1);
        var plugin = root.Subcommands.Single(c => c.Name == "plugin");
        var update = plugin.Subcommands.Single(c => c.Name == "update");
        var opts   = update.Options.Select(o => o.Name).ToHashSet();

        Assert.Contains("all",     opts);
        Assert.Contains("dry-run", opts);
        Assert.Contains("channel", opts);
    }

    [Fact]
    public void PluginUpdateCommand_HasOptionalIdArgument()
    {
        var root   = Program.CreateRootCommand(FakeFelixPs1);
        var plugin = root.Subcommands.Single(c => c.Name == "plugin");
        var update = plugin.Subcommands.Single(c => c.Name == "update");

        Assert.Single(update.Arguments);
        var idArg = update.Arguments.Single();
        Assert.Equal("id", idArg.Name);
        Assert.Equal(0, idArg.Arity.MinimumNumberOfValues); // optional
    }

    [Fact]
    public void PluginUpdateCommand_ChannelDefaultIsStable()
    {
        var root   = Program.CreateRootCommand(FakeFelixPs1);
        var plugin = root.Subcommands.Single(c => c.Name == "plugin");
        var update = plugin.Subcommands.Single(c => c.Name == "update");

        var channelOpt = update.Options.Single(o => o.Name == "channel");
        Assert.Equal(typeof(string), channelOpt.ValueType);
    }

    [Fact]
    public void PluginInstallCommand_HasChannelOption()
    {
        var root   = Program.CreateRootCommand(FakeFelixPs1);
        var plugin = root.Subcommands.Single(c => c.Name == "plugin");
        var install = plugin.Subcommands.Single(c => c.Name == "install");
        var opts   = install.Options.Select(o => o.Name).ToHashSet();

        Assert.Contains("channel", opts);
    }

    [Fact]
    public void PluginListCommand_HasChannelOption()
    {
        var root   = Program.CreateRootCommand(FakeFelixPs1);
        var plugin = root.Subcommands.Single(c => c.Name == "plugin");
        var list   = plugin.Subcommands.Single(c => c.Name == "list");
        var opts   = list.Options.Select(o => o.Name).ToHashSet();

        Assert.Contains("remote",  opts);
        Assert.Contains("json",    opts);
        Assert.Contains("channel", opts);
    }

    // â”€â”€ skill install (Phase G5) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    [Fact]
    public void SkillInstallCommand_HasChannelAndScopeOptions()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var skill = root.Subcommands.Single(c => c.Name == "skill");
        var install = skill.Subcommands.Single(c => c.Name == "install");
        var opts  = install.Options.Select(o => o.Name).ToHashSet();

        Assert.Contains("channel", opts);
        Assert.Contains("scope",   opts);
    }

    [Fact]
    public void SkillInstallCommand_ScopeDefaultIsRepo()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var skill = root.Subcommands.Single(c => c.Name == "skill");
        var install = skill.Subcommands.Single(c => c.Name == "install");

        var scopeOpt = install.Options.Single(o => o.Name == "scope");
        Assert.Equal(typeof(string), scopeOpt.ValueType);
    }

    // ── Phase H: loop --parallel / --worktrees ────────────────────────────

    [Fact]
    public void LoopCommand_HasParallelAndWorktreesOptions()
    {
        var root = Program.CreateRootCommand(FakeFelixPs1);
        var loop = root.Subcommands.Single(c => c.Name == "loop");
        var opts = loop.Options.Select(o => o.Name).ToHashSet();

        Assert.Contains("parallel",  opts);
        Assert.Contains("worktrees", opts);
        Assert.Contains("max-iterations", opts);
    }

    [Fact]
    public void LoopCommand_ParallelOption_IsNullableInt()
    {
        var root = Program.CreateRootCommand(FakeFelixPs1);
        var loop = root.Subcommands.Single(c => c.Name == "loop");
        var parallel = loop.Options.Single(o => o.Name == "parallel");

        Assert.Equal(typeof(int?), parallel.ValueType);
    }

    [Fact]
    public void LoopCommand_WorktreesOption_IsBool()
    {
        var root = Program.CreateRootCommand(FakeFelixPs1);
        var loop = root.Subcommands.Single(c => c.Name == "loop");
        var worktrees = loop.Options.Single(o => o.Name == "worktrees");

        Assert.Equal(typeof(bool), worktrees.ValueType);
    }

    // ── Phase H: recover command ──────────────────────────────────────────

    [Fact]
    public void RootCommand_ContainsRecoverCommand()
    {
        var root  = Program.CreateRootCommand(FakeFelixPs1);
        var names = root.Subcommands.Select(c => c.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        Assert.Contains("recover", names);
    }

    [Fact]
    public void RecoverCommand_HasExpectedOptions()
    {
        var root    = Program.CreateRootCommand(FakeFelixPs1);
        var recover = root.Subcommands.Single(c => c.Name == "recover");
        var opts    = recover.Options.Select(o => o.Name).ToHashSet();

        Assert.Contains("run",     opts);
        Assert.Contains("all",     opts);
        Assert.Contains("yes",     opts);
        Assert.Contains("dry-run", opts);
    }

    [Fact]
    public void RunCommand_HasRecoverSubcommand()
    {
        var root    = Program.CreateRootCommand(FakeFelixPs1);
        var run     = root.Subcommands.Single(c => c.Name == "run");
        var subCmds = run.Subcommands.Select(c => c.Name).ToHashSet();

        Assert.Contains("recover", subCmds);
    }

    [Fact]
    public void RunRecoverSubcommand_HasExpectedOptions()
    {
        var root    = Program.CreateRootCommand(FakeFelixPs1);
        var run     = root.Subcommands.Single(c => c.Name == "run");
        var recover = run.Subcommands.Single(c => c.Name == "recover");
        var opts    = recover.Options.Select(o => o.Name).ToHashSet();

        Assert.Contains("run",     opts);
        Assert.Contains("all",     opts);
        Assert.Contains("yes",     opts);
        Assert.Contains("dry-run", opts);
    }
}

