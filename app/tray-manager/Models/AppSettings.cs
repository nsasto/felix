using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Serialization;

namespace FelixTrayManager.Models;

/// <summary>
/// Application settings model for persistence to settings.json
/// </summary>
public class AppSettings
{
    /// <summary>
    /// Path to the Felix project directory (LEGACY - for backward compatibility)
    /// </summary>
    [JsonPropertyName("projectPath")]
    public string? ProjectPath { get; set; }

    /// <summary>
    /// Backend server endpoint URL (default: http://localhost:8080)
    /// </summary>
    [JsonPropertyName("serverEndpoint")]
    public string ServerEndpoint { get; set; } = "http://localhost:8080";

    /// <summary>
    /// Collection of configured Felix agents
    /// </summary>
    [JsonPropertyName("agents")]
    public List<AgentConfig> Agents { get; set; } = new();

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
    /// Creates a default settings instance with no agents
    /// </summary>
    public static AppSettings CreateDefault()
    {
        return new AppSettings
        {
            ProjectPath = null,
            ServerEndpoint = "http://localhost:8080",
            Agents = new List<AgentConfig>(),
            AutoStartOnLogin = false,
            MaxIterations = 100,
            RunInBackgroundOnClose = true
        };
    }

    /// <summary>
    /// Validates that settings are valid
    /// </summary>
    public bool IsValid()
    {
        // If using legacy mode, validate project path
        if (!string.IsNullOrWhiteSpace(ProjectPath))
        {
            if (!Directory.Exists(ProjectPath))
                return false;

            var felixDir = Path.Combine(ProjectPath, "felix");
            if (!Directory.Exists(felixDir))
                return false;
        }

        // Validate at least one enabled agent exists
        if (Agents.Count == 0 && string.IsNullOrWhiteSpace(ProjectPath))
            return false;

        return true;
    }

    /// <summary>
    /// Checks if this is using legacy single-project mode
    /// </summary>
    public bool IsLegacyMode()
    {
        return !string.IsNullOrWhiteSpace(ProjectPath) && Agents.Count == 0;
    }

    /// <summary>
    /// Migrates legacy projectPath to agent-based configuration
    /// </summary>
    public void MigrateLegacySettings()
    {
        if (!IsLegacyMode())
            return;

        // Create agent from legacy project path
        var agentPath = Path.Combine(ProjectPath!, "felix-agent.ps1");
        if (File.Exists(agentPath))
        {
            var agent = new AgentConfig
            {
                Id = Guid.NewGuid().ToString(),
                Name = Environment.MachineName,
                DisplayName = "Local Agent",
                AgentPath = agentPath,
                Enabled = true,
                LocationType = "local"
            };
            Agents.Add(agent);
        }

        // Clear legacy field
        ProjectPath = null;
    }

    /// <summary>
    /// Generates a unique agent name based on computer name and existing agents
    /// </summary>
    public string GenerateUniqueAgentName()
    {
        var baseName = Environment.MachineName;
        var existingNames = Agents.Select(a => a.Name).ToHashSet();

        if (!existingNames.Contains(baseName))
            return baseName;

        int counter = 2;
        while (existingNames.Contains($"{baseName}-{counter}"))
        {
            counter++;
        }

        return $"{baseName}-{counter}";
    }
}
