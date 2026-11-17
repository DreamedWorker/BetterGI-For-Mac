using System;
using System.IO;

namespace BetterGI.Mac;

/// <summary>
/// Minimal logger: raises an event for the UI and appends to ~/Library/Logs/BetterGI-Mac/app.log.
/// (Upstream uses Serilog; this is replaced when the upstream core is brought in.)
/// </summary>
public static class AppLog
{
    private static readonly object Sync = new();

    public static string LogFile { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Library", "Logs", "BetterGI-Mac", "app.log");

    public static event Action<string>? Line;

    public static void Info(string message) => Write("INF", message);

    public static void Warn(string message) => Write("WRN", message);

    public static void Error(string message) => Write("ERR", message);

    /// <summary>Shows an already formatted line in the UI without writing it to the app log file.</summary>
    public static void Raw(string line) => Line?.Invoke(line);

    private static void Write(string level, string message)
    {
        var line = $"{DateTime.Now:HH:mm:ss.fff} [{level}] {message}";
        lock (Sync)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(LogFile)!);
                File.AppendAllText(LogFile, line + Environment.NewLine);
            }
            catch
            {
                // logging must never take the app down
            }
        }

        Line?.Invoke(line);
    }
}
