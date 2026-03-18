using System.Security.Cryptography;
using Felix.Cli;
using Xunit;

namespace Felix.Cli.Tests;

public sealed class UpdateCommandTests
{
    [Theory]
    [InlineData("v1.2.3", "1.2.3")]
    [InlineData("1.2.3-beta.1", "1.2.3")]
    [InlineData("  v2.0.0  ", "2.0.0")]
    public void NormalizeVersionString_StripsPrefixesAndPrerelease(string input, string expected)
    {
        Assert.Equal(expected, Program.NormalizeVersionString(input));
    }

    [Fact]
    public void CompareVersions_UsesSemanticOrdering()
    {
        Assert.True(Program.CompareVersions("1.0.1", "1.0.2") < 0);
        Assert.True(Program.CompareVersions("v1.2.0", "1.1.9") > 0);
        Assert.Equal(0, Program.CompareVersions("1.0.2", "v1.0.2"));
    }

    [Fact]
    public void SelectUpdateReleasePlan_PrefersStableLatestAliases()
    {
        var release = new Program.GitHubReleaseMetadata(
            "v1.0.2",
            new List<Program.GitHubReleaseAsset>
            {
                new("felix-1.0.2-win-x64.zip", "https://example.test/versioned.zip"),
                new("felix-latest-win-x64.zip", "https://example.test/latest.zip"),
                new("checksums-1.0.2.txt", "https://example.test/versioned-checksums.txt"),
                new("checksums-latest.txt", "https://example.test/latest-checksums.txt")
            });

        var plan = Program.SelectUpdateReleasePlan(release, "1.0.1", "1.0.2", hasInstalledCopy: true);

        Assert.NotNull(plan);
        Assert.Equal("felix-latest-win-x64.zip", plan!.ZipAsset.Name);
        Assert.Equal("checksums-latest.txt", plan.ChecksumAsset.Name);
        Assert.Equal("1.0.1", plan.CurrentVersion);
        Assert.Equal("1.0.2", plan.TargetVersion);
    }

    [Fact]
    public void SelectUpdateReleasePlan_FallsBackToVersionedAssets()
    {
        var release = new Program.GitHubReleaseMetadata(
            "v1.0.2",
            new List<Program.GitHubReleaseAsset>
            {
                new("felix-1.0.2-win-x64.zip", "https://example.test/versioned.zip"),
                new("checksums-1.0.2.txt", "https://example.test/versioned-checksums.txt")
            });

        var plan = Program.SelectUpdateReleasePlan(release, "1.0.1", "1.0.2", hasInstalledCopy: false);

        Assert.NotNull(plan);
        Assert.Equal("felix-1.0.2-win-x64.zip", plan!.ZipAsset.Name);
        Assert.Equal("checksums-1.0.2.txt", plan.ChecksumAsset.Name);
        Assert.False(plan.HasInstalledCopy);
    }

    [Fact]
    public void SelectUpdateReleasePlan_ReturnsNullWhenChecksumsAreMissing()
    {
        var release = new Program.GitHubReleaseMetadata(
            "v1.0.2",
            new List<Program.GitHubReleaseAsset>
            {
                new("felix-latest-win-x64.zip", "https://example.test/latest.zip")
            });

        var plan = Program.SelectUpdateReleasePlan(release, "1.0.1", "1.0.2", hasInstalledCopy: true);

        Assert.Null(plan);
    }

    [Fact]
    public void ParseChecksumLine_ReturnsHashAndFileName()
    {
        var parsed = Program.ParseChecksumLine("ABCDEF123456  felix-latest-win-x64.zip");

        Assert.True(parsed.HasValue);
        Assert.Equal("ABCDEF123456", parsed.Value.Hash);
        Assert.Equal("felix-latest-win-x64.zip", parsed.Value.FileName);
    }

    [Fact]
    public void ParseChecksumLine_ReturnsNullForInvalidInput()
    {
        Assert.Null(Program.ParseChecksumLine("not-a-valid-line"));
    }

    [Fact]
    public void VerifyDownloadedChecksum_AcceptsMatchingHash()
    {
        var tempDir = CreateTempDirectory();
        try
        {
            var zipPath = Path.Combine(tempDir, "felix-latest-win-x64.zip");
            File.WriteAllText(zipPath, "payload");

            var expectedHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(zipPath)));
            var checksumPath = Path.Combine(tempDir, "checksums-latest.txt");
            File.WriteAllText(checksumPath, $"{expectedHash}  felix-latest-win-x64.zip{Environment.NewLine}");

            Program.VerifyDownloadedChecksum(checksumPath, zipPath, "felix-latest-win-x64.zip");
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void VerifyDownloadedChecksum_ThrowsOnMismatch()
    {
        var tempDir = CreateTempDirectory();
        try
        {
            var zipPath = Path.Combine(tempDir, "felix-latest-win-x64.zip");
            File.WriteAllText(zipPath, "payload");

            var checksumPath = Path.Combine(tempDir, "checksums-latest.txt");
            File.WriteAllText(checksumPath, $"DEADBEEF  felix-latest-win-x64.zip{Environment.NewLine}");

            var ex = Assert.Throws<InvalidOperationException>(() =>
                Program.VerifyDownloadedChecksum(checksumPath, zipPath, "felix-latest-win-x64.zip"));

            Assert.Contains("Checksum mismatch", ex.Message);
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void BuildWindowsUpdateHelperScript_ContainsExpectedOperations()
    {
        var script = Program.BuildWindowsUpdateHelperScript();

        Assert.Contains("Wait-Process -Id $ParentPid", script);
        Assert.Contains("Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force", script);
        Assert.Contains("Remove-Item -LiteralPath $StageRoot -Recurse -Force", script);
    }

    private static string CreateTempDirectory()
    {
        var path = Path.Combine(Path.GetTempPath(), $"felix-cli-tests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }
}