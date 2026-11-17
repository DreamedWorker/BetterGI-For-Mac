using Vanara.PInvoke;

namespace BetterGI.Mac.Platform;

/// <summary>
/// Translates Windows virtual-key codes (what all of upstream's task code speaks) to macOS virtual key
/// codes (ANSI layout). Wine translates them back to the same Windows keys for the game.
/// Windows Ctrl -> Control, Alt -> Option, Win -> Command, matching Wine's default modifier mapping.
/// The table itself lives in the native library (Win32Compat.swift) so both sides share it.
/// </summary>
public static class MacKeyMap
{
    /// <summary>Returns false for keys with no macOS equivalent (and for the mouse-button VKs).</summary>
    public static bool TryGetMacKeyCode(User32.VK key, out ushort macKeyCode)
    {
        var code = MacNative.bgi_vk_to_keycode((int)key);
        macKeyCode = code < 0 ? (ushort)0 : (ushort)code;
        return code >= 0;
    }

    /// <summary>Mouse button index used by the native layer for the mouse-button VKs, or -1.</summary>
    public static int ToMouseButton(User32.VK key) => (int)key switch
    {
        0x01 => 0, // VK_LBUTTON
        0x02 => 1, // VK_RBUTTON
        0x04 => 2, // VK_MBUTTON
        0x05 => 3, // VK_XBUTTON1
        0x06 => 4, // VK_XBUTTON2
        _ => -1,
    };
}
