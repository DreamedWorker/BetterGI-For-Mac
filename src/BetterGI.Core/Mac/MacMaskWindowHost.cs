using System;
using System.Windows;
using BetterGenshinImpact.Core.Mask;

namespace BetterGenshinImpact.Mac;

/// <summary>
/// Overlay ("mask") window host. There is no overlay window on macOS yet, so this only tracks what
/// upstream reports: the overlay state follows the game window, and the latest game-window state is
/// published for a future Avalonia overlay to consume.
/// </summary>
public sealed class MacMaskWindowHost : IMaskWindowHost
{
    private nint _gameHandle;

    public MaskWindowState State { get; private set; }

    public event EventHandler<MaskWindowState>? StateChanged;

    /// <summary>Latest state the dispatcher reported for the game window.</summary>
    public GameWindowState? GameWindow { get; private set; }

    public void Attach(nint gameHandle) => _gameHandle = gameHandle;

    public void Detach()
    {
        _gameHandle = 0;
        Update(new MaskWindowState(false, default));
    }

    public void Close() => Detach();

    public void ReportGameWindow(GameWindowState state)
    {
        GameWindow = state;
        var bounds = state.Bounds;
        var visible = _gameHandle != 0 && state is { IsCapturing: true, IsMinimized: false };
        Update(new MaskWindowState(visible, new Rect(bounds.X, bounds.Y, bounds.Width, bounds.Height)));
    }

    private void Update(MaskWindowState state)
    {
        if (state.Equals(State))
        {
            return;
        }

        State = state;
        StateChanged?.Invoke(this, state);
    }
}
