namespace BetterGI.Mac.Platform;

/// <summary>
/// The game window the user picked by hand. Under Yaagl the game is a Wine process, so it cannot be
/// identified by process name the way upstream does on Windows; everything that needs "the game window"
/// asks here first.
/// </summary>
public static class MacGameWindowSelection
{
    private static readonly object Sync = new();
    private static MacWindowInfo? _selected;
    private static double? _titleBarPoints;

    /// <summary>Raised after the selection changed.</summary>
    public static event Action? Changed;

    /// <summary>The picked window, or null when nothing has been picked (or it has been cleared).</summary>
    public static MacWindowInfo? Selected
    {
        get
        {
            lock (Sync)
            {
                return _selected;
            }
        }
    }

    /// <summary>Title bar height to crop, in points. Null means detect automatically.</summary>
    public static double? TitleBarPoints
    {
        get
        {
            lock (Sync)
            {
                return _titleBarPoints;
            }
        }
    }

    public static void Select(MacWindowInfo? window, double? titleBarPoints = null)
    {
        lock (Sync)
        {
            _selected = window;
            _titleBarPoints = titleBarPoints;
        }

        Changed?.Invoke();
    }

    /// <summary>
    /// The window to treat as the game: the manual selection while it still exists, otherwise the best
    /// guess from the window list. Returns 0 when there is none.
    /// </summary>
    public static uint ResolveWindowId()
    {
        var selected = Selected;
        if (selected != null && MacWindows.Query(selected) != null)
        {
            return selected.Id;
        }

        var guess = MacWindows.List().FirstOrDefault(w => w.LooksLikeGame);
        return guess?.Id ?? 0;
    }

    /// <summary>
    /// Geometry of the game picture for a window: the window frame minus the title bar, in points,
    /// plus the display scale. Null when the window is gone.
    /// </summary>
    public static (double X, double Y, double Width, double Height, double Scale)? GameArea(uint windowId)
    {
        var info = MacWindows.Query(new MacWindowInfo { Id = windowId });
        if (info is null)
        {
            return null;
        }

        var selected = Selected;
        var bar = selected != null && selected.Id == windowId && TitleBarPoints.HasValue
            ? TitleBarPoints.Value
            : MacWindows.GuessTitleBarHeight(info.Width, info.Height);
        return (info.X, info.Y + bar, info.Width, info.Height - bar, info.Scale);
    }
}
