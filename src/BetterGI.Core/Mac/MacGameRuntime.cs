using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Core.Input.Backends.Win32;
using BetterGenshinImpact.Core.Mask;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.Service.Interface;
using BetterGenshinImpact.View.Windows;
using BetterGI.Mac.Platform;
using Fischless.GameCapture;
using Microsoft.Extensions.Logging;

// The two classes below keep upstream's names (Win32GameWindow, Win32RuntimeProvider) and namespace because
// unmodified upstream files refer to them by name (SystemControl callers, GameRuntimeService, App wiring).
// On macOS "Win32" here means "a native top-level window", as opposed to the web-page runtime.
namespace BetterGenshinImpact.GameTask.Runtime.Win32;

/// <summary>
/// The game window on macOS: a top-level window identified by its window number.
/// </summary>
public class Win32GameWindow : IGameWindow
{
    private const int GeometryPollMs = 500;

    private readonly Process? _process;
    private readonly Timer _geometryTimer;
    private Vanara.PInvoke.RECT _lastRect;
    private bool _disposed;

    public Win32GameWindow(nint hWnd)
    {
        if (hWnd == IntPtr.Zero)
        {
            throw new ArgumentException("游戏窗口句柄为空", nameof(hWnd));
        }

        Handle = hWnd;
        _process = SystemControl.GetProcessByHandle(hWnd) ?? throw new ArgumentException("通过句柄获取游戏进程失败");
        ProcessId = _process.Id;
        ProcessName = _process.ProcessName;
        _lastRect = SystemControl.GetCaptureRect(hWnd);
        // macOS has no per-window move/resize notification without an Accessibility observer; poll instead.
        _geometryTimer = new Timer(_ => PollGeometry(), null, GeometryPollMs, GeometryPollMs);
    }

    public nint Handle { get; }

    public int ProcessId { get; }

    public string ProcessName { get; }

    public virtual GameViewport Viewport
    {
        get
        {
            var scale = MacGameWindowSelection.GameArea((uint)Handle)?.Scale ?? 1;
            return new GameViewport(SystemControl.GetCaptureRect(Handle), (float)scale);
        }
    }

    public virtual bool IsAlive => MacWindows.Query(new MacWindowInfo { Id = (uint)Handle }) != null;

    public bool IsForeground => MacWindows.IsFrontmost((uint)Handle);

    /// <summary>A minimised window is no longer on screen.</summary>
    public bool IsMinimized => MacWindows.Query(new MacWindowInfo { Id = (uint)Handle }) is { OnScreen: false };

    public virtual bool RequiresForeground => true;

    public virtual void Activate() => SystemControl.ActivateWindow(Handle);

    public event EventHandler? ViewportChanged;

    private void PollGeometry()
    {
        if (_disposed)
        {
            return;
        }

        var rect = SystemControl.GetCaptureRect(Handle);
        if (!rect.Equals(_lastRect))
        {
            _lastRect = rect;
            ViewportChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }

    protected virtual void Dispose(bool disposing)
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        ViewportChanged = null;
        if (disposing)
        {
            _geometryTimer.Dispose();
            _process?.Dispose();
        }
    }
}

/// <summary>
/// Acquires the runtime for a native game window: the window the user picked, ScreenCaptureKit capture
/// and CGEvent input. Mirrors upstream's Win32RuntimeProvider step for step.
/// </summary>
public sealed class Win32RuntimeProvider(
    IConfigService configService,
    IMaskWindowDrawingBoard maskWindowDrawingBoard,
    IMaskWindowMapState maskWindowMapState,
    ILogger<Win32RuntimeProvider> logger)
    : IGameRuntimeProvider
{
    public GameRuntimeKind Kind => GameRuntimeKind.Win32Window;

    public async Task<GameRuntime?> AcquireAsync(CancellationToken ct)
    {
        if (!MacPermissions.HasScreenCapture)
        {
            await ThemedMessageBox.ErrorAsync("BetterGI needs the Screen Recording permission to capture the game.");
            return null;
        }

        var hWnd = SystemControl.FindGenshinImpactHandle();
        if (hWnd == IntPtr.Zero)
        {
            await ThemedMessageBox.ErrorAsync("未找到原神窗口，请先启动原神！\nNo game window is selected. Start the game with Yaagl and pick its window.");
            return null;
        }

        ct.ThrowIfCancellationRequested();
        return AttachTo(hWnd);
    }

    public GameRuntime AttachTo(nint hWnd)
    {
        SystemControl.ActivateWindow(hWnd);

        var window = new Win32GameWindow(hWnd);
        IGameCapture? capture = null;
        try
        {
            if (window.IsMinimized)
            {
                throw new ArgumentException("游戏窗口不能最小化");
            }

            // The Win32 compatibility layer converts between points and desktop pixels with this geometry.
            if (MacGameWindowSelection.GameArea((uint)hWnd) is { } area
                && MacWindows.Query(new MacWindowInfo { Id = (uint)hWnd }) is { } frame)
            {
                MacWin32Compat.SetGameGeometry(area.Scale, area.Y - frame.Y);
            }

            var systemInfo = new SystemInfo(window.Viewport, maskWindowDrawingBoard);

            var config = configService.Get();
            capture = GameCaptureFactory.Create(CaptureModes.WindowsGraphicsCapture);
            var settings = new Dictionary<string, object>();
            if (MacGameWindowSelection.Selected?.Id == (uint)hWnd && MacGameWindowSelection.TitleBarPoints is { } bar)
            {
                settings[MacGameCapture.TitleBarPointsKey] = bar;
            }

            capture.Start(hWnd, settings);
            logger.LogInformation("Capturing window {Handle} ({Process}), game picture {Width}x{Height}",
                hWnd, window.ProcessName, window.Viewport.Width, window.Viewport.Height);

            return new GameRuntime(Kind, window, capture, new Win32InputBackend(hWnd), systemInfo,
                maskWindowDrawingBoard, maskWindowMapState);
        }
        catch
        {
            capture?.Dispose();
            window.Dispose();
            throw;
        }
    }

    public void CloseGame(GameRuntime? current) => SystemControl.CloseGameProcesses(current?.Window);
}
