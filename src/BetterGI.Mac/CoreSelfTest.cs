using System;
using System.IO;
using System.Linq;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Runtime;
using BetterGenshinImpact.Mac;
using BetterGenshinImpact.Service.Interface;
using BetterGenshinImpact.Core.Input.Backends.Win32;
using BetterGenshinImpact.Core.Mask;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask.Model;
using Fischless.GameCapture;
using Microsoft.Extensions.DependencyInjection;
using OpenCvSharp;

namespace BetterGI.Mac;

/// <summary>
/// Headless check of the upstream core on macOS: <c>BetterGI --coretest [--data &lt;folder&gt;]</c>.
/// Builds the service container exactly as the app does and resolves the services the capture /
/// trigger pipeline needs. Sends no input and does not capture.
/// </summary>
internal static class CoreSelfTest
{
    public static int Run(string[] args)
    {
        var index = Array.IndexOf(args, "--data");
        var dataRoot = index >= 0 && index + 1 < args.Length
            ? args[index + 1]
            : Path.Combine(Path.GetTempPath(), "bettergi-coretest");
        var failures = 0;

        void Step(string name, Action action)
        {
            try
            {
                action();
                Console.WriteLine($"  ok    {name}");
            }
            catch (Exception e)
            {
                failures++;
                var inner = e;
                while (inner.InnerException != null)
                {
                    inner = inner.InnerException;
                }

                Console.WriteLine($"  FAIL  {name}\n        {inner.GetType().Name}: {inner.Message.Split('\n')[0]}");
                if (Environment.GetEnvironmentVariable("BGI_TRACE") == "1")
                {
                    Console.WriteLine(e);
                }

                foreach (var frame in (inner.StackTrace ?? "").Split('\n').Where(l => l.Contains("BetterGenshinImpact") || l.Contains("BetterGI")).Take(4))
                {
                    var text = frame.Trim();
                    var cut = text.IndexOf(" in /", StringComparison.Ordinal);
                    Console.WriteLine("        " + (cut > 0 ? text[..cut] + " :" + text[(text.LastIndexOf(':') + 1)..] : text));
                }
            }
        }

        Console.WriteLine($"Core self-test, data root: {dataRoot}");
        Microsoft.Extensions.Hosting.IHost? host = null;
        Step("build service container", () => host = MacAppHost.Build(dataRoot));
        if (host is null)
        {
            Console.WriteLine("\nCORETEST FAILED");
            return 1;
        }

        var services = host.Services;
        Step("startup sequence (inference, plugins, hosted services)", () => MacAppHost.StartAsync(host).GetAwaiter().GetResult());
        Step("config service", () => _ = services.GetRequiredService<IConfigService>().Get());
        Step("Global.Absolute", () =>
        {
            var path = Global.Absolute(@"User\JsScript");
            if (path.Contains('\\'))
            {
                throw new InvalidOperationException("backslash left in " + path);
            }
        });
        Step("game runtime service", () => _ = services.GetRequiredService<GameRuntimeService>());
        Step("task trigger dispatcher", () => _ = services.GetRequiredService<TaskTriggerDispatcher>());
        // Trigger pipeline on a synthetic 1280x720 frame without any prompt: loads upstream's templates and
        // recognition definitions and runs every trigger once. Nothing in a blank frame makes a trigger act.
        GameRuntime? runtime = null;
        SystemInfo? systemInfo = null;
        Step("system info + runtime (synthetic 1280x720)", () =>
        {
            var board = services.GetRequiredService<IMaskWindowDrawingBoard>();
            var viewport = new GameViewport(new Vanara.PInvoke.RECT(0, 0, 1280, 720), 1f);
            systemInfo = new SystemInfo(viewport, board);
            runtime = new GameRuntime(GameRuntimeKind.Win32Window, new FakeWindow(viewport), new FakeCapture(),
                new Win32InputBackend(0), systemInfo, board, services.GetRequiredService<IMaskWindowMapState>());
        });
        if (runtime != null && systemInfo != null)
        {
            var config = services.GetRequiredService<IConfigService>().Get();
            System.Collections.Generic.List<ITaskTrigger> triggers = [];
            Step("create triggers", () =>
            {
                triggers = GameTaskManager.CreateTriggers(runtime, config);
                Console.WriteLine("        " + string.Join(", ", triggers.Select(t => t.Name)));
            });
            foreach (var trigger in triggers)
            {
                Step($"trigger '{trigger.Name}' on a blank frame", () =>
                {
                    using var frame = new Mat(720, 1280, MatType.CV_8UC3, new Scalar(90, 120, 60));
                    using var content = new CaptureContent(frame.Clone(), 0, 50, systemInfo);
                    trigger.OnCapture(content);
                });
            }
        }

        Step("OCR (PaddleOCR through ONNX Runtime)", () =>
        {
            using var image = new Mat(64, 420, MatType.CV_8UC3, new Scalar(30, 30, 30));
            Cv2.PutText(image, "BetterGI 12345", new Point(12, 44), HersheyFonts.HersheySimplex, 1.2, Scalar.White, 2, LineTypes.AntiAlias);
            var text = OcrFactory.Paddle.Ocr(image);
            Console.WriteLine($"        recognised: \"{text.Trim()}\"");
            if (!text.Contains("12345"))
            {
                throw new InvalidOperationException("unexpected OCR result");
            }
        });

        Step("JavaScript engine (ClearScript V8)", () =>
        {
            using var engine = new Microsoft.ClearScript.V8.V8ScriptEngine();
            var value = engine.Evaluate("[1, 2, 3].map(x => x * 2).join(',')") as string;
            if (value != "2,4,6")
            {
                throw new InvalidOperationException("unexpected result: " + value);
            }
        });
        Step("git library (LibGit2Sharp)", () => Console.WriteLine("        libgit2 " + LibGit2Sharp.GlobalSettings.Version.InformationalVersion));
        Step("solo task registry", () =>
        {
            var registry = services.GetRequiredService<BetterGenshinImpact.GameTask.SoloTask.SoloTaskRegistry>();
            Console.WriteLine($"        {registry.All.Count} tasks: " + string.Join(", ", registry.All.Take(6).Select(t => t.DisplayName)) + "…");
        });

        Console.WriteLine(failures == 0 ? "\nCORETEST OK" : $"\nCORETEST FAILED ({failures})");
        return failures == 0 ? 0 : 1;
    }

    /// <summary>Window stand-in for the synthetic pipeline test.</summary>
    private sealed class FakeWindow(GameViewport viewport) : IGameWindow
    {
        public nint Handle => 0;
        public int ProcessId => Environment.ProcessId;
        public GameViewport Viewport { get; } = viewport;
        public bool IsAlive => true;
        public bool IsForeground => false;
        public bool IsMinimized => false;
        public bool RequiresForeground => true;
        public void Activate() { }
#pragma warning disable CS0067
        public event EventHandler? ViewportChanged;
#pragma warning restore CS0067
        public void Dispose() { }
    }

    /// <summary>Capture stand-in: the test feeds frames to the triggers directly.</summary>
    private sealed class FakeCapture : IGameCapture
    {
        public bool IsCapturing => false;
        public void Start(nint hWnd, System.Collections.Generic.Dictionary<string, object>? settings = null) { }
        public GameCaptureFrame? Capture() => null;
        public void Stop() { }
        public void Dispose() { }
    }
}
