using System.CommandLine;
using System.Diagnostics;
using System.IO.Compression;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Spectre.Console;

namespace Felix.Cli;

partial class Program
{
    static async Task ShowVersionUI()
    {
        var installDir = GetInstallDirectory();
        var installedVersion = GetInstalledVersion(installDir);
        var embeddedVersion = ReadEmbeddedVersion();
        var currentVersion = installedVersion ?? embeddedVersion;

        string branch = "-";
        string commit = "-";
        try
        {
            branch = (await CaptureGitOutputAsync("rev-parse --abbrev-ref HEAD")) ?? "-";
            commit = (await CaptureGitOutputAsync("rev-parse --short HEAD")) ?? "-";
        }
        catch { }

        AnsiConsole.Write(new Rule("[cyan]Felix Version[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var table = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey)
            .AddColumn(new TableColumn("[yellow]Field[/]").NoWrap())
            .AddColumn(new TableColumn("[yellow]Value[/]"));

        table.AddRow("Version", $"[white]{currentVersion.EscapeMarkup()}[/]");
        table.AddRow("Embedded", $"[grey]{embeddedVersion.EscapeMarkup()}[/]");
        table.AddRow("Installed", string.IsNullOrWhiteSpace(installedVersion) ? "[grey]not installed[/]" : $"[white]{installedVersion!.EscapeMarkup()}[/]");
        table.AddRow("Repository", $"[white]{_felixProjectRoot.EscapeMarkup()}[/]");
        table.AddRow("Branch", $"[white]{branch.EscapeMarkup()}[/]");
        table.AddRow("Commit", $"[white]{commit.EscapeMarkup()}[/]");

        AnsiConsole.Write(new Panel(table)
        {
            Header = new PanelHeader("[cyan]Version Information[/]"),
            Border = BoxBorder.Rounded,
            BorderStyle = Style.Parse("cyan")
        });
        AnsiConsole.WriteLine();
    }

    static async Task<int> RunSelfUpdateAsync(bool checkOnly, bool assumeYes)
    {
        string releaseRid;
        try
        {
            releaseRid = GetCurrentReleaseRid();
        }
        catch (PlatformNotSupportedException ex)
        {
            AnsiConsole.MarkupLine($"[yellow]{ex.Message.EscapeMarkup()}[/]");
            return 1;
        }

        var installDir = GetInstallDirectory();
        var installedVersion = GetInstalledVersion(installDir);
        var currentVersion = installedVersion ?? ReadEmbeddedVersion();
        var executableName = GetExecutableFileName(releaseRid);
        var hasInstalledCopy = File.Exists(Path.Combine(installDir, executableName));

        GitHubReleaseMetadata release;
        try
        {
            release = await AnsiConsole.Status()
                .Spinner(Spinner.Known.Dots)
                .StartAsync("Checking GitHub releases...", _ => GetLatestGitHubReleaseAsync(DefaultUpdateRepo));
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]Update check failed:[/] {ex.Message.EscapeMarkup()}");
            return 1;
        }

        var targetVersion = NormalizeVersionString(release.TagName);
        var plan = SelectUpdateReleasePlan(release, currentVersion, targetVersion, hasInstalledCopy, releaseRid);
        if (plan == null)
        {
            AnsiConsole.MarkupLine($"[red]Update failed:[/] Could not find the required {releaseRid.EscapeMarkup()} release assets on GitHub.");
            return 1;
        }

        var comparison = CompareVersions(plan.CurrentVersion, plan.TargetVersion);
        var updateAvailable = !plan.HasInstalledCopy || comparison < 0;

        RenderUpdateOverview(plan, installDir, releaseRid, updateAvailable, checkOnly);
        AnsiConsole.MarkupLine($"[grey]Source:[/] https://github.com/{DefaultUpdateRepo}/releases/latest");

        if (!updateAvailable)
        {
            AnsiConsole.MarkupLine("[green]Felix is already up to date.[/]");
            return 0;
        }

        if (checkOnly)
        {
            if (plan.HasInstalledCopy)
            {
                AnsiConsole.MarkupLine("[yellow]Update available.[/]");
            }
            else
            {
                AnsiConsole.MarkupLine($"[yellow]No installed Felix copy found in[/] [grey]{installDir.EscapeMarkup()}[/]");
                AnsiConsole.MarkupLine("[yellow]The latest release is available to install.[/]");
            }
            return 0;
        }

        if (!assumeYes)
        {
            var prompt = BuildUpdateActionPrompt(plan, installDir);

            if (!AnsiConsole.Confirm(prompt))
            {
                AnsiConsole.MarkupLine("[grey]Update cancelled.[/]");
                return 0;
            }
        }

        string stageRoot;
        try
        {
            stageRoot = await AnsiConsole.Status()
                .Spinner(Spinner.Known.Dots)
                .StartAsync("Preparing update...", async ctx =>
                {
                    return await DownloadAndStageReleaseAsync(plan, message =>
                    {
                        ctx.Status(message);
                        ctx.Refresh();
                    });
                });
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]Download failed:[/] {ex.Message.EscapeMarkup()}");
            return 1;
        }

        Directory.CreateDirectory(installDir);
        var addedToPath = OperatingSystem.IsWindows() && EnsureWindowsInstallDirOnPath(installDir);

        try
        {
            LaunchUpdateHelper(stageRoot, installDir, releaseRid, plan.TargetVersion);
        }
        catch (Exception ex)
        {
            AnsiConsole.MarkupLine($"[red]Could not launch the updater helper:[/] {ex.Message.EscapeMarkup()}");
            return 1;
        }

        AnsiConsole.WriteLine();
        RenderUpdateSuccess(plan, installDir, addedToPath, stageRoot);
        return 0;
    }

