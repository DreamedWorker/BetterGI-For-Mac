// Placeholders for upstream classes whose Windows implementation is excluded (see Exclude.props).
// They exist so the rest of upstream compiles; members are added as callers need them and each one
// is either given a macOS implementation here or left inert on purpose.
using System;
using BetterGenshinImpact.Core.Monitor;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Core.Monitor
{
    /// <summary>Raw (relative) mouse input, used to mirror camera movement to other instances.</summary>
    public sealed partial class RawInputMonitor(ILogger<RawInputMonitor> logger) : IRelativeMouseInputMonitor
    {
        private readonly ILogger _logger = logger;

        /// <summary>Not implemented on macOS: no events are delivered.</summary>
        public IDisposable Subscribe(EventHandler<RelativeMouseMoveEventArgs> handler) => new Subscription();

        private sealed class Subscription : IDisposable
        {
            public void Dispose() { }
        }
    }

    /// <summary>Confines the cursor while mirroring mouse movement to another instance. Inert on macOS.</summary>
    internal sealed partial class LocalCursorCapture(ILogger logger) : IDisposable
    {
        private readonly ILogger _logger = logger;

        public void Capture(System.Drawing.Rectangle bounds) { }

        public void Release() { }

        public void ReleaseTemporarily() { }

        public void Dispose() { }
    }
}

namespace BetterGenshinImpact.Service
{
    /// <summary>Overlay performance metrics.</summary>
    public sealed partial class OverlayMetricsService : IDisposable
    {
        public bool IsEnabled => false;
        public void SetGameWindow(BetterGenshinImpact.GameTask.Runtime.IGameWindow? window) { }
        public void UpdateGameFps(double fps) { }
        public void RecordSkippedTick() { }
        public void RecordDispatcherTick(double processingCostMs, double captureCostMs, double triggerCostMs) { }
        public void Refresh() { }
        public void Dispose() { }
    }

    /// <summary>Picture-in-picture preview of the capture. The Avalonia preview replaces it.</summary>
    public static class PictureInPictureService
    {
        public static bool IsManuallyClosed => false;
        public static void Update(OpenCvSharp.Mat frame) { }
        public static void Hide(bool resetManual = false) { }
        public static void ResetManualClose() { }
    }
}
