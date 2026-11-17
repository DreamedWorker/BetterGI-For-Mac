using System;
using System.Collections.Generic;
using System.Diagnostics;
using Fischless.GameCapture;
using OpenCvSharp;

namespace BetterGI.Mac.Platform;

/// <summary>
/// ScreenCaptureKit implementation of upstream's <see cref="IGameCapture"/>.
/// <para>
/// The <c>hWnd</c> passed to <see cref="Start"/> is the macOS window number (CGWindowID) of the window
/// the user picked. Frames are returned as BGR (CV_8UC3) like the Windows capturers, with the macOS
/// title bar already cropped away so the picture equals the game's client area.
/// </para>
/// </summary>
public sealed class MacGameCapture : IGameCapture
{
    /// <summary>Settings key: title bar height in points to crop from the top (double). Omit for auto.</summary>
    public const string TitleBarPointsKey = "TitleBarPoints";

    /// <summary>Settings key: capture frame rate (int, default 30).</summary>
    public const string FpsKey = "Fps";

    private const long GeometryCheckIntervalMs = 500;

    private readonly object _sync = new();
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private MacWindowInfo? _window;
    private double? _titleBarOverride;
    private long _lastGeometryCheck;
    private Mat? _bgra;

    public bool IsCapturing { get; private set; }

    /// <summary>The captured window with its most recently observed geometry.</summary>
    public MacWindowInfo? Window => _window;

    /// <summary>Title bar height in points currently being cropped.</summary>
    public double TitleBarPoints { get; private set; }

    /// <summary>Sequence number of the frame returned by the last <see cref="Capture"/> call.</summary>
    public ulong LastFrameSequence { get; private set; }

    /// <summary>False once the window has been closed.</summary>
    public bool WindowAlive { get; private set; }

    /// <summary>False after ScreenCaptureKit ended the stream by itself (e.g. the window was closed).</summary>
    public static bool NativeRunning => MacNative.bgi_capture_is_running() != 0;

    /// <summary>Message of the last native capture error, empty when none.</summary>
    public static string LastError => MacNative.TakeString(MacNative.bgi_capture_last_error());

    /// <summary>
    /// Game picture on screen in global display points (window frame minus title bar).
    /// </summary>
    public (double X, double Y, double Width, double Height) GameAreaPoints
    {
        get
        {
            var window = _window;
            return window is null
                ? default
                : (window.X, window.Y + TitleBarPoints, window.Width, window.Height - TitleBarPoints);
        }
    }

    public void Start(nint hWnd, Dictionary<string, object>? settings = null)
    {
        lock (_sync)
        {
            Stop();
            var windowId = (uint)hWnd;
            var info = MacWindows.Query(new MacWindowInfo { Id = windowId })
                       ?? throw new InvalidOperationException($"Window {windowId} no longer exists.");

            var fps = settings != null && settings.TryGetValue(FpsKey, out var fpsValue) ? Convert.ToInt32(fpsValue) : 30;
            _titleBarOverride = settings != null && settings.TryGetValue(TitleBarPointsKey, out var barValue)
                ? Convert.ToDouble(barValue)
                : null;

            var code = MacNative.bgi_capture_start(windowId, fps);
            if (code != 0)
            {
                throw new InvalidOperationException($"Could not start capture ({code}): {LastError}");
            }

            _window = info;
            TitleBarPoints = _titleBarOverride ?? MacWindows.GuessTitleBarHeight(info.Width, info.Height);
            WindowAlive = true;
            IsCapturing = true;
            _lastGeometryCheck = _clock.ElapsedMilliseconds;
        }
    }

    public GameCaptureFrame? Capture()
    {
        lock (_sync)
        {
            if (!IsCapturing || _window is null)
            {
                return null;
            }

            RefreshGeometry();

            MacNative.bgi_capture_frame_size(out var fullWidth, out var fullHeight);
            if (fullWidth <= 0 || fullHeight <= 0)
            {
                return null; // no frame delivered yet
            }

            // Title bar in frame pixels: the stream is configured at window size * scale.
            var cropTop = (int)Math.Round(TitleBarPoints * fullHeight / Math.Max(1, _window.Height));
            var height = fullHeight - cropTop;
            if (height <= 0)
            {
                return null;
            }

            if (_bgra is null || _bgra.Width != fullWidth || _bgra.Height != height)
            {
                _bgra?.Dispose();
                _bgra = new Mat(height, fullWidth, MatType.CV_8UC4);
            }

            var sequence = MacNative.bgi_capture_copy_frame(_bgra.Data, (long)fullWidth * height * 4, cropTop,
                out var copiedWidth, out var copiedHeight);
            if (sequence == 0 || copiedWidth != fullWidth || copiedHeight != height)
            {
                return null; // frame changed size between the two calls; the next call picks it up
            }

            LastFrameSequence = sequence;
            var bgr = new Mat();
            Cv2.CvtColor(_bgra, bgr, ColorConversionCodes.BGRA2BGR);
            return new GameCaptureFrame(bgr);
        }
    }

    public void Stop()
    {
        lock (_sync)
        {
            if (IsCapturing)
            {
                MacNative.bgi_capture_stop();
            }

            IsCapturing = false;
            _bgra?.Dispose();
            _bgra = null;
        }
    }

    public void Dispose() => Stop();

    /// <summary>
    /// Follows window moves and resizes: keeps the viewport current and re-sizes the stream
    /// when the pixel size of the window changes.
    /// </summary>
    private void RefreshGeometry()
    {
        var now = _clock.ElapsedMilliseconds;
        if (now - _lastGeometryCheck < GeometryCheckIntervalMs || _window is null)
        {
            return;
        }

        _lastGeometryCheck = now;
        var current = MacWindows.Query(_window);
        if (current is null)
        {
            WindowAlive = false;
            return;
        }

        var resized = Math.Abs(current.Width - _window.Width) > 0.5 || Math.Abs(current.Height - _window.Height) > 0.5
                      || Math.Abs(current.Scale - _window.Scale) > 0.01;
        _window = current;
        if (resized)
        {
            TitleBarPoints = _titleBarOverride ?? MacWindows.GuessTitleBarHeight(current.Width, current.Height);
            MacNative.bgi_capture_resize((int)Math.Round(current.Width * current.Scale),
                (int)Math.Round(current.Height * current.Scale));
        }
    }
}
