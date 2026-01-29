using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using FelixTrayApp.ViewModels;

namespace FelixTrayApp.Services;

public class AgentStorageService
{
    private readonly string _storageFilePath;
    private readonly JsonSerializerOptions _jsonOptions;

    public AgentStorageService()
    {
        var appDataFolder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "FelixTrayApp");
        
        Directory.CreateDirectory(appDataFolder);
        _storageFilePath = Path.Combine(appDataFolder, "agents.json");

        _jsonOptions = new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNameCaseInsensitive = true
        };
    }

    public List<AgentItem> LoadAgents()
    {
        try
        {
            if (!File.Exists(_storageFilePath))
            {
                return new List<AgentItem>();
            }

            var json = File.ReadAllText(_storageFilePath);
            return JsonSerializer.Deserialize<List<AgentItem>>(json, _jsonOptions) 
                   ?? new List<AgentItem>();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error loading agents: {ex.Message}");
            return new List<AgentItem>();
        }
    }

    public void SaveAgents(IEnumerable<AgentItem> agents)
    {
        try
        {
            var json = JsonSerializer.Serialize(agents, _jsonOptions);
            File.WriteAllText(_storageFilePath, json);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error saving agents: {ex.Message}");
        }
    }
}
