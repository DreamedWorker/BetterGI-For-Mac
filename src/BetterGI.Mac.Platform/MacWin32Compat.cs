using System.Reflection;
using System.Runtime.InteropServices;

namespace BetterGI.Mac.Platform;

/// <summary>
/// Redirects P/Invokes aimed at Windows system DLLs to the Win32 subset implemented in
/// libBgiMacNative (native/BgiMacNative/Win32Compat.swift), so unmodified upstream code keeps working.
/// </summary>
public static class MacWin32Compat
{
    private static readonly string[] Redirected =
        ["user32", "gdi32", "kernel32", "ntdll", "shcore", "dwmapi"];

    private static readonly HashSet<Assembly> Installed = [];

    /// <summary>
    /// Installs the redirect for each assembly that declares Win32 P/Invokes (the Vanara assemblies and
    /// upstream's own). Safe to call repeatedly.
    /// </summary>
    public static void Install(params Assembly[] assemblies)
    {
        lock (Installed)
        {
            foreach (var assembly in assemblies)
            {
                if (Installed.Add(assembly))
                {
                    NativeLibrary.SetDllImportResolver(assembly, Resolve);
                }
            }
        }
    }

    /// <summary>
    /// Tells the compatibility layer how the game is placed: the display scale (points to desktop pixels)
    /// and the title bar height above the game picture.
    /// </summary>
    public static void SetGameGeometry(double scale, double titleBarPoints)
    {
        MacNative.bgi_set_desktop_scale(scale);
        MacNative.bgi_set_client_top_inset(titleBarPoints);
    }

    private static nint Resolve(string libraryName, Assembly assembly, DllImportSearchPath? searchPath)
    {
        var name = Path.GetFileNameWithoutExtension(libraryName);
        if (Redirected.Contains(name, StringComparer.OrdinalIgnoreCase))
        {
            return NativeLibrary.Load("libBgiMacNative", typeof(MacWin32Compat).Assembly, searchPath);
        }

        return 0; // default probing
    }
}
