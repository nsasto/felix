using System.CommandLine;

namespace Felix.Cli;

partial class Program
{
    static Command CreateFelix3Command()
    {
        var command = new Command("v3", "Run Felix 3 workflows and Cloud work sources");

        var setup = new Command("setup", "Create a Felix 3 project config")
        {
            new Option<string>("--harness", () => "claude-code", "Harness to configure: claude-code, opencode, or codex")
        };
        setup.SetHandler(async (string harness) => await ExecuteFelix3PowerShell("setup", "-Harness", harness), (Option<string>)setup.Options[0]);

        var run = new Command("run", "Run one named spec through plan, build, validation, and review")
        {
            new Argument<string>("requirement-id", "Stable work item ID"),
            new Option<string>("--spec", "Project-relative specification file path") { IsRequired = true }
        };
        run.SetHandler(async (string id, string spec) => await ExecuteFelix3PowerShell("run", "-RequirementId", id, "-SpecPath", spec), (Argument<string>)run.Arguments[0], (Option<string>)run.Options[0]);

        var next = new Command("next", "Claim and run one ready Felix Cloud work item");
        next.SetHandler(async () => await ExecuteFelix3PowerShell("next"));

        var loop = new Command("loop", "Continuously claim and run ready Felix Cloud work")
        {
            new Option<int>("--max-iterations", () => 0, "Maximum work cycles; 0 runs continuously")
        };
        loop.SetHandler(async (int maxIterations) => await ExecuteFelix3PowerShell("loop", "-MaxIterations", maxIterations.ToString()), (Option<int>)loop.Options[0]);

        var resume = new Command("resume", "Resume a saved Felix 3 run")
        {
            new Argument<string>("run-id", "Felix 3 run ID"),
            new Option<string?>("--answer", "Answer a pending question or approve/reject a plan")
        };
        resume.SetHandler(async (string runId, string? answer) =>
        {
            var args = new List<string> { "resume", "-RunId", runId };
            if (answer != null) args.AddRange(new[] { "-Answer", answer });
            await ExecuteFelix3PowerShell(args.ToArray());
        }, (Argument<string>)resume.Arguments[0], (Option<string?>)resume.Options[0]);

        var stop = new Command("stop", "Request cooperative stop for an active Felix 3 run")
        {
            new Argument<string>("run-id", "Felix 3 run ID")
        };
        stop.SetHandler(async (string runId) => await ExecuteFelix3PowerShell("stop", "-RunId", runId), (Argument<string>)stop.Arguments[0]);

        var status = new Command("status", "Show saved Felix 3 run state")
        {
            new Argument<string>("run-id", "Felix 3 run ID")
        };
        status.SetHandler(async (string runId) => await ExecuteFelix3PowerShell("status", "-RunId", runId), (Argument<string>)status.Arguments[0]);

        command.AddCommand(setup);
        command.AddCommand(run);
        command.AddCommand(next);
        command.AddCommand(loop);
        command.AddCommand(resume);
        command.AddCommand(stop);
        command.AddCommand(status);
        return command;
    }
}