    internal static async Task<GitHubReleaseMetadata> GetLatestGitHubReleaseAsync(string repo, HttpClient? client = null)
    {
        var disposeClient = client == null;
        client ??= CreateGitHubHttpClient();
        using var request = new HttpRequestMessage(HttpMethod.Get, $"https://api.github.com/repos/{repo}/releases/latest");
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));

        try
        {
            using var response = await client.SendAsync(request);
            var content = await response.Content.ReadAsStringAsync();
            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException($"GitHub API returned {(int)response.StatusCode}: {content}");
            }

            using var document = JsonDocument.Parse(content);
            var root = document.RootElement;
            var tagName = root.GetProperty("tag_name").GetString() ?? throw new InvalidOperationException("GitHub release response did not include tag_name.");
            var assets = new List<GitHubReleaseAsset>();

            foreach (var assetElement in root.GetProperty("assets").EnumerateArray())
            {
                var name = assetElement.GetProperty("name").GetString();
                var downloadUrl = assetElement.GetProperty("browser_download_url").GetString();
                if (!string.IsNullOrWhiteSpace(name) && !string.IsNullOrWhiteSpace(downloadUrl))
                {
                    assets.Add(new GitHubReleaseAsset(name, downloadUrl));
                }
            }

            return new GitHubReleaseMetadata(tagName, assets);
        }
        finally
        {
            if (disposeClient)
            {
                client.Dispose();
            }
        }
    }

    static HttpClient CreateGitHubHttpClient()
    {
        var client = new HttpClient();
        client.DefaultRequestHeaders.UserAgent.ParseAdd($"Felix/{ReadEmbeddedVersion()}");
        client.Timeout = TimeSpan.FromMinutes(5);
        return client;
    }

    internal static UpdateReleasePlan? SelectUpdateReleasePlan(GitHubReleaseMetadata release, string currentVersion, string targetVersion, bool hasInstalledCopy, string? releaseRid = null)
    {
        var rid = releaseRid ?? GetCurrentReleaseRid();
        var zipAsset = FindReleaseAsset(release, new[]
        {
            $"felix-latest-{rid}.zip",
            $"felix-{targetVersion}-{rid}.zip"
        });

        var checksumAsset = FindReleaseAsset(release, new[]
        {
            "checksums-latest.txt",
            $"checksums-{targetVersion}.txt"
        });

        if (zipAsset == null || checksumAsset == null)
        {
            return null;
        }

        return new UpdateReleasePlan(
            currentVersion,
            targetVersion,
            zipAsset,
            checksumAsset,
            GetAcceptedChecksumFileNames(zipAsset.Name, targetVersion).ToArray(),
            hasInstalledCopy);
    }

    internal static GitHubReleaseAsset? FindReleaseAsset(GitHubReleaseMetadata release, IEnumerable<string> candidateNames)
    {
        foreach (var candidate in candidateNames)
        {
            var asset = release.Assets.FirstOrDefault(a => string.Equals(a.Name, candidate, StringComparison.OrdinalIgnoreCase));
            if (asset != null)
            {
                return asset;
            }
        }

        return null;
    }

    internal static IEnumerable<string> GetAcceptedChecksumFileNames(string assetName, string targetVersion)
    {
        yield return assetName;

        const string latestMarker = "latest-";
        var markerIndex = assetName.IndexOf(latestMarker, StringComparison.OrdinalIgnoreCase);
        if (markerIndex >= 0)
        {
            var versionedName = string.Concat(
                assetName.AsSpan(0, markerIndex),
                targetVersion,
                "-",
                assetName.AsSpan(markerIndex + latestMarker.Length));

            if (!string.Equals(versionedName, assetName, StringComparison.OrdinalIgnoreCase))
            {
                yield return versionedName;
            }
        }
    }

    static void RenderUpdateOverview(UpdateReleasePlan plan, string installDir, string releaseRid, bool updateAvailable, bool checkOnly)
    {
        AnsiConsole.Write(new Rule("[cyan]Felix Update[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        var statusMarkup = !plan.HasInstalledCopy
            ? "[yellow]Ready to install[/]"
            : updateAvailable
                ? "[yellow]Update available[/]"
                : "[green]Up to date[/]";

        var actionMarkup = checkOnly
            ? "[grey]Check only[/]"
            : updateAvailable
                ? "[cyan]Will stage installer after confirmation[/]"
                : "[grey]No action needed[/]";

        var summaryTable = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(updateAvailable ? Color.Yellow : Color.Green3)
            .AddColumn(new TableColumn("[yellow]Field[/]").RightAligned())
            .AddColumn(new TableColumn("[yellow]Value[/]"));

        summaryTable.AddRow("[grey]Status[/]", statusMarkup);
        summaryTable.AddRow("[grey]Current[/]", $"[white]{plan.CurrentVersion.EscapeMarkup()}[/]");
        summaryTable.AddRow("[grey]Latest[/]", $"[white]{plan.TargetVersion.EscapeMarkup()}[/]");
        summaryTable.AddRow("[grey]Platform[/]", $"[white]{releaseRid.EscapeMarkup()}[/]");
        summaryTable.AddRow("[grey]Install Dir[/]", $"[grey]{installDir.EscapeMarkup()}[/]");
        summaryTable.AddRow("[grey]Package[/]", $"[grey]{plan.ZipAsset.Name.EscapeMarkup()}[/]");
        summaryTable.AddRow("[grey]Action[/]", actionMarkup);

        AnsiConsole.Write(summaryTable);
        AnsiConsole.WriteLine();

        var nextStepMessage = !plan.HasInstalledCopy
            ? "Felix did not find an installed CLI in the standard install directory. Continuing will install the latest packaged release there and wire it into your user PATH when needed."
            : updateAvailable
                ? "Felix will download the published release zip, verify the checksum, stage the payload, and hand off to the updater helper after this process exits."
                : "The installed CLI already matches the latest published GitHub release for this platform.";

        if (checkOnly)
        {
            nextStepMessage += " This run only checks availability and does not modify the installation.";
        }

        var panel = new Panel($"[grey]{nextStepMessage.EscapeMarkup()}[/]")
        {
            Header = new PanelHeader("Next", Justify.Left),
            Border = BoxBorder.Rounded,
            BorderStyle = new Style(Color.Grey)
        };

        AnsiConsole.Write(panel);
        AnsiConsole.WriteLine();
    }

    static string BuildUpdateActionPrompt(UpdateReleasePlan plan, string installDir)
    {
        return plan.HasInstalledCopy
            ? $"Replace Felix {plan.CurrentVersion} with {plan.TargetVersion} in {installDir}?"
            : $"Install Felix {plan.TargetVersion} to {installDir}?";
    }

    static void RenderUpdateSuccess(UpdateReleasePlan plan, string installDir, bool addedToPath, string stageRoot = "")
    {
        var resultsTable = new Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Green3)
            .AddColumn(new TableColumn("[yellow]Step[/]"))
            .AddColumn(new TableColumn("[yellow]Result[/]"));

        resultsTable.AddRow("[green]Downloaded package[/]", $"[grey]{plan.ZipAsset.Name.EscapeMarkup()}[/]");
        resultsTable.AddRow("[green]Verified checksum[/]", $"[grey]{plan.ChecksumAsset.Name.EscapeMarkup()}[/]");
        resultsTable.AddRow("[green]Staged payload[/]", $"[grey]{installDir.EscapeMarkup()}[/]");

        if (addedToPath)
        {
            resultsTable.AddRow("[green]Updated PATH[/]", $"[grey]{installDir.EscapeMarkup()}[/]");
        }

        AnsiConsole.Write(resultsTable);
        AnsiConsole.WriteLine();
        AnsiConsole.MarkupLine($"[green]Felix {plan.TargetVersion.EscapeMarkup()} staged successfully.[/]");
        AnsiConsole.MarkupLine("[grey]The updater is running in the background. Wait a few seconds, then run 'felix version' to confirm.[/]");
        if (!string.IsNullOrWhiteSpace(stageRoot))
        {
            var logPath = Path.Combine(stageRoot, "update-log.txt");
            AnsiConsole.MarkupLine($"[grey]If the version does not change, check the update log: {logPath.EscapeMarkup()}[/]");
        }
    }

    static async Task<string> DownloadAndStageReleaseAsync(UpdateReleasePlan plan, Action<string>? onProgress = null)
    {
        var stageRoot = Path.Combine(Path.GetTempPath(), $"felix-update-{Guid.NewGuid():N}");
        Directory.CreateDirectory(stageRoot);

        var zipPath = Path.Combine(stageRoot, plan.ZipAsset.Name);
        var checksumPath = Path.Combine(stageRoot, plan.ChecksumAsset.Name);
        var payloadDir = Path.Combine(stageRoot, "payload");

        using var client = CreateGitHubHttpClient();

        onProgress?.Invoke($"Downloading {plan.ZipAsset.Name}...");
        await DownloadFileAsync(client, plan.ZipAsset.DownloadUrl, zipPath);

        onProgress?.Invoke($"Downloading {plan.ChecksumAsset.Name}...");
        await DownloadFileAsync(client, plan.ChecksumAsset.DownloadUrl, checksumPath);

        onProgress?.Invoke("Verifying checksum...");
        VerifyDownloadedChecksum(checksumPath, zipPath, plan.AcceptedChecksumFileNames);

        onProgress?.Invoke("Extracting release payload...");
        ZipFile.ExtractToDirectory(zipPath, payloadDir);

        var executableName = GetExecutableFileName();
        var stagedExe = Path.Combine(payloadDir, executableName);
        if (!File.Exists(stagedExe))
        {
            throw new InvalidOperationException($"Downloaded archive did not contain {executableName}.");
        }

        return stageRoot;
    }

    static async Task DownloadFileAsync(HttpClient client, string downloadUrl, string destinationPath)
    {
        using var response = await client.GetAsync(downloadUrl, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();

        await using var responseStream = await response.Content.ReadAsStreamAsync();
        await using var fileStream = File.Create(destinationPath);
        await responseStream.CopyToAsync(fileStream);
    }

    internal static void VerifyDownloadedChecksum(string checksumPath, string filePath, IEnumerable<string> expectedFileNames)
    {
        var expectedNames = expectedFileNames
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var checksumEntry = File.ReadAllLines(checksumPath)
            .Select(line => line.Trim())
            .Where(line => !string.IsNullOrWhiteSpace(line))
            .Select(ParseChecksumLine)
            .Where(result => result.HasValue)
            .Select(result => result!.Value)
            .FirstOrDefault(result => expectedNames.Contains(result.FileName, StringComparer.OrdinalIgnoreCase));

        if (string.IsNullOrWhiteSpace(checksumEntry.Hash))
        {
            throw new InvalidOperationException($"Checksum file did not include an entry for any of: {string.Join(", ", expectedNames)}.");
        }

        using var sha = SHA256.Create();
        using var stream = File.OpenRead(filePath);
        var actualHash = Convert.ToHexString(sha.ComputeHash(stream));
        if (!string.Equals(actualHash, checksumEntry.Hash, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException($"Checksum mismatch for {checksumEntry.FileName}. Expected {checksumEntry.Hash}, got {actualHash}.");
        }
    }

    internal static (string Hash, string FileName)? ParseChecksumLine(string line)
    {
        var separatorIndex = line.IndexOf("  ", StringComparison.Ordinal);
        if (separatorIndex < 0)
        {
            return null;
        }

        var hash = line.Substring(0, separatorIndex).Trim();
        var fileName = line.Substring(separatorIndex + 2).Trim();
        if (string.IsNullOrWhiteSpace(hash) || string.IsNullOrWhiteSpace(fileName))
        {
            return null;
        }

        return (hash, fileName);
    }

    static void LaunchUpdateHelper(string stageRoot, string installDir, string releaseRid, string targetVersion = "")
    {
        var isWindows = releaseRid.StartsWith("win-", StringComparison.OrdinalIgnoreCase);
        var helperExtension = isWindows ? ".ps1" : ".sh";
        var helperScriptPath = Path.Combine(Path.GetTempPath(), $"felix-apply-update-{Guid.NewGuid():N}{helperExtension}");
        var helperScript = isWindows ? BuildWindowsUpdateHelperScript() : BuildUnixUpdateHelperScript();

        File.WriteAllText(helperScriptPath, helperScript, new UTF8Encoding(false));

        ProcessStartInfo startInfo;
        if (isWindows)
        {
            startInfo = new ProcessStartInfo
            {
                FileName = FindPowerShell(),
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{helperScriptPath}\" -ParentPid {Environment.ProcessId} -StageRoot \"{stageRoot}\" -InstallDir \"{installDir}\" -TargetVersion \"{targetVersion}\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
        }
        else
        {
            startInfo = new ProcessStartInfo
            {
                FileName = "/bin/sh",
                Arguments = $"\"{helperScriptPath}\" {Environment.ProcessId} \"{stageRoot}\" \"{installDir}\" \"{targetVersion}\"",
                UseShellExecute = false,
                CreateNoWindow = true
            };
        }

        var helperProcess = Process.Start(startInfo);

        if (helperProcess == null)
        {
            throw new InvalidOperationException("Failed to start the background updater helper process.");
        }
    }

    internal static string BuildWindowsUpdateHelperScript() => @"
param(
    [int]$ParentPid,
    [string]$StageRoot,
    [string]$InstallDir,
    [string]$TargetVersion = ''
)

$logFile = Join-Path $StageRoot 'update-log.txt'

function Write-Log {
    param([string]$Message)
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    ""$ts  $Message"" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

try {
    Write-Log 'Update helper started'

    try {
        Wait-Process -Id $ParentPid -ErrorAction SilentlyContinue
    } catch { }

    Start-Sleep -Milliseconds 750

    $payloadDir = Join-Path $StageRoot 'payload'
    if (-not (Test-Path -LiteralPath $payloadDir)) {
        throw ""Update payload directory not found: $payloadDir""
    }

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    Get-ChildItem -LiteralPath $payloadDir -Force | ForEach-Object {
        $destination = Join-Path $InstallDir $_.Name
        Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force -ErrorAction Stop
        Write-Log ""Copied: $($_.Name)""
    }

    if (-not [string]::IsNullOrWhiteSpace($TargetVersion))
    {
        $versionFile = Join-Path $InstallDir 'version.txt'
        Set-Content -LiteralPath $versionFile -Value $TargetVersion -Encoding UTF8 -NoNewline
        Write-Log ""Wrote version.txt: $TargetVersion""
    }

    Write-Log 'Update complete'
    Remove-Item -LiteralPath $StageRoot -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Log ""Error: $_""
}
";

    internal static string BuildUnixUpdateHelperScript() => """
#!/bin/sh
PARENT_PID="$1"
STAGE_ROOT="$2"
INSTALL_DIR="$3"
TARGET_VERSION="$4"

LOG_FILE="$STAGE_ROOT/update-log.txt"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S')  $1" >> "$LOG_FILE" 2>/dev/null
}

log 'Update helper started'

case "$PARENT_PID" in
    ''|*[!0-9]*)
        PARENT_PID=0
        ;;
esac

if [ "$PARENT_PID" -gt 0 ] 2>/dev/null; then
    while kill -0 "$PARENT_PID" 2>/dev/null; do
        sleep 1
    done
fi

PAYLOAD_DIR="$STAGE_ROOT/payload"
if [ ! -d "$PAYLOAD_DIR" ]; then
    log "Error: payload directory not found: $PAYLOAD_DIR"
    exit 1
fi

mkdir -p "$INSTALL_DIR"
if ! cp -R "$PAYLOAD_DIR"/. "$INSTALL_DIR"/; then
    log 'Error: cp failed'
    exit 1
fi
log 'Files copied'

if [ -f "$INSTALL_DIR/felix" ]; then
    chmod +x "$INSTALL_DIR/felix"
fi

if [ -n "$TARGET_VERSION" ]; then
    printf '%s' "$TARGET_VERSION" > "$INSTALL_DIR/version.txt"
    log "Wrote version.txt: $TARGET_VERSION"
fi

log 'Update complete'
rm -rf "$STAGE_ROOT"
""";

    static Command CreateInstallCommand()
    {
        var forceOpt = new Option<bool>("--force", "Re-extract scripts even if version matches");
        var cmd = new Command("install", "Install Felix CLI to user directory and add to PATH")
        {
            forceOpt
        };
        cmd.IsHidden = true;

        cmd.SetHandler((bool force) =>
        {
            var installDir = GetInstallDirectory();

            AnsiConsole.MarkupLine("[cyan]Felix CLI Installer[/]");
            AnsiConsole.MarkupLine("[grey]------------------------------[/]");

            var embeddedVersion = ReadEmbeddedVersion();
            var versionFile = Path.Combine(installDir, "version.txt");
            var installedVersion = File.Exists(versionFile) ? File.ReadAllText(versionFile).Trim() : null;

            if (!force && installedVersion == embeddedVersion)
            {
                AnsiConsole.MarkupLine($"[green]Already installed:[/] Felix {embeddedVersion} at [grey]{installDir}[/]");
            }
            else
            {
                var action = installedVersion == null ? "Installing" : $"Upgrading {installedVersion} ->";
                AnsiConsole.MarkupLine($"[yellow]{action} Felix {embeddedVersion}[/] -> [grey]{installDir}[/]");

                Directory.CreateDirectory(installDir);
                ExtractEmbeddedScripts(installDir);

                var selfPath = Environment.ProcessPath ?? Process.GetCurrentProcess().MainModule!.FileName;
                var destExeName = OperatingSystem.IsWindows() ? "felix.exe" : "felix";
                var destExe = Path.Combine(installDir, destExeName);
                File.Copy(selfPath!, destExe, overwrite: true);

                if (!OperatingSystem.IsWindows())
                {
                    try { Process.Start("chmod", $"+x \"{destExe}\"")?.WaitForExit(); } catch { }
                }

                AnsiConsole.MarkupLine("[green]✓[/] Scripts and felix extracted");
            }

            if (OperatingSystem.IsWindows())
            {
                var userPath = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.User) ?? string.Empty;
                var segments = userPath.Split(';', StringSplitOptions.RemoveEmptyEntries);
                if (!segments.Any(s => string.Equals(s.Trim(), installDir, StringComparison.OrdinalIgnoreCase)))
                {
                    Environment.SetEnvironmentVariable("Path", $"{userPath};{installDir}", EnvironmentVariableTarget.User);
                    AnsiConsole.MarkupLine($"[green]✓[/] Added [grey]{installDir}[/] to User PATH");
                }
                else
                {
                    AnsiConsole.MarkupLine("[green]✓[/] Already in PATH");
                }
            }
            else
            {
                var exportLine = $"export PATH=\"$PATH:{installDir}\"";
                var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                var profiles = new[] { ".bashrc", ".zshrc", ".profile" };
                var updated = new List<string>();

                foreach (var profile in profiles)
                {
                    var profilePath = Path.Combine(home, profile);
                    if (!File.Exists(profilePath)) continue;
                    var content = File.ReadAllText(profilePath);
                    if (content.Contains(installDir)) continue;
                    File.AppendAllText(profilePath, $"\n# Felix CLI\n{exportLine}\n");
                    updated.Add(profile);
                }

                if (updated.Count > 0)
                    AnsiConsole.MarkupLine($"[green]✓[/] PATH added to: [grey]{string.Join(", ", updated.Select(profile => "~/" + profile))}[/]");
                else
                    AnsiConsole.MarkupLine("[green]✓[/] Already in PATH");
            }

            AnsiConsole.WriteLine();
            AnsiConsole.MarkupLine("[green]Installation complete![/]");
            AnsiConsole.MarkupLine("  1. [yellow]Restart your terminal[/] (or [grey]source ~/.zshrc[/] on macOS/Linux)");
            AnsiConsole.MarkupLine("  2. In a project directory, run: [cyan]felix setup[/]");
        }, forceOpt);

        return cmd;
    }

    static string ReadEmbeddedVersion()
    {
        var asm = typeof(Program).Assembly;
        using var zip = new ZipArchive(asm.GetManifestResourceStream("felix-scripts.zip")
            ?? throw new Exception("Embedded felix-scripts.zip not found"), ZipArchiveMode.Read);
        var entry = zip.GetEntry("version.txt");
        if (entry == null) return "unknown";
        using var reader = new StreamReader(entry.Open());
        return reader.ReadToEnd().Trim();
    }

    static void ExtractEmbeddedScripts(string installDir)
    {
        var asm = typeof(Program).Assembly;
        using var zip = new ZipArchive(asm.GetManifestResourceStream("felix-scripts.zip")
            ?? throw new Exception("Embedded felix-scripts.zip not found"), ZipArchiveMode.Read);

        var count = 0;
        foreach (var entry in zip.Entries)
        {
            if (string.IsNullOrEmpty(entry.Name)) continue;

            var destPath = Path.GetFullPath(Path.Combine(installDir, entry.FullName));
            if (!destPath.StartsWith(installDir + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                continue;

            Directory.CreateDirectory(Path.GetDirectoryName(destPath)!);
            using var src = entry.Open();
            using var dst = File.Create(destPath);
            src.CopyTo(dst);
            count++;
        }

        AnsiConsole.MarkupLine($"[grey]  Extracted {count} files[/]");
    }
}
