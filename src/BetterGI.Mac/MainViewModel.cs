using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Avalonia;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;
using BetterGI.Mac.Platform;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Fischless.HotkeyCapture;
using OpenCvSharp;
using Vanara.PInvoke;

namespace BetterGI.Mac;

/// <summary>
/// View model of the main window: permissions, manual window selection, capture preview, input tests
/// and switches for upstream's real-time triggers. Capture, recognition and the triggers themselves are
/// upstream BetterGI code running through <see cref="CoreSession"/>.
/// </summary>
public partial class MainViewModel : ObservableObject, IDisposable
{
    private const int MaxLogLines = 300;
    private const int PreviewIntervalMs = 100;
    private const int PreviewMaxWidth = 960;

    private readonly CoreSession _core = new();
    private readonly MacInput _input = new();
    private readonly HotkeyHook _pauseHotkey = new();
    private readonly DispatcherTimer _statusTimer;
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private long _lastPreviewAt = -PreviewIntervalMs;
    private int _previewPending;
    private int _framesThisSecond;

    public ObservableCollection<MacWindowInfo> Windows { get; } = [];

    public ObservableCollection<string> LogLines { get; } = [];

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(StartCaptureCommand))]
    private MacWindowInfo? _selectedWindow;

    [ObservableProperty] private bool _includeOffScreen;

    /// <summary>0 = automatic, 1 = no title bar, 2 = custom height</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsCustomTitleBar))]
    private int _titleBarMode;

    [ObservableProperty] private decimal? _customTitleBarPoints = 28;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ScreenCaptureText))]
    private bool _screenCaptureGranted;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(AccessibilityText))]
    private bool _accessibilityGranted;

    /// <summary>True once upstream's services have started.</summary>
    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(StartCaptureCommand))]
    private bool _coreReady;

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(StartCaptureCommand))]
    [NotifyCanExecuteChangedFor(nameof(StopCaptureCommand))]
    [NotifyCanExecuteChangedFor(nameof(TestKeyCommand))]
    [NotifyCanExecuteChangedFor(nameof(TestMouseCommand))]
    [NotifyCanExecuteChangedFor(nameof(ActivateGameCommand))]
    [NotifyPropertyChangedFor(nameof(NoPreview))]
    private bool _isCapturing;

    [ObservableProperty] private string _statusText = "Starting BetterGI core…";

    [ObservableProperty] private WriteableBitmap? _preview;

    [ObservableProperty] private bool _paused;

    public bool IsCustomTitleBar => TitleBarMode == 2;

    public bool NoPreview => !IsCapturing;

    public string ScreenCaptureText => ScreenCaptureGranted ? "✓ Screen Recording" : "✗ Screen Recording — required to capture";

    public string AccessibilityText => AccessibilityGranted ? "✓ Accessibility" : "✗ Accessibility — required to send keys / mouse";

    /// <summary>Upstream's services, for the pages.</summary>
    public CoreSession Core => _core;

    public MainViewModel()
    {
        AppLog.Line += OnLogLine;
        RefreshPermissions();
        RefreshWindows();
        _statusTimer = new DispatcherTimer(TimeSpan.FromSeconds(1), DispatcherPriority.Background, (_, _) => OnStatusTick());
        _statusTimer.Start();
        AppLog.Info($"BetterGI-Mac started. Data folder: {BetterGenshinImpact.Mac.MacAppHost.DefaultDataRoot}");
        _ = StartCoreAsync();
    }

    private async Task StartCoreAsync()
    {
        try
        {
            await _core.StartAsync();
            _core.Runtime.Stopped += (_, _) => Dispatcher.UIThread.Post(() =>
            {
                IsCapturing = false;
                StatusText = "Not capturing.";
            });
            _core.Dispatcher.FrameCaptured += OnFrameCaptured;

            // ⌥ Option + P pauses / resumes the trigger loop from inside the game.
            _pauseHotkey.KeyPressed += (_, _) => Dispatcher.UIThread.Post(() => Paused = !Paused);
            _pauseHotkey.RegisterHotKey(User32.HotKeyModifiers.MOD_ALT, System.Windows.Forms.Keys.P);

            CoreReady = true;
            StatusText = "Not capturing. Pick the game window on the left and press Start.";
        }
        catch (Exception e)
        {
            AppLog.Error("Core failed to start: " + e.GetBaseException().Message);
            StatusText = "BetterGI core failed to start: " + e.GetBaseException().Message;
        }
    }

    /// <summary>Stops the running task or script (upstream's stop-all); capture keeps running.</summary>
    [RelayCommand]
    private void StopTasks()
    {
        if (CoreReady)
        {
            Pages.PageUi.StopAll(_core);
            AppLog.Info("Stop requested");
        }
    }

    partial void OnPausedChanged(bool value)
    {
        if (!CoreReady)
        {
            return;
        }

        if (value)
        {
            _core.Dispatcher.StopTimer();
            _input.ReleaseAll();
        }
        else if (_core.Runtime.IsRunning)
        {
            _core.Dispatcher.StartTimer();
        }

        AppLog.Info(value ? "Paused" : "Resumed");
    }

    partial void OnIncludeOffScreenChanged(bool value) => RefreshWindows();

    private void RefreshPermissions()
    {
        ScreenCaptureGranted = MacPermissions.HasScreenCapture;
        AccessibilityGranted = MacPermissions.HasAccessibility;
    }

    [RelayCommand]
    private void RefreshWindows()
    {
        var previousId = SelectedWindow?.Id;
        Windows.Clear();
        foreach (var window in MacWindows.List(IncludeOffScreen))
        {
            Windows.Add(window);
        }

        // Keep the user's choice; otherwise pre-select the window that looks like the game.
        SelectedWindow = Windows.FirstOrDefault(w => w.Id == previousId) ?? Windows.FirstOrDefault(w => w.LooksLikeGame);
    }

    [RelayCommand]
    private void RequestScreenCapture()
    {
        if (!MacPermissions.RequestScreenCapture())
        {
            MacPermissions.OpenScreenCaptureSettings();
            AppLog.Info("Enable BetterGI under Privacy & Security → Screen & System Audio Recording, then quit and reopen BetterGI.");
        }

        RefreshPermissions();
    }

    [RelayCommand]
    private void RequestAccessibility()
    {
        if (!MacPermissions.RequestAccessibility())
        {
            AppLog.Info("Enable BetterGI under Privacy & Security → Accessibility.");
        }

        RefreshPermissions();
    }

    private bool CanStartCapture() => CoreReady && SelectedWindow != null && !IsCapturing;

    [RelayCommand(CanExecute = nameof(CanStartCapture))]
    private async Task StartCapture()
    {
        var window = SelectedWindow;
        if (window is null)
        {
            return;
        }

        double? titleBar = TitleBarMode switch
        {
            1 => 0,
            2 => (double)(CustomTitleBarPoints ?? 0),
            _ => null,
        };

        try
        {
            // The manual choice is what upstream's "find the game window" resolves to on macOS.
            MacGameWindowSelection.Select(window, titleBar);
            StatusText = "Starting capture…";
            var runtime = await _core.Runtime.StartAsync();
            IsCapturing = runtime != null;
            StatusText = runtime != null ? "Waiting for the first frame…" : "Capture did not start (see the log).";
            if (runtime != null && Paused)
            {
                _core.Dispatcher.StopTimer();
            }
        }
        catch (Exception e)
        {
            AppLog.Error(e.GetBaseException().Message);
            StatusText = e.GetBaseException().Message;
        }
    }

    [RelayCommand(CanExecute = nameof(IsCapturing))]
    private async Task StopCapture()
    {
        await _core.Runtime.StopAsync();
        IsCapturing = false;
        StatusText = "Not capturing.";
    }

    [RelayCommand(CanExecute = nameof(IsCapturing))]
    private void ActivateGame()
    {
        var window = _core.Runtime.Current?.Window;
        if (window != null && !MacWindows.Activate((uint)window.Handle))
        {
            AppLog.Warn("Could not bring the game window to the front.");
        }
    }

    /// <summary>Brings the game forward and presses M (opens the map) to prove keyboard injection.</summary>
    [RelayCommand(CanExecute = nameof(IsCapturing))]
    private async Task TestKey()
    {
        if (await PrepareInputTest() is null)
        {
            return;
        }

        await Task.Run(() => _input.KeyPress(User32.VK.VK_M));
        AppLog.Info("Input test: pressed M. The map should have opened in the game.");
    }

    /// <summary>Brings the game forward, centres the cursor and turns the camera to the right and back.</summary>
    [RelayCommand(CanExecute = nameof(IsCapturing))]
    private async Task TestMouse()
    {
        if (await PrepareInputTest() is not { } windowId || MacGameWindowSelection.GameArea(windowId) is not { } area)
        {
            return;
        }

        await Task.Run(() =>
        {
            _input.MoveMouseToPoints(area.X + area.Width / 2, area.Y + area.Height / 2);
            Thread.Sleep(200);
            foreach (var direction in new[] { 1, -1 })
            {
                for (var step = 0; step < 20; step++)
                {
                    _input.MoveMouseBy(15 * direction, 0);
                    Thread.Sleep(15);
                }

                Thread.Sleep(300);
            }
        });
        AppLog.Info("Input test: moved the mouse 300pt right and back. The camera should have turned and returned.");
    }

    private async Task<uint?> PrepareInputTest()
    {
        if (!MacPermissions.HasAccessibility)
        {
            AppLog.Warn("Input test skipped: Accessibility permission is not granted.");
            return null;
        }

        var window = _core.Runtime.Current?.Window;
        if (window is null)
        {
            return null;
        }

        var id = (uint)window.Handle;
        MacWindows.Activate(id);
        await Task.Delay(1000);
        if (!MacWindows.IsFrontmost(id))
        {
            AppLog.Warn("Input test skipped: the game window did not come to the front.");
            return null;
        }

        return id;
    }

    private int _statusTicks;

    /// <summary>When false (another page is shown) no preview frames are produced at all.</summary>
    public volatile bool PreviewVisible = true;

    private void OnStatusTick()
    {
        // permission checks query the privacy database; once granted they rarely change
        if (++_statusTicks % 5 == 0 || !ScreenCaptureGranted || !AccessibilityGranted)
        {
            RefreshPermissions();
        }

        var frames = Interlocked.Exchange(ref _framesThisSecond, 0);
        if (!CoreReady || !IsCapturing || _core.Runtime.Current is not { } runtime)
        {
            return;
        }

        var viewport = runtime.Window.Viewport;
        StatusText = $"Game picture {viewport.Width}×{viewport.Height} px · {frames} frames/s · display {viewport.DpiScale:0.#}x · " +
                     (Paused ? "PAUSED · " : "") +
                     (runtime.Window.IsForeground ? "game is in front" : "game is NOT in front (triggers idle)");
    }

    private void OnLogLine(string line) => Dispatcher.UIThread.Post(() =>
    {
        LogLines.Add(line);
        while (LogLines.Count > MaxLogLines)
        {
            LogLines.RemoveAt(0);
        }
    });

    /// <summary>
    /// Upstream's frame side-channel: called on the capture thread, the frame is only valid during the
    /// call and the handler must not block. A small copy is taken at most ten times per second.
    /// </summary>
    private void OnFrameCaptured(Mat frame)
    {
        Interlocked.Increment(ref _framesThisSecond);
        var now = _clock.ElapsedMilliseconds;
        if (!PreviewVisible || now - Interlocked.Read(ref _lastPreviewAt) < PreviewIntervalMs
                            || Interlocked.Exchange(ref _previewPending, 1) == 1)
        {
            return;
        }

        Interlocked.Exchange(ref _lastPreviewAt, now);
        Mat bgra;
        try
        {
            bgra = MakePreview(frame);
        }
        catch
        {
            Interlocked.Exchange(ref _previewPending, 0);
            return;
        }

        Dispatcher.UIThread.Post(() =>
        {
            try
            {
                Preview = NextBitmap(bgra);
            }
            finally
            {
                bgra.Dispose();
                Interlocked.Exchange(ref _previewPending, 0);
            }
        }, DispatcherPriority.Background);
    }

    /// <summary>
    /// Runs on the capture thread, so it must be cheap: a linear downscale straight into BGRA
    /// (an area filter on a 1440p frame costs several times more and the preview does not need it).
    /// </summary>
    private static Mat MakePreview(Mat frame)
    {
        var width = Math.Min(PreviewMaxWidth, frame.Width);
        var height = (int)Math.Round(frame.Height * (double)width / frame.Width);
        var small = new Mat();
        Cv2.Resize(frame, small, new OpenCvSharp.Size(width, height), 0, 0, InterpolationFlags.Linear);
        if (small.Channels() == 4)
        {
            return small;
        }

        using (small)
        {
            var bgra = new Mat();
            Cv2.CvtColor(small, bgra, ColorConversionCodes.BGR2BGRA);
            return bgra;
        }
    }

    // Two bitmaps used in turn: the one on screen is never written, and no bitmap is allocated per frame
    // (allocating ten 2 MB bitmaps a second left the GC to clean up after them in bursts).
    private readonly WriteableBitmap?[] _previewBitmaps = new WriteableBitmap?[2];
    private int _previewIndex;

    private unsafe WriteableBitmap NextBitmap(Mat bgra)
    {
        _previewIndex ^= 1;
        var bitmap = _previewBitmaps[_previewIndex];
        if (bitmap is null || bitmap.PixelSize.Width != bgra.Width || bitmap.PixelSize.Height != bgra.Height)
        {
            bitmap?.Dispose();
            bitmap = new WriteableBitmap(new PixelSize(bgra.Width, bgra.Height), new Vector(96, 96),
                PixelFormat.Bgra8888, AlphaFormat.Opaque);
            _previewBitmaps[_previewIndex] = bitmap;
        }

        using (var buffer = bitmap.Lock())
        {
            var rowBytes = bgra.Width * 4;
            var sourceStep = (long)bgra.Step();
            for (var y = 0; y < bgra.Height; y++)
            {
                Buffer.MemoryCopy((byte*)bgra.Data + y * sourceStep, (byte*)buffer.Address + (long)y * buffer.RowBytes,
                    buffer.RowBytes, rowBytes);
            }
        }

        return bitmap;
    }

    public void Dispose()
    {
        _statusTimer.Stop();
        _pauseHotkey.Dispose();
        AppLog.Line -= OnLogLine;
        _input.ReleaseAll();
        _core.Dispose();
    }
}
