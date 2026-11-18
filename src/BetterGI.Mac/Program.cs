using System;
using System.Linq;
using System.Runtime.InteropServices;
using Avalonia;

namespace BetterGI.Mac;

internal static partial class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        int code;
        if (args.Contains("--selftest"))
        {
            code = SelfTest.Run(args);
        }
        else if (args.Contains("--perftest"))
        {
            code = PerfTest.Run(args);
        }
        else if (args.Contains("--coretest"))
        {
            code = CoreSelfTest.Run(args);
        }
        else
        {
            code = BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        }

        // Leave without running native static destructors: the native libraries the core loads (ONNX Runtime,
        // OpenCV, V8) race each other during normal process teardown and abort with "mutex lock failed",
        // which macOS reports as a crash even though all work is done and saved.
        Serilog.Log.CloseAndFlush();
        Console.Out.Flush();
        Console.Error.Flush();
        ExitNow(code);
        return code;
    }

    [LibraryImport("libc", EntryPoint = "_exit")]
    private static partial void ExitNow(int status);

    public static AppBuilder BuildAvaloniaApp() =>
        AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
}
