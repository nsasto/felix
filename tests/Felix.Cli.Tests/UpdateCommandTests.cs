using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Text;
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
    public async Task GetLatestGitHubReleaseAsync_ParsesMockedGitHubResponse()
    {
        const string payload = """
                {
                    "tag_name": "v1.2.3",
                    "assets": [
                        {
                            "name": "felix-latest-win-x64.zip",
                            "browser_download_url": "https://example.test/felix-latest-win-x64.zip"
                        },
                        {
                            "name": "checksums-latest.txt",
                            "browser_download_url": "https://example.test/checksums-latest.txt"
                        }
                    ]
                }
                """;

        using var client = new HttpClient(new StubHttpMessageHandler(_ =>
                new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent(payload, Encoding.UTF8, "application/json")
                }));

        var release = await Program.GetLatestGitHubReleaseAsync("nsasto/felix", client);

        Assert.Equal("v1.2.3", release.TagName);
        Assert.Equal(2, release.Assets.Count);
        Assert.Equal("felix-latest-win-x64.zip", release.Assets[0].Name);
        Assert.Equal("https://example.test/checksums-latest.txt", release.Assets[1].DownloadUrl);
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
        Assert.Equal(new[] { "felix-latest-win-x64.zip", "felix-1.0.2-win-x64.zip" }, plan.AcceptedChecksumFileNames);
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

        var plan = Program.SelectUpdateReleasePlan(release, "1.0.1", "1.0.2", hasInstalledCopy: false, releaseRid: "win-x64");

        Assert.NotNull(plan);
        Assert.Equal("felix-1.0.2-win-x64.zip", plan!.ZipAsset.Name);
        Assert.Equal("checksums-1.0.2.txt", plan.ChecksumAsset.Name);
        Assert.Equal(new[] { "felix-1.0.2-win-x64.zip" }, plan.AcceptedChecksumFileNames);
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

        var plan = Program.SelectUpdateReleasePlan(release, "1.0.1", "1.0.2", hasInstalledCopy: true, releaseRid: "win-x64");

        Assert.Null(plan);
    }

    [Fact]
    public void SelectUpdateReleasePlan_ChoosesLinuxAssetsWhenRequested()
    {
        var release = new Program.GitHubReleaseMetadata(
            "v1.0.2",
            new List<Program.GitHubReleaseAsset>
            {
                new("felix-latest-linux-x64.zip", "https://example.test/latest-linux.zip"),
                new("checksums-latest.txt", "https://example.test/checksums.txt")
            });

        var plan = Program.SelectUpdateReleasePlan(release, "1.0.1", "1.0.2", hasInstalledCopy: true, releaseRid: "linux-x64");

        Assert.NotNull(plan);
        Assert.Equal("felix-latest-linux-x64.zip", plan!.ZipAsset.Name);
    }

    [Fact]
    public void SelectUpdateReleasePlan_ChoosesMacAssetsWhenRequested()
    {
        var release = new Program.GitHubReleaseMetadata(
            "v1.0.2",
            new List<Program.GitHubReleaseAsset>
            {
                new("felix-1.0.2-osx-arm64.zip", "https://example.test/osx-arm64.zip"),
                new("checksums-1.0.2.txt", "https://example.test/checksums.txt")
            });

        var plan = Program.SelectUpdateReleasePlan(release, "1.0.1", "1.0.2", hasInstalledCopy: true, releaseRid: "osx-arm64");

        Assert.NotNull(plan);
        Assert.Equal("felix-1.0.2-osx-arm64.zip", plan!.ZipAsset.Name);
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

            Program.VerifyDownloadedChecksum(checksumPath, zipPath, new[] { "felix-latest-win-x64.zip" });
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
                Program.VerifyDownloadedChecksum(checksumPath, zipPath, new[] { "felix-latest-win-x64.zip" }));

            Assert.Contains("Checksum mismatch", ex.Message);
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void VerifyDownloadedChecksum_AcceptsVersionedFallbackForLatestAlias()
    {
        var tempDir = CreateTempDirectory();
        try
        {
            var zipPath = Path.Combine(tempDir, "felix-latest-win-x64.zip");
            File.WriteAllText(zipPath, "payload");

            var expectedHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(zipPath)));
            var checksumPath = Path.Combine(tempDir, "checksums-latest.txt");
            File.WriteAllText(checksumPath, $"{expectedHash}  felix-1.1.2-win-x64.zip{Environment.NewLine}");

            Program.VerifyDownloadedChecksum(
                checksumPath,
                zipPath,
                new[] { "felix-latest-win-x64.zip", "felix-1.1.2-win-x64.zip" });
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

    [Fact]
    public void BuildUnixUpdateHelperScript_ContainsExpectedOperations()
    {
        var script = Program.BuildUnixUpdateHelperScript();

        Assert.Contains("cp -R \"$PAYLOAD_DIR\"/. \"$INSTALL_DIR\"/", script);
        Assert.Contains("chmod +x \"$INSTALL_DIR/felix\"", script);
        Assert.Contains("rm -rf \"$STAGE_ROOT\"", script);
    }

    [Fact]
    public void WindowsHelperScript_AppliesStagedPayloadInTempDirectory()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        var rootDir = CreateTempDirectory();
        var stageRoot = Path.Combine(rootDir, "stage");
        var payloadDir = Path.Combine(stageRoot, "payload");
        var installDir = Path.Combine(rootDir, "install");
        Directory.CreateDirectory(payloadDir);
        Directory.CreateDirectory(installDir);
        Directory.CreateDirectory(Path.Combine(payloadDir, ".felix", "commands"));

        File.WriteAllText(Path.Combine(payloadDir, "felix.exe"), "new-binary");
        File.WriteAllText(Path.Combine(payloadDir, "version.txt"), "1.2.3");
        File.WriteAllText(Path.Combine(payloadDir, ".felix", "commands", "help.ps1"), "new-help");
        File.WriteAllText(Path.Combine(installDir, "felix.exe"), "old-binary");

        var scriptPath = Path.Combine(rootDir, "apply-update.ps1");
        File.WriteAllText(scriptPath, Program.BuildWindowsUpdateHelperScript(), new UTF8Encoding(false));

        var process = Process.Start(new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\" -ParentPid 0 -StageRoot \"{stageRoot}\" -InstallDir \"{installDir}\"",
            UseShellExecute = false,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            CreateNoWindow = true
        });

        Assert.NotNull(process);
        process!.WaitForExit();

        var stderr = process.StandardError.ReadToEnd();
        var stdout = process.StandardOutput.ReadToEnd();

        try
        {
            Assert.Equal(0, process.ExitCode);
            Assert.True(File.Exists(Path.Combine(installDir, "felix.exe")));
            Assert.Equal("new-binary", File.ReadAllText(Path.Combine(installDir, "felix.exe")));
            Assert.Equal("1.2.3", File.ReadAllText(Path.Combine(installDir, "version.txt")));
            Assert.Equal("new-help", File.ReadAllText(Path.Combine(installDir, ".felix", "commands", "help.ps1")));
            Assert.False(Directory.Exists(stageRoot));
        }
        catch
        {
            throw new Xunit.Sdk.XunitException($"Helper script failed. Stdout: {stdout}{Environment.NewLine}Stderr: {stderr}");
        }
        finally
        {
            Directory.Delete(rootDir, recursive: true);
        }
    }

    [Fact]
    public void UnixHelperScript_AppliesStagedPayloadInTempDirectory()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var rootDir = CreateTempDirectory();
        var stageRoot = Path.Combine(rootDir, "stage");
        var payloadDir = Path.Combine(stageRoot, "payload");
        var installDir = Path.Combine(rootDir, "install");
        Directory.CreateDirectory(Path.Combine(payloadDir, ".felix", "commands"));
        Directory.CreateDirectory(installDir);

        File.WriteAllText(Path.Combine(payloadDir, "felix"), "new-binary");
        File.WriteAllText(Path.Combine(payloadDir, "version.txt"), "1.2.3");
        File.WriteAllText(Path.Combine(payloadDir, ".felix", "commands", "help.ps1"), "new-help");
        File.WriteAllText(Path.Combine(installDir, "felix"), "old-binary");

        var scriptPath = Path.Combine(rootDir, "apply-update.sh");
        File.WriteAllText(scriptPath, Program.BuildUnixUpdateHelperScript(), new UTF8Encoding(false));

        var chmodProcess = Process.Start(new ProcessStartInfo
        {
            FileName = "/bin/chmod",
            Arguments = $"+x \"{scriptPath}\"",
            UseShellExecute = false,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            CreateNoWindow = true
        });

        Assert.NotNull(chmodProcess);
        chmodProcess!.WaitForExit();
        Assert.Equal(0, chmodProcess.ExitCode);

        var process = Process.Start(new ProcessStartInfo
        {
            FileName = "/bin/sh",
            Arguments = $"\"{scriptPath}\" 0 \"{stageRoot}\" \"{installDir}\"",
            UseShellExecute = false,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            CreateNoWindow = true
        });

        Assert.NotNull(process);
        process!.WaitForExit();

        var stderr = process.StandardError.ReadToEnd();
        var stdout = process.StandardOutput.ReadToEnd();

        try
        {
            Assert.Equal(0, process.ExitCode);
            Assert.True(File.Exists(Path.Combine(installDir, "felix")));
            Assert.Equal("new-binary", File.ReadAllText(Path.Combine(installDir, "felix")));
            Assert.Equal("1.2.3", File.ReadAllText(Path.Combine(installDir, "version.txt")));
            Assert.Equal("new-help", File.ReadAllText(Path.Combine(installDir, ".felix", "commands", "help.ps1")));
            Assert.False(Directory.Exists(stageRoot));
        }
        catch
        {
            throw new Xunit.Sdk.XunitException($"Unix helper script failed. Stdout: {stdout}{Environment.NewLine}Stderr: {stderr}");
        }
        finally
        {
            Directory.Delete(rootDir, recursive: true);
        }
    }

    private static string CreateTempDirectory()
    {
        var path = Path.Combine(Path.GetTempPath(), $"felix-cli-tests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }

    private sealed class StubHttpMessageHandler(Func<HttpRequestMessage, HttpResponseMessage> responder) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            return Task.FromResult(responder(request));
        }
    }
}