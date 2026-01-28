using System;
using System.IO;
using System.Text.Json.Serialization;

namespace FelixTrayManager.Models;

/// <summary>
/// Configuration for a Felix agent instance
/// </summary>
public class AgentConfig
{
    /// <summary>
    /// Unique identifier for this agent (GUID)
    /// </summary>
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    /// <summary>
    /// Unique name (auto-generated from computer name)
    /// </summary>
    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// User-friendly display name (editable)
    /// </summary>
    [JsonPropertyName("displayName")]
    public string DisplayName { get; set; } = string.Empty;

    /// <summary>
    /// Full path to felix-agent.ps1 script
    /// </summary>
    [JsonPropertyName("agentPath")]
    public string AgentPath { get; set; } = string.Empty;

    /// <summary>
    /// Project path (root directory containing felix/ folder)
    /// </summary>
    [JsonPropertyName("projectPath")]
    public string ProjectPath { get; set; } = string.Empty;

    /// <summary>
    /// Whether this agent is enabled
    /// </summary>
    [JsonPropertyName("enabled")]
    public bool Enabled { get; set; } = true;

    /// <summary>
    /// Location type: "local" or "remote"
    /// </summary>
    [JsonPropertyName("locationType")]
    public string LocationType { get; set; } = "local";

    /// <summary>
    /// Creates a default agent configuration with auto-generated name
    /// </summary>
    public static AgentConfig CreateDefault(string agentPath)
    {
        var computerName = Environment.MachineName;
        var projectPath = Path.GetDirectoryName(agentPath) ?? string.Empty;
        
        return new AgentConfig
        {
            Id = Guid.NewGuid().ToString(),
            Name = computerName,
            DisplayName = computerName,
            AgentPath = agentPath,
            ProjectPath = projectPath,
            Enabled = true,
            LocationType = "local"
        };
    }

    /// <summary>
    /// Validates that the agent configuration is valid
    /// </summary>
    public bool IsValid()
    {
        if (string.IsNullOrWhiteSpace(AgentPath))
            return false;

        if (!File.Exists(AgentPath))
            return false;

        // Verify it's a felix-agent.ps1 file
        var fileName = Path.GetFileName(AgentPath);
        if (!fileName.Equals("felix-agent.ps1", StringComparison.OrdinalIgnoreCase))
            return false;

        // Validate project path exists
        if (string.IsNullOrWhiteSpace(ProjectPath))
            return false;

        if (!Directory.Exists(ProjectPath))
            return false;

        return true;
    }

    /// <summary>
    /// Gets the project path (backward compatibility helper)
    /// </summary>
    public string GetProjectPath()
    {
        return ProjectPath;
    }
}
