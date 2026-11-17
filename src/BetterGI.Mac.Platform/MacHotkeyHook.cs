using System.Windows.Forms;
using BetterGI.Mac.Platform;
using Vanara.PInvoke;

// Same namespace and class name as upstream's Fischless.HotkeyCapture.HotkeyHook (RegisterHotKey on Windows).
namespace Fischless.HotkeyCapture;

/// <summary>
/// System-wide hotkey on macOS, implemented by polling the key state (the same approach upstream's Wine
/// add-on uses). Polling needs no event tap and therefore no extra permission; the key press is not
/// swallowed, so it also reaches the front-most app.
/// </summary>
public sealed class HotkeyHook : IDisposable
{
    private const int PollIntervalMs = 30;

    private static readonly object Sync = new();
    private static readonly List<HotkeyHook> Registered = [];
    private static Timer? _timer;

    private User32.HotKeyModifiers _modifier;
    private Keys _key = Keys.None;
    private bool _wasDown;

    public event EventHandler<KeyPressedEventArgs>? KeyPressed;

    public void RegisterHotKey(User32.HotKeyModifiers modifier, Keys key)
    {
        lock (Sync)
        {
            _modifier = modifier;
            _key = key & Keys.KeyCode;
            _wasDown = IsDown(); // a key already held while registering must not fire
            if (!Registered.Contains(this))
            {
                Registered.Add(this);
            }

            _timer ??= new Timer(_ => Poll(), null, PollIntervalMs, PollIntervalMs);
        }
    }

    public void UnregisterHotKey()
    {
        lock (Sync)
        {
            Registered.Remove(this);
            if (Registered.Count == 0)
            {
                _timer?.Dispose();
                _timer = null;
            }
        }
    }

    public void Dispose() => UnregisterHotKey();

    private bool IsDown()
    {
        if (_key == Keys.None || !MacInput.IsKeyDown((User32.VK)(int)_key))
        {
            return false;
        }

        return Matches(User32.HotKeyModifiers.MOD_ALT, User32.VK.VK_MENU)
               && Matches(User32.HotKeyModifiers.MOD_CONTROL, User32.VK.VK_CONTROL)
               && Matches(User32.HotKeyModifiers.MOD_SHIFT, User32.VK.VK_SHIFT)
               && Matches(User32.HotKeyModifiers.MOD_WIN, User32.VK.VK_LWIN);
    }

    /// <summary>A modifier must be held exactly when the hotkey asks for it.</summary>
    private bool Matches(User32.HotKeyModifiers flag, User32.VK key) =>
        _modifier.HasFlag(flag) == MacInput.IsKeyDown(key);

    private static void Poll()
    {
        HotkeyHook[] hooks;
        lock (Sync)
        {
            hooks = [.. Registered];
        }

        foreach (var hook in hooks)
        {
            var down = hook.IsDown();
            var fire = down && !hook._wasDown;
            hook._wasDown = down;
            if (fire)
            {
                try
                {
                    hook.KeyPressed?.Invoke(hook, new KeyPressedEventArgs(hook._modifier, hook._key));
                }
                catch
                {
                    // a failing handler must not stop hotkey polling
                }
            }
        }
    }
}
