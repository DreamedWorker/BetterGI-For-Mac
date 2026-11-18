using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using BetterGenshinImpact.Core.Input;
using BetterGenshinImpact.Core.Mask;
using BetterGenshinImpact.Core.Recognition.OCR;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Model;
using BetterGenshinImpact.GameTask.Runtime;
using BetterGenshinImpact.Mac;
using BetterGI.Mac.Platform;
using Fischless.GameCapture;
using Microsoft.Extensions.DependencyInjection;
using OpenCvSharp;
using Vanara.PInvoke;

namespace BetterGI.Mac;

/// <summary>
/// Performance check: <c>BetterGI --perftest [--window &lt;id&gt;] [--seconds &lt;n&gt;] [--data &lt;folder&gt;]</c>.
/// Measures the per-call cost of the window / foreground queries the capture loop makes, then runs
/// upstream's real trigger dispatcher for a while on synthetic 2560×1440 frames and reports the gaps
/// between captures (stalls), GC pauses and CPU use. Input goes to a no-op backend: nothing is sent.
/// </summary>
internal static class PerfTest
{
    public static int Run(string[] args)
    {
        var dataRoot = Value(args, "--data") ?? Path.Combine(Path.GetTempPath(), "bettergi-perftest");
        var seconds = int.TryParse(Value(args, "--seconds"), out var s) ? s : 20;
        var windowId = uint.TryParse(Value(args, "--window"), out var w) ? w : MacWindows.List().FirstOrDefault()?.Id ?? 0;

        Console.WriteLine($"CPU cores: {Environment.ProcessorCount}, window under test: {windowId}");
        Console.WriteLine("\nPer-call cost (median / p95 over 200 calls):");
        if (windowId != 0)
        {
            var info = new MacWindowInfo { Id = windowId };
            Bench("MacWindows.Query", () => MacWindows.Query(info));
            Bench("MacWindows.IsFrontmost", () => MacWindows.IsFrontmost(windowId));
            Bench("MacWindows.Frontmost", () => MacWindows.Frontmost());
            Bench("GameArea", () => MacGameWindowSelection.GameArea(windowId));
            Bench("SystemControl.GetCaptureRect", () => SystemControl.GetCaptureRect((nint)windowId));
            Bench("SystemControl.GetActiveProcessName", () => SystemControl.GetActiveProcessName());
            Bench("MacInput.IsKeyDown", () => MacInput.IsKeyDown(User32.VK.VK_F));
        }

        using var bgra = new Mat(1440, 2560, MatType.CV_8UC4, new Scalar(80, 110, 70, 255));
        Bench("BGRA→BGR 2560×1440 (new Mat)", () =>
        {
            using var bgr = new Mat();
            Cv2.CvtColor(bgra, bgr, ColorConversionCodes.BGRA2BGR);
        }, 50);
        using var bgr1440 = new Mat(1440, 2560, MatType.CV_8UC3, new Scalar(80, 110, 70));
        Bench("Preview downscale, area filter", () => { using var m = new Mat(); Cv2.Resize(bgr1440, m, new OpenCvSharp.Size(960, 540), 0, 0, InterpolationFlags.Area); }, 50);
        Bench("Preview downscale, linear", () => { using var m = new Mat(); Cv2.Resize(bgr1440, m, new OpenCvSharp.Size(960, 540), 0, 0, InterpolationFlags.Linear); }, 50);
        using var reused = new Mat(1440, 2560, MatType.CV_8UC3);
        Bench("BGRA→BGR 2560×1440 (reused)", () => Cv2.CvtColor(bgra, reused, ColorConversionCodes.BGRA2BGR), 50);

        if (args.Contains("--opencv"))
        {
            var info = Cv2.GetBuildInformation();
            foreach (var line in info.Split('\n').Where(l => l.Contains("Parallel framework") || l.Contains("CPU/HW features") || l.Contains("Baseline") || l.Contains("Dispatched") || l.Contains("IPP") || l.Contains("Version control") || l.Contains("Lapack") || l.Contains("Other third-party")))
            {
                Console.WriteLine("  " + line.Trim());
            }

            Console.WriteLine($"  threads: {Cv2.GetNumThreads()}, optimized: {Cv2.UseOptimized()}");
            using var image = new Mat(1080, 1920, MatType.CV_8UC3);
            Cv2.Randu(image, new Scalar(0, 0, 0), new Scalar(255, 255, 255));
            using var templ = new Mat(image, new Rect(900, 500, 42, 42)).Clone();
            using var grey = new Mat();
            Cv2.CvtColor(image, grey, ColorConversionCodes.BGR2GRAY);
            using var greyTempl = new Mat();
            Cv2.CvtColor(templ, greyTempl, ColorConversionCodes.BGR2GRAY);
            using var result = new Mat();
            Bench("matchTemplate 42x42 BGR on 1080p", () => Cv2.MatchTemplate(image, templ, result, TemplateMatchModes.CCoeffNormed), 10);
            Bench("matchTemplate 42x42 grey on 1080p", () => Cv2.MatchTemplate(grey, greyTempl, result, TemplateMatchModes.CCoeffNormed), 10);
            Bench("FastMatch 42x42 BGR on 1080p", () => FastMatch.MatchTemplate(image, templ, result, TemplateMatchModes.CCoeffNormed), 10);
            Bench("FastMatch 42x42 grey on 1080p", () => FastMatch.MatchTemplate(grey, greyTempl, result, TemplateMatchModes.CCoeffNormed), 10);

            // same scores as OpenCV on the whole image, for every mode, with and without a mask
            using var mask = new Mat(42, 42, MatType.CV_8UC1, Scalar.All(255));
            Cv2.Circle(mask, new OpenCvSharp.Point(21, 21), 12, Scalar.All(0), -1);
            var worst = 0.0;
            foreach (var mode in Enum.GetValues<TemplateMatchModes>())
            {
                foreach (var useMask in new[] { false, true })
                {
                    using var expected = new Mat();
                    using var actual = new Mat();
                    Cv2.MatchTemplate(image, templ, expected, mode, useMask ? mask : null);
                    FastMatch.MatchTemplate(image, templ, actual, mode, useMask ? mask : null);
                    using var diff = new Mat();
                    Cv2.Absdiff(expected, actual, diff);
                    Cv2.MinMaxLoc(diff, out _, out double maxDiff);
                    Cv2.MinMaxLoc(expected, out _, out double maxValue);
                    var relative = maxDiff / Math.Max(1e-9, Math.Abs(maxValue));
                    worst = Math.Max(worst, relative);
                    Cv2.MinMaxLoc(expected, out _, out _, out var minE, out var maxE);
                    Cv2.MinMaxLoc(actual, out _, out _, out var minA, out var maxA);
                    var same = mode is TemplateMatchModes.SqDiff or TemplateMatchModes.SqDiffNormed ? minE == minA : maxE == maxA;
                    Console.WriteLine($"  {mode,-14} mask {(useMask ? "yes" : "no "),-3}  size {(expected.Size() == actual.Size() ? "same" : "DIFFERENT")}  best match {(same ? "same" : "DIFFERENT")}  max relative difference {relative:E1}");
                }
            }

            Cv2.SetNumThreads(1);
            Bench("  OpenCV, 1 thread (BGR)", () => Cv2.MatchTemplate(image, templ, result, TemplateMatchModes.CCoeffNormed), 10);
            return 0;
        }

        if (args.Contains("--onnx"))
        {
            OnnxBench();
            return 0;
        }

        Console.WriteLine($"\nBuilding the core (data: {dataRoot})…");
        var host = MacAppHost.Build(dataRoot);
        MacAppHost.StartAsync(host).GetAwaiter().GetResult();
        var services = host.Services;
        InputHub.Attach(new NullInputBackend());

        var cpuStart = Process.GetCurrentProcess().TotalProcessorTime;
        Thread.Sleep(5000);
        Console.WriteLine($"  core idle (no capture): {(Process.GetCurrentProcess().TotalProcessorTime - cpuStart).TotalMilliseconds / 50:0}% of one core");

        Bench("PaddleOCR recognise one line", () =>
        {
            using var line = new Mat(48, 320, MatType.CV_8UC3, new Scalar(30, 30, 30));
            Cv2.PutText(line, "Mint 12", new OpenCvSharp.Point(8, 36), HersheyFonts.HersheySimplex, 1.1, Scalar.White, 2);
            OcrFactory.Paddle.OcrWithoutDetector(line);
        }, 30);

        foreach (var scenario in new[] { "idle frame", "pick-up prompt" })
        {
            TimeTriggers(services, scenario);
            RunDispatcher(services, scenario, seconds, windowId);
        }

        return 0;
    }

