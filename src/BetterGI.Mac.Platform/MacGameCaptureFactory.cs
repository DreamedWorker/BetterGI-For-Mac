using BetterGI.Mac.Platform;

// Same namespace and class name as upstream's Fischless.GameCapture.GameCaptureFactory.
namespace Fischless.GameCapture;

/// <summary>
/// On macOS there is one capturer (ScreenCaptureKit); upstream's Windows capture modes all map to it.
/// </summary>
public static class GameCaptureFactory
{
    public static string[] ModeNames() => Enum.GetNames(typeof(CaptureModes));

    public static IGameCapture Create(CaptureModes mode) => new MacGameCapture();
}
