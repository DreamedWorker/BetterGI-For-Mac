using System.Diagnostics;

namespace BetterGI.Mac.Platform;

/// <summary>
/// macOS privacy permissions BetterGI needs: Screen Recording (capture, window titles)
/// and Accessibility (posting keyboard / mouse events).
/// </summary>
public static class MacPermissions
{
    public static bool HasScreenCapture => MacNative.bgi_has_screen_capture_access() != 0;

    public static bool HasAccessibility => MacNative.bgi_has_accessibility_access(0) != 0;

    /// <summary>Shows the system Screen Recording prompt (macOS shows it only once per app).</summary>
    public static bool RequestScreenCapture() => MacNative.bgi_request_screen_capture_access() != 0;

    /// <summary>Shows the system Accessibility prompt.</summary>
    public static bool RequestAccessibility() => MacNative.bgi_has_accessibility_access(1) != 0;

    public static void OpenScreenCaptureSettings() =>
        OpenUrl("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture");

    public static void OpenAccessibilitySettings() =>
        OpenUrl("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility");

    private static void OpenUrl(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo("/usr/bin/open", url) { UseShellExecute = false });
        }
        catch
        {
            // opening System Settings is a convenience only
        }
    }
}