    private static void RunDispatcher(IServiceProvider services, string scenario, int seconds, uint windowId)
    {
        var board = services.GetRequiredService<IMaskWindowDrawingBoard>();
        var viewport = new GameViewport(new RECT(0, 0, 2560, 1440), 2f);
        var systemInfo = new SystemInfo(viewport, board);
        var frame = MakeFrame(scenario);
        var capture = new TimedCapture(frame);
        var window = new TimedWindow(viewport, windowId);
        var runtime = new GameRuntime(GameRuntimeKind.Win32Window, window, capture, new NullInputBackend(), systemInfo, board,
            services.GetRequiredService<IMaskWindowMapState>());
        var dispatcher = services.GetRequiredService<TaskTriggerDispatcher>();

        var gcBefore = (GC.CollectionCount(0), GC.CollectionCount(1), GC.CollectionCount(2), GC.GetTotalPauseDuration());
        var cpuBefore = Process.GetCurrentProcess().TotalProcessorTime;
        var clock = Stopwatch.StartNew();
        dispatcher.Start(runtime, 50);
        Thread.Sleep(TimeSpan.FromSeconds(seconds));
        dispatcher.Stop();
        var elapsed = clock.Elapsed;
        var cpu = Process.GetCurrentProcess().TotalProcessorTime - cpuBefore;
        var pause = GC.GetTotalPauseDuration() - gcBefore.Item4;

        var gaps = capture.Gaps();
        Console.WriteLine($"\nDispatcher, {scenario}, {seconds}s:");
        if (gaps.Count == 0)
        {
            Console.WriteLine("  no frames were captured");
            return;
        }

        gaps.Sort();
        Console.WriteLine($"  frames {gaps.Count + 1}, gap between captures: median {gaps[gaps.Count / 2]:0.0} ms, " +
                          $"p95 {gaps[(int)(gaps.Count * 0.95)]:0.0} ms, max {gaps[^1]:0.0} ms, gaps > 120 ms: {gaps.Count(g => g > 120)}");
        Console.WriteLine($"  window queries per second: {window.Calls / elapsed.TotalSeconds:0}, time in them {window.Time.TotalMilliseconds / elapsed.TotalSeconds:0.0} ms/s");
        Console.WriteLine($"  GC: gen0 {GC.CollectionCount(0) - gcBefore.Item1}, gen1 {GC.CollectionCount(1) - gcBefore.Item2}, " +
                          $"gen2 {GC.CollectionCount(2) - gcBefore.Item3}, total pause {pause.TotalMilliseconds:0} ms");
        Console.WriteLine($"  CPU: {cpu.TotalMilliseconds / elapsed.TotalMilliseconds * 100:0}% of one core");
        frame.Dispose();
    }

