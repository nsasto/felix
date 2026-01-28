using System;
using System.IO;
using System.Threading;

namespace FelixTrayManager.Services
{
    /// <summary>
    /// Simple file-based logger for Felix Tray Manager
    /// </summary>
    public class Logger : IDisposable
    {
        private readonly string _logFilePath;
        private readonly object _logLock = new object();
        private readonly SemaphoreSlim _writeSemaphore = new SemaphoreSlim(1, 1);
        private bool _disposed;

        /// <summary>
        /// Log levels
        /// </summary>
        public enum LogLevel
        {
            Info,
            Warning,
            Error,
            Debug
        }

        /// <summary>
        /// Creates a new logger instance
        /// </summary>
        /// <param name="logFilePath">Path to the log file (defaults to logs/TrayManager.log)</param>
        public Logger(string? logFilePath = null)
        {
            // Default log path relative to executable
            if (string.IsNullOrEmpty(logFilePath))
            {
                var appDir = AppDomain.CurrentDomain.BaseDirectory;
                var logsDir = Path.Combine(appDir, "logs");
                _logFilePath = Path.Combine(logsDir, "TrayManager.log");
            }
            else
            {
                _logFilePath = logFilePath;
            }

            // Ensure logs directory exists
            EnsureLogDirectoryExists();

            // Write startup message
            Log(LogLevel.Info, "Felix Tray Manager started");
        }

        /// <summary>
        /// Ensures the logs directory exists
        /// </summary>
        private void EnsureLogDirectoryExists()
        {
            try
            {
                var directory = Path.GetDirectoryName(_logFilePath);
                if (!string.IsNullOrEmpty(directory) && !Directory.Exists(directory))
                {
                    Directory.CreateDirectory(directory);
                }
            }
            catch (Exception ex)
            {
                // If we can't create the directory, log to console as fallback
                Console.Error.WriteLine($"Failed to create logs directory: {ex.Message}");
            }
        }

        /// <summary>
        /// Logs a message with the specified level
        /// </summary>
        /// <param name="level">Log level</param>
        /// <param name="message">Message to log</param>
        public void Log(LogLevel level, string message)
        {
            if (_disposed)
                return;

            try
            {
                _writeSemaphore.Wait();
                try
                {
                    var timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff");
                    var logEntry = $"[{timestamp}] [{level.ToString().ToUpper()}] {message}";

                    // Write to file
                    File.AppendAllText(_logFilePath, logEntry + Environment.NewLine);

                    // Also write to debug output
                    System.Diagnostics.Debug.WriteLine(logEntry);
                }
                finally
                {
                    _writeSemaphore.Release();
                }
            }
            catch (Exception ex)
            {
                // Fallback to console if file write fails
                Console.Error.WriteLine($"Logging failed: {ex.Message}");
                Console.Error.WriteLine($"Original message: [{level}] {message}");
            }
        }

        /// <summary>
        /// Logs an info message
        /// </summary>
        public void Info(string message) => Log(LogLevel.Info, message);

        /// <summary>
        /// Logs a warning message
        /// </summary>
        public void Warning(string message) => Log(LogLevel.Warning, message);

        /// <summary>
        /// Logs an error message
        /// </summary>
        public void Error(string message) => Log(LogLevel.Error, message);

        /// <summary>
        /// Logs an error message with exception details
        /// </summary>
        public void Error(string message, Exception ex)
        {
            Log(LogLevel.Error, $"{message}: {ex.GetType().Name} - {ex.Message}");
            if (ex.StackTrace != null)
            {
                Log(LogLevel.Debug, $"Stack trace: {ex.StackTrace}");
            }
        }

        /// <summary>
        /// Logs a debug message
        /// </summary>
        public void Debug(string message) => Log(LogLevel.Debug, message);

        /// <summary>
        /// Rotates the log file if it exceeds the specified size
        /// </summary>
        /// <param name="maxSizeBytes">Maximum log file size in bytes (default: 10MB)</param>
        public void RotateIfNeeded(long maxSizeBytes = 10 * 1024 * 1024)
        {
            try
            {
                if (File.Exists(_logFilePath))
                {
                    var fileInfo = new FileInfo(_logFilePath);
                    if (fileInfo.Length > maxSizeBytes)
                    {
                        // Create backup with timestamp
                        var backupPath = _logFilePath + $".{DateTime.Now:yyyyMMdd-HHmmss}.bak";
                        File.Move(_logFilePath, backupPath);
                        
                        Log(LogLevel.Info, $"Log file rotated. Backup: {Path.GetFileName(backupPath)}");

                        // Keep only last 5 backups
                        CleanupOldBackups();
                    }
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Log rotation failed: {ex.Message}");
            }
        }

        /// <summary>
        /// Removes old log backup files, keeping only the most recent ones
        /// </summary>
        private void CleanupOldBackups(int maxBackups = 5)
        {
            try
            {
                var directory = Path.GetDirectoryName(_logFilePath);
                if (string.IsNullOrEmpty(directory))
                    return;

                var logFileName = Path.GetFileName(_logFilePath);
                var backupFiles = Directory.GetFiles(directory, $"{logFileName}.*.bak");

                if (backupFiles.Length > maxBackups)
                {
                    // Sort by creation time and delete oldest
                    Array.Sort(backupFiles, (a, b) => File.GetCreationTime(a).CompareTo(File.GetCreationTime(b)));

                    for (int i = 0; i < backupFiles.Length - maxBackups; i++)
                    {
                        try
                        {
                            File.Delete(backupFiles[i]);
                            Log(LogLevel.Debug, $"Deleted old log backup: {Path.GetFileName(backupFiles[i])}");
                        }
                        catch
                        {
                            // Ignore errors when deleting old backups
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Failed to cleanup old log backups: {ex.Message}");
            }
        }

        /// <summary>
        /// Gets the current log file path
        /// </summary>
        public string LogFilePath => _logFilePath;

        /// <summary>
        /// Disposes of resources
        /// </summary>
        public void Dispose()
        {
            if (_disposed)
                return;

            Log(LogLevel.Info, "Felix Tray Manager shutting down");

            _writeSemaphore?.Dispose();
            _disposed = true;
        }
    }
}
