using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace BetterGI.Mac.Platform;

/// <summary>
/// One top-level macOS window that can be chosen as the capture target.
/// Geometry is in global display points; <see cref="Scale"/> converts points to pixels.
/// </summary>
public sealed record MacWindowInfo
{
    [JsonPropertyName("id")] public uint Id { get; init; }
    [JsonPropertyName("pid")] public int ProcessId { get; init; }
    [JsonPropertyName("owner")] public string Owner { get; init; } = "";
    [JsonPropertyName("title")] public string Title { get; init; } = "";
    [JsonPropertyName("executable")] public string Executable { get; init; } = "";
    [JsonPropertyName("x")] public double X { get; init; }
    [JsonPropertyName("y")] public double Y { get; init; }
    [JsonPropertyName("width")] public double Width { get; init; }
    [JsonPropertyName("height")] public double Height { get; init; }
    [JsonPropertyName("scale")] public double Scale { get; init; } = 1;
    [JsonPropertyName("onScreen")] public bool OnScreen { get; init; }

    /// <summary>
    /// The game runs inside Wine when launched by Yaagl, so its window belongs to a "wine" process
    /// rather than YuanShen.exe. This flag only pre-sorts the list; the user still makes the choice.
    /// </summary>
    [JsonIgnore]
    public bool LooksLikeGame
    {
        get
        {
            if (Contains(Title, "原神") || Contains(Title, "Genshin") || Contains(Title, "YuanShen"))
            {
                return true;
            }

            var isWine = Contains(Owner, "wine") || Contains(Executable, "/wine") || Contains(Executable, "crossover")
                         || Contains(Executable, "Game Porting Toolkit") || Contains(Owner, "PlayCover");
            // Wine also owns small helper windows; the game itself is a large on-screen one.
            return isWine && OnScreen && Width >= 800 && Height >= 450;
        }
    }

    [JsonIgnore]
    public string DisplayName => string.IsNullOrWhiteSpace(Title) ? Owner : $"{Owner} — {Title}";

    [JsonIgnore]
    public string Details =>
        $"{Width:0}×{Height:0} pt · {Scale:0.#}x · pid {ProcessId} · id {Id}{(OnScreen ? "" : " · off-screen")}";

    private static bool Contains(string text, string value) =>
        text.Contains(value, StringComparison.OrdinalIgnoreCase);
}

/// <summary>
/// Window enumeration and live queries.
/// </summary>
public static class MacWindows
{
    /// <summary>Height in points of a standard macOS title bar.</summary>
    public const double StandardTitleBarHeight = 28;

    private static readonly double[] CommonAspects = [16d / 9, 16d / 10, 4d / 3, 21d / 9, 64d / 27, 3d / 2];

    /// <summary>
    /// Lists candidate windows, likely game windows first, otherwise front-to-back.
    /// </summary>
    public static IReadOnlyList<MacWindowInfo> List(bool includeOffScreen = false)
    {
        var json = MacNative.TakeString(MacNative.bgi_list_windows(includeOffScreen ? 1 : 0));
        var windows = JsonSerializer.Deserialize<List<MacWindowInfo>>(json) ?? [];
        return windows.OrderByDescending(w => w.LooksLikeGame).ToList();
    }

    // The capture loop asks about the game window several times per tick and every running task asks
    // again before each wait; each answer is a round trip to the window server. Answers are reused for
    // a short time instead (well below one capture interval), which removes ~90% of those calls.
    private static readonly long CacheTicks = System.Diagnostics.Stopwatch.Frequency * 40 / 1000;
    private static readonly object CacheLock = new();
    private static readonly Dictionary<uint, (long Stamp, MacWindowInfo? Info)> QueryCache = [];
    // Stamp 0 means "no answer yet". (Not long.MinValue: now - long.MinValue overflows to a negative
    // number, which made the empty initial answer look fresh forever.)
    private static (long Stamp, uint WindowId, int ProcessId) _frontmost;

    private static bool IsFresh(long stamp, long now) => stamp != 0 && now >= stamp && now - stamp < CacheTicks;