    /// <summary>Runs each enabled trigger alone on 120 consecutive frames and reports slow calls.</summary>
    private static void TimeTriggers(IServiceProvider services, string scenario)
    {
        var board = services.GetRequiredService<IMaskWindowDrawingBoard>();
        var viewport = new GameViewport(new RECT(0, 0, 2560, 1440), 2f);
        var systemInfo = new SystemInfo(viewport, board);
        using var frame = MakeFrame(scenario);
        var runtime = new GameRuntime(GameRuntimeKind.Win32Window, new TimedWindow(viewport, 0), new TimedCapture(frame),
            new NullInputBackend(), systemInfo, board, services.GetRequiredService<IMaskWindowMapState>());
        var config = services.GetRequiredService<BetterGenshinImpact.Service.Interface.IConfigService>().Get();
        Console.WriteLine($"\nTriggers alone, {scenario} (120 frames at 50 ms):");
        var total = new double[120];
        foreach (var trigger in GameTaskManager.CreateTriggers(runtime, config))
        {
            if (!trigger.IsEnabledByConfig)
            {
                continue;
            }

            trigger.OnEnabled(null);
            var times = new double[120];
            for (var i = 0; i < times.Length; i++)
            {
                using var content = new CaptureContent(frame.Clone(), i, 50, systemInfo);
                var start = Stopwatch.GetTimestamp();
                trigger.OnCapture(content);
                times[i] = Stopwatch.GetElapsedTime(start).TotalMilliseconds;
                total[i] += times[i];
            }

            var slow = times.Select((t, i) => (t, i)).Where(x => x.t > 40).Select(x => $"#{x.i}:{x.t:0}").ToList();
            Console.WriteLine($"  {trigger.Name,-12} median {times.OrderBy(t => t).ElementAt(60),7:0.00} ms  max {times.Max(),7:0.0} ms" +
                              (slow.Count > 0 ? "  slow frames " + string.Join(" ", slow.Take(8)) : ""));
        }

        using (var content = new CaptureContent(frame.Clone(), 0, 50, systemInfo))
        {
            var ra = content.CaptureRectArea;
            void Step(string name, Func<object?> action)
            {
                action();
                var t = Stopwatch.GetTimestamp();
                for (var i = 0; i < 5; i++)
                {
                    action();
                }

                Console.WriteLine($"  {"  " + name,-40} {Stopwatch.GetElapsedTime(t).TotalMilliseconds / 5,7:0.00} ms");
            }

            Console.WriteLine("  auto-enter-game steps:");
            Step("IsInMainUi", () => BetterGenshinImpact.GameTask.Common.BgiVision.Bv.IsInMainUi(ra));
            Step("IsInAnyClosableUi", () => BetterGenshinImpact.GameTask.Common.BgiVision.Bv.IsInAnyClosableUi(ra));
            Step("IsInDomain", () => BetterGenshinImpact.GameTask.Common.BgiVision.Bv.IsInDomain(ra));
            Step("BtnWhiteConfirm", () => ra.Find(BetterGenshinImpact.GameTask.Common.Element.Assets.ElementRecognition.Get("BtnWhiteConfirm", ra)));
            Step("ChooseEnterGame", () => ra.Find(BetterGenshinImpact.Core.Recognition.RecognitionAssets.Get("GameLoading", "ChooseEnterGame", ra)));
            Step("EnterGame", () => ra.Find(BetterGenshinImpact.Core.Recognition.RecognitionAssets.Get("GameLoading", "EnterGame", ra)));
            Step("WelkinMoon", () => ra.Find(BetterGenshinImpact.Core.Recognition.RecognitionAssets.Get("GameLoading", "WelkinMoon", ra)));
            Step("GirlMoon", () => ra.Find(BetterGenshinImpact.Core.Recognition.RecognitionAssets.Get("GameLoading", "GirlMoon", ra)));

            var start = Stopwatch.GetTimestamp();
            for (var i = 0; i < 20; i++)
            {
                BetterGenshinImpact.GameTask.Common.BgiVision.Bv.DetectChatUi(content.CaptureRectArea);
            }

            Console.WriteLine($"  {"DetectChatUi",-12} {Stopwatch.GetElapsedTime(start).TotalMilliseconds / 20,7:0.00} ms per frame");
        }
    }

