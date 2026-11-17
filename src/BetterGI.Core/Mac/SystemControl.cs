using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using BetterGenshinImpact.GameTask.Runtime;
using BetterGenshinImpact.GameTask.Runtime.Win32;
using BetterGI.Mac.Platform;
using Vanara.PInvoke;

namespace BetterGenshinImpact.GameTask;

/// <summary>
/// macOS counterpart of upstream's SystemControl (a static collection of Win32 window functions with
/// 500+ call sites). Same member names and meaning; every "hWnd" is a macOS window number (CGWindowID).
/// <para>
/// Coordinates returned here are "desktop pixels": global points multiplied by the scale of the game's
/// display, so they have the same size as captured frames, as upstream assumes on Windows.
/// </para>
/// </summary>
public static class SystemControl
{
    public static List<string> GetGenshinGameProcessNameList(IGameWindow? boundWindow)
    {
        if (boundWindow is Win32GameWindow window)
        {
            return [window.ProcessName];
        }

        // Under Wine the process is not YuanShen.exe; the manually selected window decides.
        var names = new List<string> { "YuanShen", "GenshinImpact" };
        var selected = MacGameWindowSelection.Selected;
        if (selected != null && GetProcessByHandle((nint)selected.Id) is { } process)
        {
            names.Insert(0, process.ProcessName);
        }

        return names;
    }

    /// <summary>The window picked by the user, otherwise the best guess; 0 when there is none.</summary>
    public static nint FindGenshinImpactHandle() => (nint)MacGameWindowSelection.ResolveWindowId();

    /// <summary>Starting the game is Yaagl's job on macOS; BetterGI does not launch it.</summary>
    public static Task<nint> StartFromLocalAsync(string path) => Task.FromResult((nint)0);

    public static string GetActiveByProcess() => GetActiveProcessName() ?? "Unknown";

    public static bool IsGameForeground(IGameWindow? window)
    {
        if (window is not null)
        {
            return window.IsForeground;
        }

        var handle = FindGenshinImpactHandle();
        return handle != 0 && MacWindows.IsFrontmost((uint)handle);
    }

    public static nint GetForegroundWindowHandle() => (nint)MacWindows.Frontmost().WindowId;

    public static string? GetActiveProcessName()
    {
        try
        {
            var pid = MacWindows.Frontmost().ProcessId;
            return pid == 0 ? null : Process.GetProcessById(pid).ProcessName;
        }
        catch
        {
            return null;
        }
    }

    public static Process? GetProcessByHandle(nint hWnd)
    {
        try
        {
            var info = MacWindows.Query(new MacWindowInfo { Id = (uint)hWnd });
            return info is null ? null : Process.GetProcessById(info.ProcessId);
        }
        catch (Exception e)
        {
            Debug.WriteLine($"GetProcessByHandle: {e.Message}");
            return null;
        }
    }

    /// <summary>Whole window (title bar included) in desktop pixels.</summary>
    public static RECT GetWindowRect(nint hWnd)
    {
        var info = MacWindows.Query(new MacWindowInfo { Id = (uint)hWnd });
        return info is null ? default : ToPixels(info.X, info.Y, info.Width, info.Height, info.Scale);
    }

    /// <summary>Game picture with its origin at zero (the Win32 client rect).</summary>
    public static RECT GetGameScreenRect(nint hWnd)
    {
        var capture = GetCaptureRect(hWnd);
        return new RECT(0, 0, capture.Width, capture.Height);
    }

    /// <summary>Game picture (window minus title bar) in desktop pixels; same size as captured frames.</summary>
    public static RECT GetCaptureRect(nint hWnd)
    {
        var area = MacGameWindowSelection.GameArea((uint)hWnd);
        return area is null ? default : ToPixels(area.Value.X, area.Value.Y, area.Value.Width, area.Value.Height, area.Value.Scale);
    }

    private static RECT ToPixels(double x, double y, double width, double height, double scale)
    {
        var left = (int)Math.Round(x * scale);
        var top = (int)Math.Round(y * scale);
        return new RECT(left, top, left + (int)Math.Round(width * scale), top + (int)Math.Round(height * scale));
    }

    public static void ActivateWindow(nint hWnd) => MacWindows.Activate((uint)hWnd);

    public static void FocusWindow(nint hWnd) => MacWindows.Activate((uint)hWnd);

    public static void MinimizeAndActivateWindow(nint hWnd)
    {
        MacWindows.SetMinimized((uint)hWnd, true);
        MacWindows.SetMinimized((uint)hWnd, false);
        MacWindows.Activate((uint)hWnd);
    }

    public static void RestoreWindow(nint hWnd)
    {
        MacWindows.SetMinimized((uint)hWnd, false);
        MacWindows.Activate((uint)hWnd);
    }

    /// <summary>True when the window covers a whole display (no title bar detected and same size as a screen).</summary>
    public static bool IsFullScreenMode(IntPtr hWnd)
    {
        var info = MacWindows.Query(new MacWindowInfo { Id = (uint)hWnd });
        if (info is null)
        {
            return false;
        }

        var (width, height) = MacDisplays.MainSize;
        return Math.Abs(info.Width - width) < 1 && Math.Abs(info.Height - height) < 1;
    }

    public static void CloseGame()
    {
        var service = App.GetService<GameRuntimeService>();
        if (service != null)
        {
            service.CloseGame();
        }
        else
        {
            CloseGameProcesses(null);
        }
    }

    /// <summary>Ends the process that owns the game window (the Wine process running the game).</summary>
    public static void CloseGameProcesses(IGameWindow? boundWindow)
    {
        try
        {
            var handle = boundWindow?.Handle ?? FindGenshinImpactHandle();
            using var process = handle == 0 ? null : GetProcessByHandle(handle);
            process?.Kill();
        }
        catch (Exception e)
        {
            Debug.WriteLine($"CloseGameProcesses: {e.Message}");
        }
    }

    public static void Shutdown()
    {
        try
        {
            Process.Start("/usr/bin/osascript", ["-e", "tell application \"System Events\" to shut down"]);
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Shutdown: {e.Message}");
        }
    }
}
