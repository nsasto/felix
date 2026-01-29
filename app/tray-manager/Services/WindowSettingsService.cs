using System;
using System.IO;
using System.Text.Json;

namespace FelixTrayApp.Services;

public class WindowSettings
{
    public double Width { get; set; } = 1100;
    public double Height { get; set; } = 700;
    public double Left { get; set; } = double.NaN;
    public double Top { get; set; } = double.NaN;
    public bool IsMaximized { get; set; } = false;
    public double RunHistorySplitterPosition { get; set; } = 300;
    
    // DataGrid column widths
    public double AgentNameColumnWidth { get; set; } = double.NaN;
    public double AgentStatusColumnWidth { get; set; } = 120;
    public double AgentLastRunColumnWidth { get; set; } = 160;
    public double AgentLastFeatureColumnWidth { get; set; } = 250;
    public double AgentOperationsColumnWidth { get; set; } = 250;
}

public class WindowSettingsService
{
    private readonly string _settingsFilePath;
    private readonly JsonSerializerOptions _jsonOptions;

    public WindowSettingsService()
    {
        var appDataFolder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "FelixTrayApp");
        
        Directory.CreateDirectory(appDataFolder);
        _settingsFilePath = Path.Combine(appDataFolder, "window-settings.json");

        _jsonOptions = new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNameCaseInsensitive = true
        };
    }

    public WindowSettings LoadSettings()
    {
        try
        {
            if (!File.Exists(_settingsFilePath))
            {
                return new WindowSettings();
            }

            var json = File.ReadAllText(_settingsFilePath);
            return JsonSerializer.Deserialize<WindowSettings>(json, _jsonOptions) 
                   ?? new WindowSettings();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error loading window settings: {ex.Message}");
            return new WindowSettings();
        }
    }

    public void SaveSettings(WindowSettings settings)
    {
        try
        {
            var json = JsonSerializer.Serialize(settings, _jsonOptions);
            File.WriteAllText(_settingsFilePath, json);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Error saving window settings: {ex.Message}");
        }
    }
}