    /// <summary>PaddleOCR detection on a 1080p-sized input with different ONNX Runtime settings.</summary>
    private static void OnnxBench()
    {
        var model = Directory.GetFiles(Path.Combine(AppContext.BaseDirectory, "Assets", "Model", "PaddleOCR", "Det"), "*.onnx", SearchOption.AllDirectories).First();
        Console.WriteLine($"\nPaddleOCR detection ({Path.GetFileName(Path.GetDirectoryName(model))}/{Path.GetFileName(model)}), input 1x3x1088x1920:");
        var input = new Microsoft.ML.OnnxRuntime.Tensors.DenseTensor<float>(new[] { 1, 3, 1088, 1920 });
        var rng = new Random(1);
        for (var i = 0; i < input.Length; i++)
        {
            input.SetValue(i, (float)rng.NextDouble());
        }

        void Run(string name, Action<Microsoft.ML.OnnxRuntime.SessionOptions> configure)
        {
            try
            {
                using var options = new Microsoft.ML.OnnxRuntime.SessionOptions();
                configure(options);
                var load = Stopwatch.StartNew();
                using var session = new Microsoft.ML.OnnxRuntime.InferenceSession(model, options);
                var inputName = session.InputMetadata.Keys.First();
                var feeds = new[] { Microsoft.ML.OnnxRuntime.NamedOnnxValue.CreateFromTensor(inputName, input) };
                using (session.Run(feeds)) { }
                var loadMs = load.ElapsedMilliseconds;
                var times = new List<double>();
                for (var i = 0; i < 8; i++)
                {
                    var start = Stopwatch.GetTimestamp();
                    using (session.Run(feeds)) { }
                    times.Add(Stopwatch.GetElapsedTime(start).TotalMilliseconds);
                }

                times.Sort();
                Console.WriteLine($"  {name,-34} median {times[4],7:0.0} ms   min {times[0],7:0.0} ms   (load + first run {loadMs} ms)");
            }
            catch (Exception e)
            {
                Console.WriteLine($"  {name,-34} failed: {e.GetBaseException().Message.Split('\n')[0]}");
            }
        }

        Run("CPU, ORT default threads", _ => { });
        Run("CPU, 8 threads (P-cores)", o => o.IntraOpNumThreads = 8);
        Run("CPU, 4 threads", o => o.IntraOpNumThreads = 4);
        Run("CoreML (MLProgram, all units)", o => o.AppendExecutionProvider("CoreML", new Dictionary<string, string> { ["ModelFormat"] = "MLProgram", ["MLComputeUnits"] = "ALL" }));
        Run("CoreML (MLProgram, GPU)", o => o.AppendExecutionProvider("CoreML", new Dictionary<string, string> { ["ModelFormat"] = "MLProgram", ["MLComputeUnits"] = "CPUAndGPU" }));
        Run("CoreML (NeuralNetwork, all units)", o => o.AppendExecutionProvider("CoreML", new Dictionary<string, string> { ["ModelFormat"] = "NeuralNetwork", ["MLComputeUnits"] = "ALL" }));
    }

