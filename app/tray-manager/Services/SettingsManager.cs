using System;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using FelixTrayManager.Models;

namespace FelixTrayManager.Services;

/// <summary>
/// Manages loading, saving, and validating application settings
/// </summary>
public class SettingsManager
{
    private readonly string _settingsFilePath;
    private readonly JsonSerializerOptions _jsonOptions;

    /// <summary>
    /// Current application settings
    /// </summary>
    public AppSettings Settings { get; private set; }

    /// <summary>
    /// Event raised when settings are changed
    /// </summary>
    public event EventHandler? SettingsChanged;

    public SettingsManager()
    {
        // Settings file path relative to executable
        var appDirectory = AppDomain.CurrentDomain.BaseDirectory;
        _settingsFilePath = Path.Combine(appDirectory, "settings.json");

        _jsonOptions = new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };

        // Load settings or create default
        Settings = LoadSettings();
    }

    /// <summary>
    /// Loads settings from disk. If file doesn't exist or is invalid, returns default settings.
    /// Automatically migrates legacy settings to new format.
    /// </summary>
    public AppSettings LoadSettings()
    {
        try
        {
            if (!File.Exists(_settingsFilePath))
            {
                var defaultSettings = AppSettings.CreateDefault();
                SaveSettings(defaultSettings);
                return defaultSettings;
            }

            var json = File.ReadAllText(_settingsFilePath);
            var settings = JsonSerializer.Deserialize<AppSettings>(json, _jsonOptions);

            if (settings == null)
            {
                throw new JsonException("Deserialized settings are null");
            }

            // Migrate legacy settings if needed
            if (settings.IsLegacyMode())
            {
                System.Diagnostics.Debug.WriteLine("Migrating legacy settings to agent-based configuration...");
                settings.MigrateLegacySettings();
                SaveSettings(settings);
                System.Diagnostics.Debug.WriteLine("Migration completed successfully.");
            }

            return settings;
        }
        catch (Exception ex)
        {
            // Log error and return default settings
            System.Diagnostics.Debug.WriteLine($"Error loading settings: {ex.Message}");
            return AppSettings.CreateDefault();
        }
    }

    /// <summary>
    /// Saves the provided settings to disk and updates the current settings
    /// </summary>
    public void SaveSettings(AppSettings settings)
    {
        try
        {
            var json = JsonSerializer.Serialize(settings, _jsonOptions);
            
            // Ensure directory exists
            var directory = Path.GetDirectoryName(_settingsFilePath);
            if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
            {
                Directory.CreateDirectory(directory);
            }

            File.WriteAllText(_settingsFilePath, json);
            Settings = settings;

            // Notify subscribers of settings change
            SettingsChanged?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception ex)
        {
            // Log error
            System.Diagnostics.Debug.WriteLine($"Error saving settings: {ex.Message}");
            throw;
        }
    }

    /// <summary>
    /// Updates settings with new values and saves to disk
    /// </summary>
    public void UpdateSettings(Action<AppSettings> updateAction)
    {
        updateAction(Settings);
        SaveSettings(Settings);
    }

    /// <summary>
    /// Validates that the current settings are correct
    /// </summary>
    public bool ValidateSettings()
    {
        return Settings.IsValid();
    }

    /// <summary>
    /// Gets the full path to the settings file
    /// </summary>
    public string GetSettingsFilePath()
    {
        return _settingsFilePath;
    }

    /// <summary>
    /// Resets settings to default values
    /// </summary>
    public void ResetToDefaults()
    {
        SaveSettings(AppSettings.CreateDefault());
    }

    /// <summary>
    /// Tests connection to the backend server endpoint
    /// </summary>
    /// <param name="serverEndpoint">Backend server URL to test</param>
    /// <returns>Tuple with success status and result message</returns>
    public async Task<(bool Success, string Message)> TestConnectionAsync(string serverEndpoint)
    {
        if (string.IsNullOrWhiteSpace(serverEndpoint))
        {
            return (false, "Server endpoint URL is required");
        }

        // Validate URL format
        if (!Uri.TryCreate(serverEndpoint, UriKind.Absolute, out var uri))
        {
            return (false, "Invalid URL format");
        }

        try
        {
            using var httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
            var healthUrl = $"{serverEndpoint.TrimEnd('/')}/health";
            
            var response = await httpClient.GetAsync(healthUrl);
            
            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                
                // Try to extract version if available
                try
                {
                    var healthData = JsonSerializer.Deserialize<JsonElement>(content);
                    if (healthData.TryGetProperty("version", out var version))
                    {
                        return (true, $"✅ Connected to Felix backend v{version}");
                    }
                }
                catch
                {
                    // Version not available, just report success
                }
                
                return (true, "✅ Connected to Felix backend");
            }
            else
            {
                return (false, $"❌ Server responded with status code: {(int)response.StatusCode}");
            }
        }
        catch (HttpRequestException ex)
        {
            return (false, $"❌ Cannot connect to {serverEndpoint}: {ex.Message}");
        }
        catch (TaskCanceledException)
        {
            return (false, $"❌ Connection timeout after 5 seconds");
        }
        catch (Exception ex)
        {
            return (false, $"❌ Error: {ex.Message}");
        }
    }
}
