using System.IO;
using System.Text.Json.Serialization;

namespace FelixTrayManager.Models;

/// <summary>
/// Application settings model for persistence to settings.json
/// </summary>
public class AppSettings
{
    /// <summary>
    /// Path to the Felix project directory
    /// </summary>
    [JsonPropertyName("projectPath")]
    public string ProjectPath { get; set; } = string.Empty;

    /// <summary>
    /// Whether to automatically start the application on Windows login
    /// </summary>
    [JsonPropertyName("autoStartOnLogin")]
    public bool AutoStartOnLogin { get; set; } = false;

    /// <summary>
    /// Maximum number of iterations for Felix agent execution
    /// </summary>
    [JsonPropertyName("maxIterations")]
    public int MaxIterations { get; set; } = 100;

    /// <summary>
    /// Whether to minimize to tray instead of exiting when closing
    /// </summary>
    [JsonPropertyName("runInBackgroundOnClose")]
    public bool RunInBackgroundOnClose { get; set; } = true;

    /// <summary>
    /// Creates a default settings instance with empty project path
    /// </summary>
    public static AppSettings CreateDefault()
    {
        return new AppSettings
        {
            ProjectPath = string.Empty,
            AutoStartOnLogin = false,
            MaxIterations = 100,
            RunInBackgroundOnClose = true
        };
    }

    /// <summary>
    /// Validates that the project path exists and contains a felix/ directory
    /// </summary>
    public bool IsValid()
    {
        if (string.IsNullOrWhiteSpace(ProjectPath))
            return false;

        if (!Directory.Exists(ProjectPath))
            return false;

        // Check for felix/ directory
        var felixDir = Path.Combine(ProjectPath, "felix");
        return Directory.Exists(felixDir);
    }
}
