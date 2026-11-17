using System;
using System.Collections.Generic;
using System.Threading;
using Vanara.PInvoke;

namespace BetterGI.Mac.Platform;

/// <summary>
/// Foreground keyboard / mouse injection through CGEvent (the macOS counterpart of SendInput).
/// Method names follow upstream's IKeyboardInput / IMouseInput so that the future
/// <c>IInputBackend</c> adapter is a thin forwarder. Requires the Accessibility permission, and,
/// like SendInput, the game window must be front-most to receive the events.
/// </summary>
public sealed class MacInput
{
    /// <summary>Delay between the down and up half of a press; games polling at 30 fps miss shorter taps.</summary>
    public int PressHoldMs { get; set; } = 40;

    private readonly object _sync = new();
    private readonly HashSet<User32.VK> _pressed = [];

    /// <summary>Raised with a key that has no macOS mapping.</summary>
    public event Action<User32.VK>? UnsupportedKey;

    public MacInput KeyDown(User32.VK key)
    {
        var mouseButton = MacKeyMap.ToMouseButton(key);
        if (mouseButton >= 0)
        {
            MacNative.bgi_mouse_button(mouseButton, 1);
        }
        else if (MacKeyMap.TryGetMacKeyCode(key, out var code))
        {
            MacNative.bgi_key_event(code, 1);
        }
        else
        {
            UnsupportedKey?.Invoke(key);
            return this;
        }

        lock (_sync)
        {
            _pressed.Add(key);
        }

        return this;
    }

    public MacInput KeyUp(User32.VK key)
    {
        var mouseButton = MacKeyMap.ToMouseButton(key);
        if (mouseButton >= 0)
        {
            MacNative.bgi_mouse_button(mouseButton, 0);
        }
        else if (MacKeyMap.TryGetMacKeyCode(key, out var code))
        {
            MacNative.bgi_key_event(code, 0);
        }

        lock (_sync)
        {
            _pressed.Remove(key);
        }

        return this;
    }

    public MacInput KeyPress(User32.VK key)
    {
        KeyDown(key);
        Thread.Sleep(PressHoldMs);
        return KeyUp(key);
    }

    /// <summary>True while the key is physically or synthetically held (used for hotkey polling).</summary>
    public static bool IsKeyDown(User32.VK key) =>
        MacKeyMap.TryGetMacKeyCode(key, out var code) && MacNative.bgi_key_is_down(code) != 0;

    /// <summary>Moves the cursor to a position given in global display points.</summary>
    public MacInput MoveMouseToPoints(double x, double y)
    {
        MacNative.bgi_mouse_move_to(x, y);
        return this;
    }

    /// <summary>Relative movement (camera turning).</summary>
    public MacInput MoveMouseBy(int dx, int dy)
    {
        MacNative.bgi_mouse_move_by(dx, dy);
        return this;
    }

    public MacInput MouseButton(int button, bool down)
    {
        MacNative.bgi_mouse_button(button, down ? 1 : 0);
        return this;
    }

    public MacInput LeftButtonClick()
    {
        MacNative.bgi_mouse_button(0, 1);
        Thread.Sleep(PressHoldMs);
        MacNative.bgi_mouse_button(0, 0);
        return this;
    }

    public MacInput VerticalScroll(int clicks)
    {
        MacNative.bgi_mouse_scroll(clicks);
        return this;
    }

    public static (double X, double Y) MouseLocationPoints
    {
        get
        {
            MacNative.bgi_mouse_location(out var x, out var y);
            return (x, y);
        }
    }

    /// <summary>Releases everything this instance still holds down. Call when a task stops.</summary>
    public void ReleaseAll()
    {
        User32.VK[] held;
        lock (_sync)
        {
            held = [.. _pressed];
        }

        foreach (var key in held)
        {
            KeyUp(key);
        }

        MacNative.bgi_input_release_all();
    }
}
