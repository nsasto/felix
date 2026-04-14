using System.Text.Json.Nodes;
using Felix.Cli;
using Xunit;

namespace Felix.Cli.Tests;

public sealed class SpecCommandsTests
{
    [Fact]
    public void BuildSortedRequirementsArray_ClonesNodesBeforeReparenting()
    {
        var original = new JsonArray
        {
            new JsonObject { ["id"] = "SPRINT-0002", ["status"] = "planned" },
            new JsonObject { ["id"] = "SPRINT-0001", ["status"] = "planned" }
        };

        var rebuilt = Program.BuildSortedRequirementsArray(original);

        Assert.Equal(2, rebuilt.Count);
        Assert.Equal("SPRINT-0001", rebuilt[0]!["id"]!.GetValue<string>());
        Assert.Equal("SPRINT-0002", rebuilt[1]!["id"]!.GetValue<string>());
        Assert.Equal(2, original.Count);
        Assert.NotSame(original[0], rebuilt[1]);
        Assert.NotSame(original[1], rebuilt[0]);
    }
}
