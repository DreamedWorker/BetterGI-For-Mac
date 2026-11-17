using System.Diagnostics;

namespace BetterGI.Mac.Platform;

/// <summary>
/// Display geometry in global points.
/// </summary>
public static class MacDisplays
{
    /// <summary>Size of the main display (the one holding the global origin).</summary>
    public static (double Width, double Height) MainSize
    {
        get
        {
            MacNative.bgi_main_display_size(out var width, out var height);
            return (width, height);
        }
    }

    /// <summary>Bounding box of all displays.</summary>
    public static (double X, double Y, double Width, double Height) VirtualDesktop
    {
        get
        {
            MacNative.bgi_virtual_desktop_bounds(out var x, out var y, out var width, out var height);
            return (x, y, width, height);
        }
    }
}

/// <summary>
/// Plain-text clipboard through the system pbcopy / pbpaste tools.
/// </summary>
public static class MacClipboard
{
    public static void SetText(string text)
    {
        using var process = Process.Start(new ProcessStartInfo("/usr/bin/pbcopy")
        {
            RedirectStandardInput = true,
            UseShellExecute = false,
        });
        if (process is null)
        {
            return;
        }

        process.StandardInput.Write(text);
        process.StandardInput.Close();
        process.WaitForExit(2000);
    }

    public static string GetText()
    {
        using var process = Process.Start(new ProcessStartInfo("/usr/bin/pbpaste")
        {
            RedirectStandardOutput = true,
            UseShellExecute = false,
        });
        if (process is null)
        {
            return string.Empty;
        }

        var text = process.StandardOutput.ReadToEnd();
        process.WaitForExit(2000);
        return text;
    }
}