    private static Mat MakeFrame(string scenario)
    {
        var frame = new Mat(1440, 2560, MatType.CV_8UC3, new Scalar(80, 110, 70));
        if (scenario == "pick-up prompt")
        {
            // upstream's 1080p F-key template, scaled to 1440p, placed in the pick-up region with a text line
            var path = Path.Combine(AppContext.BaseDirectory, "GameTask", "AutoPick", "Assets", "1920x1080", "F.png");
            using var key = Cv2.ImRead(path);
            using var scaled = new Mat();
            Cv2.Resize(key, scaled, new OpenCvSharp.Size(key.Width * 4 / 3, key.Height * 4 / 3));
            var at = new Rect(1105 * 4 / 3, 520 * 4 / 3, scaled.Width, scaled.Height);
            using (var target = new Mat(frame, at))
            {
                scaled.CopyTo(target);
            }

            Cv2.PutText(frame, "Sweet Flower", new OpenCvSharp.Point(at.X + 160, at.Y + 30), HersheyFonts.HersheySimplex, 1.0, Scalar.White, 2);
        }

        return frame;
    }

    private static void Bench(string name, Action action, int count = 200)
    {
        action(); // warm up
        var samples = new double[count];
        for (var i = 0; i < count; i++)
        {
            var start = Stopwatch.GetTimestamp();
            action();
            samples[i] = Stopwatch.GetElapsedTime(start).TotalMilliseconds;
        }

        Array.Sort(samples);
        Console.WriteLine($"  {name,-38} {samples[count / 2],8:0.000} ms  {samples[(int)(count * 0.95)],8:0.000} ms");
    }

