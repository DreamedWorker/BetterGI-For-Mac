using System;
using System.Runtime.InteropServices;

namespace BetterGI.Mac.Platform;

/// <summary>
/// P/Invoke surface of libBgiMacNative.dylib (native/BgiMacNative/BgiMacNative.swift).
/// Window and mouse coordinates are global display points; frames are pixels.
/// </summary>
internal static partial class MacNative
{
    private const string Lib = "libBgiMacNative";

    [LibraryImport(Lib)] internal static partial void bgi_free(nint ptr);

    // permissions
    [LibraryImport(Lib)] internal static partial int bgi_has_screen_capture_access();
    [LibraryImport(Lib)] internal static partial int bgi_request_screen_capture_access();
    [LibraryImport(Lib)] internal static partial int bgi_has_accessibility_access(int prompt);

    // windows
    [LibraryImport(Lib)] internal static partial nint bgi_list_windows(int includeOffScreen);
    [LibraryImport(Lib)]
    internal static partial int bgi_window_info(uint windowId, out double x, out double y, out double width,
        out double height, out double scale, out int pid, out int onScreen);
    [LibraryImport(Lib)] internal static partial int bgi_window_is_frontmost(uint windowId);
    [LibraryImport(Lib)] internal static partial int bgi_window_activate(uint windowId);

    [LibraryImport(Lib)] internal static partial uint bgi_frontmost_window(out int pid);
    [LibraryImport(Lib)] internal static partial int bgi_window_set_minimized(uint windowId, int minimized);

    // keychain
    [LibraryImport(Lib, StringMarshalling = StringMarshalling.Utf8)] internal static partial int bgi_keychain_set(string service, string account, string secret);
    [LibraryImport(Lib, StringMarshalling = StringMarshalling.Utf8)] internal static partial nint bgi_keychain_get(string service);
    [LibraryImport(Lib, StringMarshalling = StringMarshalling.Utf8)] internal static partial int bgi_keychain_delete(string service);

    // capture
    [LibraryImport(Lib)] internal static partial int bgi_capture_start(uint windowId, int fps);
    [LibraryImport(Lib)] internal static partial void bgi_capture_stop();
    [LibraryImport(Lib)] internal static partial int bgi_capture_is_running();
    [LibraryImport(Lib)] internal static partial int bgi_capture_resize(int pixelWidth, int pixelHeight);
    [LibraryImport(Lib)] internal static partial ulong bgi_capture_frame_size(out int width, out int height);
    [LibraryImport(Lib)]
    internal static partial ulong bgi_capture_copy_frame(nint destination, long capacity, int cropTop,
        out int width, out int height);
    [LibraryImport(Lib)] internal static partial nint bgi_capture_last_error();

    // input
    [LibraryImport(Lib)] internal static partial int bgi_key_event(ushort keyCode, int down);
    [LibraryImport(Lib)] internal static partial int bgi_key_is_down(ushort keyCode);
    [LibraryImport(Lib)] internal static partial int bgi_mouse_move_to(double x, double y);
    [LibraryImport(Lib)] internal static partial int bgi_mouse_move_by(int dx, int dy);
    [LibraryImport(Lib)] internal static partial int bgi_mouse_button(int button, int down);
    [LibraryImport(Lib)] internal static partial int bgi_mouse_scroll(int clicks);
    [LibraryImport(Lib)] internal static partial void bgi_mouse_location(out double x, out double y);
    [LibraryImport(Lib)] internal static partial void bgi_input_release_all();
    [LibraryImport(Lib, StringMarshalling = StringMarshalling.Utf16)] internal static partial int bgi_type_text(string text, int length);

    [LibraryImport(Lib)] internal static partial int bgi_vk_to_keycode(int vk);
    [LibraryImport(Lib)] internal static partial void bgi_set_desktop_scale(double scale);
    [LibraryImport(Lib)] internal static partial void bgi_set_client_top_inset(double points);

    // displays
    [LibraryImport(Lib)] internal static partial void bgi_main_display_size(out double width, out double height);
    [LibraryImport(Lib)] internal static partial void bgi_virtual_desktop_bounds(out double x, out double y, out double width, out double height);

    /// <summary>Reads and frees a UTF-8 string returned by the native library.</summary>
    internal static string TakeString(nint ptr)
    {
        if (ptr == 0)
        {
            return string.Empty;
        }

        try
        {
            return Marshal.PtrToStringUTF8(ptr) ?? string.Empty;
        }
        finally
        {
            bgi_free(ptr);
        }
    }
}
