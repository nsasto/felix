using System.CommandLine;
using System.Diagnostics;
using System.IO.Compression;
using System.Net.Http.Headers;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Spectre.Console;

namespace Felix.Cli;

partial class Program
{
    static string _felixInstallDir = string.Empty;
    static string _felixProjectRoot = string.Empty;
    static readonly object _renderSync = new();
    const int FelixCategoryColumnWidth = 10;
    const string DefaultUpdateRepo = "nsasto/felix";
    const string DefaultWindowsReleaseRid = "win-x64";

    internal sealed record GitHubReleaseAsset(string Name, string DownloadUrl);
    internal sealed record GitHubReleaseMetadata(string TagName, IReadOnlyList<GitHubReleaseAsset> Assets);
    internal sealed record UpdateReleasePlan(string CurrentVersion, string TargetVersion, GitHubReleaseAsset ZipAsset, GitHubReleaseAsset ChecksumAsset, string[] AcceptedChecksumFileNames, bool HasInstalledCopy);

    sealed class FelixRichRunState
    {
        public string CommandLabel { get; init; } = "Felix";
        public string? RunId { get; set; }
        public string? RequirementId { get; set; }
        public string? LatestMode { get; set; }
        public string? AgentName { get; set; }
        public string? CompletionStatus { get; set; }
        public int? Iteration { get; set; }
        public int? MaxIterations { get; set; }
        public int Errors { get; set; }
        public int Warnings { get; set; }
        public int TasksCompleted { get; set; }
        public int TasksFailed { get; set; }
        public int ValidationsPassed { get; set; }
        public int ValidationsFailed { get; set; }
        public double? DurationSeconds { get; set; }
        public string? TerminationReason { get; set; }
        public bool HasContractViolation { get; set; }
        public string? LastAgentResponseContent { get; set; }
        public int LastAgentResponseLength { get; set; }
        public bool ExitHandlerSeen { get; set; }
        public DateTimeOffset? ExitHandlerSeenAtUtc { get; set; }
        public bool IsVerbose { get; init; }
        public bool IsDebug { get; init; }
        public bool IsSync { get; init; }
    }
}