    private static string? Value(string[] args, string name)
    {
        var index = Array.IndexOf(args, name);
        return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
    }

    /// <summary>Hands out copies of one frame and records when each capture happened.</summary>
    private sealed class TimedCapture(Mat frame) : IGameCapture
    {
        private readonly List<long> _stamps = [];

        public bool IsCapturing => true;

        public void Start(nint hWnd, Dictionary<string, object>? settings = null) { }

        public GameCaptureFrame? Capture()
        {
            lock (_stamps)
            {
                _stamps.Add(Stopwatch.GetTimestamp());
            }

            return new GameCaptureFrame(frame.Clone());
        }

        public List<double> Gaps()
        {
            lock (_stamps)
            {
                return _stamps.Zip(_stamps.Skip(1), (a, b) => Stopwatch.GetElapsedTime(a, b).TotalMilliseconds).ToList();
            }
        }

        public void Stop() { }

        public void Dispose() { }
    }

    /// <summary>
    /// Always-foreground window that still makes the same native query the real window makes, so its
    /// cost is part of the measurement.
    /// </summary>
    private sealed class TimedWindow(GameViewport viewport, uint windowId) : IGameWindow
    {
        public long Calls;
        public TimeSpan Time;

        private T Measure<T>(Func<object?> query, T result)
        {
            var start = Stopwatch.GetTimestamp();
            if (windowId != 0)
            {
                query();
            }

            Time += Stopwatch.GetElapsedTime(start);
            Calls++;
            return result;
        }

        public nint Handle => (nint)windowId;
        public int ProcessId => Environment.ProcessId;
        public GameViewport Viewport => Measure(() => MacGameWindowSelection.GameArea(windowId), viewport);
        public bool IsAlive => Measure(() => MacWindows.Query(new MacWindowInfo { Id = windowId }), true);
        public bool IsForeground => Measure(() => MacWindows.IsFrontmost(windowId), true);
        public bool IsMinimized => Measure(() => MacWindows.Query(new MacWindowInfo { Id = windowId }), false);
        public bool RequiresForeground => true;
        public void Activate() { }
#pragma warning disable CS0067
        public event EventHandler? ViewportChanged;
#pragma warning restore CS0067
        public void Dispose() { }
    }

    /// <summary>Input backend that drops everything, so the test never types into a real window.</summary>
    private sealed class NullInputBackend : IInputBackend
    {
        private readonly NullChannel _channel = new();
        public InputBackendKind Kind => InputBackendKind.Win32;
        public IInputChannel Foreground => _channel;
        public IInputChannel Background => _channel;
        public void ReleaseAll() { }
        public void Dispose() { }

        private sealed class NullChannel : InputChannelBase
        {
            protected override void OnKeyDown(User32.VK key) { }
            protected override void OnKeyUp(User32.VK key) { }
            protected override void OnMouseButton(InputMouseButton button, bool down) { }
            protected override void OnMoveBy(int dx, int dy) { }
            protected override void OnMoveTo(double absX, double absY) { }
            protected override void OnScroll(int clicks) { }
        }
    }
}
