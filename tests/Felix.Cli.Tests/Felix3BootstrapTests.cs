using Felix.Cli;
using Xunit;

namespace Felix.Cli.Tests;

public sealed class Felix3BootstrapTests
{
    [Fact]
    public void ResolveFelix3InstallDirectory_FindsSourceCheckoutSyncTransportFromEmbeddedRunLocation()
    {
        var tempRoot = Path.Combine(Path.GetTempPath(), "felix3-runtime-path-test-" + Guid.NewGuid().ToString("N"));
        var appDirectory = Path.Combine(tempRoot, "src", "Felix.Cli", "bin", "Release", "net10.0");
        var pluginPath = Path.Combine(tempRoot, ".felix", "plugins", "sync-http", "http-client.ps1");
        Directory.CreateDirectory(appDirectory);
        Directory.CreateDirectory(Path.GetDirectoryName(pluginPath)!);
        File.WriteAllText(pluginPath, "# test fixture");
        try
        {
            var resolved = Program.ResolveFelix3InstallDirectory(appDirectory, null);

            Assert.Equal(Path.Combine(tempRoot, ".felix"), resolved);
        }
        finally
        {
            if (Directory.Exists(tempRoot)) Directory.Delete(tempRoot, recursive: true);
        }
    }

    [Fact]
    public void ResolveFelix3InstallDirectory_PrefersBundledReleaseTransportDirectory()
    {
        var tempRoot = Path.Combine(Path.GetTempPath(), "felix3-runtime-path-test-" + Guid.NewGuid().ToString("N"));
        var appDirectory = Path.Combine(tempRoot, "app");
        var pluginPath = Path.Combine(appDirectory, "plugins", "sync-http", "http-client.ps1");
        Directory.CreateDirectory(Path.GetDirectoryName(pluginPath)!);
        File.WriteAllText(pluginPath, "# test fixture");
        try
        {
            var resolved = Program.ResolveFelix3InstallDirectory(appDirectory, null);

            Assert.Equal(appDirectory, resolved);
        }
        finally
        {
            if (Directory.Exists(tempRoot)) Directory.Delete(tempRoot, recursive: true);
        }
    }

    [Fact]
    public void Felix3BundleCacheKeyChangesWhenEmbeddedBundleChanges()
    {
        var first = Program.GetFelix3BundleCacheKey(new byte[] { 1, 2, 3 });
        var same = Program.GetFelix3BundleCacheKey(new byte[] { 1, 2, 3 });
        var changed = Program.GetFelix3BundleCacheKey(new byte[] { 1, 2, 4 });

        Assert.Equal(first, same);
        Assert.NotEqual(first, changed);
        Assert.Matches("^[0-9a-f]{16}$", first);
    }

    [Fact]
    public void ExtractFelix3ScriptsToDirectory_ExtractsV3EntryPointAndDependencies()
    {
        var tempRoot = Path.Combine(Path.GetTempPath(), "felix3-bundle-test-" + Guid.NewGuid().ToString("N"));
        try
        {
            var scriptPath = Program.ExtractFelix3ScriptsToDirectory(tempRoot);

            Assert.True(File.Exists(scriptPath));
            Assert.True(File.Exists(Path.Combine(tempRoot, "Invoke-Felix3Task.ps1")));
            Assert.True(File.Exists(Path.Combine(tempRoot, "grok", "Invoke-GrokBuildHarness.ps1")));
            Assert.False(File.Exists(Path.Combine(tempRoot, "felix.ps1")));
        }
        finally
        {
            if (Directory.Exists(tempRoot)) Directory.Delete(tempRoot, recursive: true);
        }
    }
}