    /// <summary>Re-reads the geometry of a window (at most 40 ms old); null when it no longer exists.</summary>
    public static MacWindowInfo? Query(MacWindowInfo known)
    {
        var now = System.Diagnostics.Stopwatch.GetTimestamp();
        MacWindowInfo? fresh;
        lock (CacheLock)
        {
            if (QueryCache.TryGetValue(known.Id, out var cached) && IsFresh(cached.Stamp, now))
            {
                return cached.Info is null ? null : known with
                {
                    X = cached.Info.X, Y = cached.Info.Y, Width = cached.Info.Width, Height = cached.Info.Height,
                    Scale = cached.Info.Scale, ProcessId = cached.Info.ProcessId, OnScreen = cached.Info.OnScreen,
                };
            }
        }

        fresh = MacNative.bgi_window_info(known.Id, out var x, out var y, out var width, out var height, out var scale,
            out var pid, out var onScreen) == 0
            ? null
            : known with { X = x, Y = y, Width = width, Height = height, Scale = scale, ProcessId = pid, OnScreen = onScreen != 0 };
        lock (CacheLock)
        {
            if (QueryCache.Count > 64)
            {
                QueryCache.Clear();
            }

            QueryCache[known.Id] = (now, fresh);
        }

        return fresh;
    }

    /// <summary>True when the process owning the window owns the front-most normal window (at most 40 ms old).</summary>
    public static bool IsFrontmost(uint windowId)
    {
        var target = Query(new MacWindowInfo { Id = windowId });
        return target is { OnScreen: true } && target.ProcessId == Frontmost().ProcessId;
    }

    /// <summary>The front-most window asked directly, without the cache (for checks).</summary>
    public static (uint WindowId, int ProcessId) FrontmostUncached()
    {
        var id = MacNative.bgi_frontmost_window(out var pid);
        return (id, pid);
    }

    /// <summary>Forgets cached answers; called after anything that changes window order or state.</summary>
    public static void InvalidateCache()
    {
        lock (CacheLock)
        {
            QueryCache.Clear();
            _frontmost = default;
        }
    }

    public static bool Activate(uint windowId)
    {
        var result = MacNative.bgi_window_activate(windowId) != 0;
        InvalidateCache();
        return result;
    }

    /// <summary>Window number and owning process of the front-most normal window; (0, 0) when none.</summary>
    public static (uint WindowId, int ProcessId) Frontmost()
    {
        var now = System.Diagnostics.Stopwatch.GetTimestamp();
        lock (CacheLock)
        {
            if (IsFresh(_frontmost.Stamp, now))
            {
                return (_frontmost.WindowId, _frontmost.ProcessId);
            }
        }

        var id = MacNative.bgi_frontmost_window(out var pid);
        lock (CacheLock)
        {
            _frontmost = (now, id, pid);
        }

        return (id, pid);
    }

    /// <summary>Minimises or restores a window (needs the Accessibility permission).</summary>
    public static bool SetMinimized(uint windowId, bool minimized)
    {
        var result = MacNative.bgi_window_set_minimized(windowId, minimized ? 1 : 0) != 0;
        InvalidateCache();
        return result;
    }

    /// <summary>
    /// Guesses the title bar height (points) of a window: a windowed Wine game is the game picture plus a
    /// standard title bar, so if removing 28pt yields a common aspect ratio and the full window does not,
    /// the window has a title bar. Borderless / full-screen windows return 0.
    /// </summary>
    public static double GuessTitleBarHeight(double width, double height)
    {
        if (width <= 0 || height <= StandardTitleBarHeight)
        {
            return 0;
        }

        var full = AspectError(width, height);
        var withoutBar = AspectError(width, height - StandardTitleBarHeight);
        return withoutBar < full && withoutBar < 0.004 ? StandardTitleBarHeight : 0;
    }

    private static double AspectError(double width, double height)
    {
        var aspect = width / height;
        return CommonAspects.Min(a => Math.Abs(aspect - a) / a);
    }
}
