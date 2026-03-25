using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Spectre.Console;

namespace Felix.Cli;

partial class Program
{
    static string? GetJsonString(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) || value.ValueKind == JsonValueKind.Null)
            return null;

        return value.ValueKind switch
        {
            JsonValueKind.String => value.GetString(),
            JsonValueKind.Number => value.ToString(),
            JsonValueKind.True => bool.TrueString,
            JsonValueKind.False => bool.FalseString,
            _ => value.ToString()
        };
    }

    static string? GetJsonString(JsonObject obj, string propertyName)
    {
        var value = obj[propertyName];
        return value switch
        {
            null => null,
            JsonValue jsonValue when jsonValue.TryGetValue<string>(out var stringValue) => stringValue,
            JsonValue jsonValue when jsonValue.TryGetValue<int>(out var intValue) => intValue.ToString(),
            JsonValue jsonValue when jsonValue.TryGetValue<long>(out var longValue) => longValue.ToString(),
            JsonValue jsonValue when jsonValue.TryGetValue<double>(out var doubleValue) => doubleValue.ToString(),
            JsonValue jsonValue when jsonValue.TryGetValue<bool>(out var boolValue) => boolValue ? bool.TrueString : bool.FalseString,
            _ => value.ToJsonString().Trim('"')
        };
    }

    static int? GetJsonInt(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) || value.ValueKind != JsonValueKind.Number)
            return null;

        return value.TryGetInt32(out var number) ? number : null;
    }

    static int? GetJsonInt(JsonObject obj, string propertyName)
    {
        var value = obj[propertyName];
        if (value is JsonValue jsonValue && jsonValue.TryGetValue<int>(out var intValue))
            return intValue;

        return null;
    }

    static double? GetJsonDouble(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value) || value.ValueKind != JsonValueKind.Number)
            return null;

        return value.TryGetDouble(out var number) ? number : null;
    }

    static bool? GetJsonBool(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value))
            return null;

        return value.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => null
        };
    }

    static bool TryExtractJsonResponse(string content, out JsonElement payload, out bool hadEnvelopeText)
    {
        payload = default;
        hadEnvelopeText = false;

        content ??= string.Empty;
        var trimmed = content.Trim();
        if (trimmed.Length == 0)
            return false;

        if (TryParseJsonPayload(trimmed, out payload))
            return true;

        var fenceMatch = Regex.Match(content, "```json\\s*(\\{.*?\\})\\s*```", RegexOptions.IgnoreCase | RegexOptions.Singleline);
        if (fenceMatch.Success)
        {
            hadEnvelopeText = true;
            if (TryParseJsonPayload(fenceMatch.Groups[1].Value, out payload))
                return true;
        }

        var firstBrace = content.IndexOf('{');
        var lastBrace = content.LastIndexOf('}');
        if (firstBrace >= 0 && lastBrace > firstBrace)
        {
            hadEnvelopeText = true;
            var candidate = content.Substring(firstBrace, lastBrace - firstBrace + 1);
            if (TryParseJsonPayload(candidate, out payload))
                return true;
        }

        return false;
    }

    static bool TryParseJsonPayload(string text, out JsonElement payload)
    {
        payload = default;
        try
        {
            using var doc = JsonDocument.Parse(text);
            if (doc.RootElement.ValueKind != JsonValueKind.Object)
                return false;

            payload = doc.RootElement.Clone();
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    static void RenderResponseJsonFields(JsonElement root)
    {
        foreach (var (key, value) in FlattenJsonFields(root, null))
        {
            RenderFelixDetailLine(key, "grey", value.EscapeMarkup());
        }
    }

    static IEnumerable<(string Key, string Value)> FlattenJsonFields(JsonElement element, string? prefix)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            foreach (var prop in element.EnumerateObject())
            {
                var nextPrefix = string.IsNullOrWhiteSpace(prefix) ? prop.Name : $"{prefix}.{prop.Name}";
                foreach (var pair in FlattenJsonFields(prop.Value, nextPrefix))
                    yield return pair;
            }

            yield break;
        }

        if (element.ValueKind == JsonValueKind.Array)
        {
            var values = element.EnumerateArray().Select(v => v.ValueKind == JsonValueKind.String ? (v.GetString() ?? string.Empty) : v.ToString());
            yield return (prefix ?? "value", string.Join(", ", values));
            yield break;
        }

        var scalar = element.ValueKind switch
        {
            JsonValueKind.String => element.GetString() ?? string.Empty,
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            JsonValueKind.Null => "null",
            _ => element.ToString()
        };

        yield return (prefix ?? "value", scalar);
    }

    static string FindPowerShell()
    {
        if (OperatingSystem.IsWindows())
        {
            var pwsh7 = @"C:\Program Files\PowerShell\7\pwsh.exe";
            if (File.Exists(pwsh7)) return pwsh7;
        }

        try
        {
            var whichCmd = OperatingSystem.IsWindows() ? "where" : "which";
            var result = Process.Start(new ProcessStartInfo
            {
                FileName = whichCmd,
                Arguments = "pwsh",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                CreateNoWindow = true
            });
            if (result != null)
            {
                var path = result.StandardOutput.ReadLine()?.Trim();
                result.WaitForExit();
                if (!string.IsNullOrEmpty(path) && File.Exists(path)) return path;
            }
        }
        catch { }

        return OperatingSystem.IsWindows() ? "powershell.exe" : "pwsh";
    }

    static List<JsonElement>? ParseRequirementsJson(string output)
    {
        var trimmed = output.Trim();
        if (string.IsNullOrEmpty(trimmed) || !trimmed.StartsWith("["))
            return null;

        try { return JsonDocument.Parse(trimmed).RootElement.EnumerateArray().ToList(); }
        catch { return null; }
    }

    internal static string GetInstallDirectory()
    {
        if (OperatingSystem.IsWindows())
        {
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Programs", "Felix");
        }

        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".local", "share", "felix");
    }

    internal static string? GetInstalledVersion(string installDir)
    {
        var versionFile = Path.Combine(installDir, "version.txt");
        if (!File.Exists(versionFile)) return null;

        return File.ReadAllText(versionFile).Trim();
    }

    internal static bool EnsureWindowsInstallDirOnPath(string installDir)
    {
        var userPath = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.User) ?? string.Empty;
        var segments = userPath.Split(';', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Any(s => string.Equals(s.Trim().TrimEnd('\\'), installDir.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        var updatedPath = string.IsNullOrWhiteSpace(userPath) ? installDir : $"{userPath};{installDir}";
        Environment.SetEnvironmentVariable("Path", updatedPath, EnvironmentVariableTarget.User);
        return true;
    }

    internal static string GetCurrentReleaseRid()
    {
        if (OperatingSystem.IsWindows())
        {
            return DefaultWindowsReleaseRid;
        }

        if (OperatingSystem.IsLinux())
        {
            return RuntimeInformation.OSArchitecture == Architecture.X64
                ? "linux-x64"
                : throw new PlatformNotSupportedException($"felix update does not currently publish Linux assets for architecture '{RuntimeInformation.OSArchitecture}'.");
        }

        if (OperatingSystem.IsMacOS())
        {
            return RuntimeInformation.OSArchitecture switch
            {
                Architecture.Arm64 => "osx-arm64",
                Architecture.X64 => "osx-x64",
                _ => throw new PlatformNotSupportedException($"felix update does not currently publish macOS assets for architecture '{RuntimeInformation.OSArchitecture}'.")
            };
        }

        throw new PlatformNotSupportedException("felix update is not supported on this operating system.");
    }

    internal static string GetExecutableFileName(string? releaseRid = null)
    {
        var rid = releaseRid ?? GetCurrentReleaseRid();
        return rid.StartsWith("win-", StringComparison.OrdinalIgnoreCase) ? "felix.exe" : "felix";
    }

    internal static string NormalizeVersionString(string version)
    {
        var normalized = version.Trim();
        if (normalized.StartsWith("v", StringComparison.OrdinalIgnoreCase))
        {
            normalized = normalized.Substring(1);
        }

        var prereleaseIndex = normalized.IndexOf('-');
        if (prereleaseIndex > 0)
        {
            normalized = normalized.Substring(0, prereleaseIndex);
        }

        return normalized;
    }

    internal static int CompareVersions(string left, string right)
    {
        var normalizedLeft = NormalizeVersionString(left);
        var normalizedRight = NormalizeVersionString(right);

        if (Version.TryParse(normalizedLeft, out var leftVersion) && Version.TryParse(normalizedRight, out var rightVersion))
        {
            return leftVersion.CompareTo(rightVersion);
        }

        return string.Compare(normalizedLeft, normalizedRight, StringComparison.OrdinalIgnoreCase);
    }

    static string? ExtractApiErrorMessage(string? responseBody)
    {
        if (string.IsNullOrWhiteSpace(responseBody))
            return null;

        try
        {
            using var document = JsonDocument.Parse(responseBody);
            if (document.RootElement.ValueKind == JsonValueKind.Object)
            {
                if (document.RootElement.TryGetProperty("detail", out var detail) && detail.ValueKind == JsonValueKind.String)
                    return detail.GetString();
                if (document.RootElement.TryGetProperty("error", out var error) && error.ValueKind == JsonValueKind.String)
                    return error.GetString();
                if (document.RootElement.TryGetProperty("message", out var message) && message.ValueKind == JsonValueKind.String)
                    return message.GetString();
            }
        }
        catch
        {
        }

        return responseBody.Trim();
    }

    static string MaskApiKey(string? apiKey)
    {
        if (string.IsNullOrWhiteSpace(apiKey))
            return "(none - will attempt without key)";

        return apiKey.Length <= 12
            ? apiKey
            : apiKey[..12] + "...";
    }

    static string? ResolveAgentExecutablePath(string executable)
    {
        if (string.IsNullOrWhiteSpace(executable))
            return null;

        if (File.Exists(executable))
            return Path.GetFullPath(executable);

        var onPath = FindExecutableOnPath(executable);
        if (!string.IsNullOrWhiteSpace(onPath))
            return onPath;

        if (string.Equals(executable, "copilot", StringComparison.OrdinalIgnoreCase))
            return GetCopilotExecutableCandidates().FirstOrDefault(File.Exists);

        return null;
    }

    static string ReadRequirementsJson()
    {
        var path = Path.Combine(_felixProjectRoot, ".felix", "requirements.json");
        if (!File.Exists(path)) return "[]";
        try
        {
            var raw = File.ReadAllText(path, Encoding.UTF8).Trim();
            if (raw.StartsWith("{"))
            {
                using var doc = JsonDocument.Parse(raw);
                var root = doc.RootElement;
                foreach (var key in new[] { "requirements", "items", "data" })
                {
                    if (root.TryGetProperty(key, out var arr) && arr.ValueKind == JsonValueKind.Array)
                        return arr.GetRawText();

                    if (root.TryGetProperty(key, out var single) && single.ValueKind == JsonValueKind.Object)
                        return $"[{single.GetRawText()}]";
                }

                foreach (var prop in root.EnumerateObject())
                {
                    if (prop.Value.ValueKind == JsonValueKind.Array)
                        return prop.Value.GetRawText();

                    if (prop.Value.ValueKind == JsonValueKind.Object)
                        return $"[{prop.Value.GetRawText()}]";
                }
                return "[]";
            }

            if (raw.StartsWith("["))
                return raw;

            if (raw.StartsWith("{"))
                return $"[{raw}]";

            return raw;
        }
        catch { return "[]"; }
    }
}
