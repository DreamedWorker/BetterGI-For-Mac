using System;
using System.IO;
using System.Linq;
using System.Threading;
using BetterGI.Mac.Platform;
using OpenCvSharp;

namespace BetterGI.Mac;

/// <summary>
/// Headless checks: <c>BetterGI --selftest [--window &lt;id&gt;] [--out &lt;png&gt;]</c>.
/// Prints permissions and the window list and, when a window id is given, captures one frame of it
/// to a PNG. Sends no input. The upstream core has its own check: <c>--coretest</c>.
/// </summary>
internal static class SelfTest
{
    public static int Run(string[] args)
    {
        var failures = 0;
        Console.WriteLine($"Screen Recording permission : {(MacPermissions.HasScreenCapture ? "granted" : "NOT granted")}");
        Console.WriteLine($"Accessibility permission    : {(MacPermissions.HasAccessibility ? "granted" : "NOT granted")}");

        Console.WriteLine("\nWindows (likely game first):");
        var windows = MacWindows.List();
        foreach (var window in windows)
        {
            var bar = MacWindows.GuessTitleBarHeight(window.Width, window.Height);
            Console.WriteLine($"  {(window.LooksLikeGame ? "*" : " ")} {window.Id,6}  {window.DisplayName}  [{window.Details}]  title bar {bar:0}pt");
        }

        var windowArg = ValueOf(args, "--window");
        if (windowArg != null)
        {
            failures += CaptureOnce(uint.Parse(windowArg), ValueOf(args, "--out") ?? "bgi-selftest.png");
        }

        Console.WriteLine(failures == 0 ? "\nSELFTEST OK" : $"\nSELFTEST FAILED ({failures})");
        return failures == 0 ? 0 : 1;
    }

    private static string? ValueOf(string[] args, string name)
    {
        var index = Array.IndexOf(args, name);
        return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
    }

    private static int CaptureOnce(uint windowId, string output)
    {
        Console.WriteLine($"\nCapturing window {windowId}:");
        using var capture = new MacGameCapture();
        try
        {
            capture.Start((nint)windowId);
        }
        catch (Exception e)
        {
            Console.WriteLine("  " + e.Message);
            return 1;
        }

        for (var attempt = 0; attempt < 60; attempt++)
        {
            Thread.Sleep(50);
            using var frame = capture.Capture();
            if (frame is null)
            {
                continue;
            }

            Cv2.ImWrite(output, frame.Frame);
            var area = capture.GameAreaPoints;
            Console.WriteLine($"  frame {frame.Frame.Width}x{frame.Frame.Height} px, title bar {capture.TitleBarPoints:0}pt, " +
                              $"game area {area.Width:0}x{area.Height:0} pt at ({area.X:0},{area.Y:0}) -> {Path.GetFullPath(output)}");
            return 0;
        }

        Console.WriteLine("  no frame within 3 s. " + MacGameCapture.LastError);
        return 1;
    }
}
