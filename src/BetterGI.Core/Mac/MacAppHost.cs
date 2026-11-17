using System;
using System.IO;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Service.Instance;
using BetterGenshinImpact.ViewModel.Pages;
using BetterGI.Mac.Platform;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace BetterGenshinImpact.Mac;

/// <summary>
/// macOS composition root: what upstream's App.xaml.cs does at startup, without WPF.
/// </summary>
public static class MacAppHost
{
    /// <summary>
    /// Folder for everything BetterGI writes (User/, Data/, config). Upstream keeps this next to the
    /// executable; a macOS app bundle must not be written to, so it lives in Application Support.
    /// </summary>
    public static string DefaultDataRoot => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Library", "Application Support", "BetterGI");

    /// <summary>
    /// Builds the service container and publishes it through <see cref="App.ServiceProvider"/>.
    /// </summary>
    /// <param name="dataRoot">Writable root; defaults to <see cref="DefaultDataRoot"/>.</param>
    /// <param name="configure">Extra registrations from the front end (applied last, so they win).</param>
    /// <param name="uiLogSink">Receives Information-and-above log events for the front end's log view.</param>
    public static IHost Build(string? dataRoot = null, Action<IServiceCollection>? configure = null,
        Serilog.Core.ILogEventSink? uiLogSink = null)
    {
        PrepareDataRoot(dataRoot ?? DefaultDataRoot);

        // Win32 P/Invokes left in unmodified upstream code go to the compatibility layer.
        MacWin32Compat.Install(
            typeof(Vanara.PInvoke.User32).Assembly,
            typeof(Vanara.PInvoke.Gdi32).Assembly,
            typeof(Vanara.PInvoke.Kernel32).Assembly,
            typeof(Vanara.PInvoke.NtDll).Assembly,
            typeof(Vanara.PInvoke.SHCore).Assembly,
            typeof(MacAppHost).Assembly);

        RemoveStaleInstancePipe();
        InstanceBootstrap.Initialize();

        var host = Host.CreateDefaultBuilder()
            .ConfigureLogging(builder => builder.ClearProviders())
            .ConfigureServices((_, services) =>
            {
                MacUpstreamServices.Register(services);

                // View models that upstream's task code resolves from the container.
                services.AddSingleton<TaskSettingsPageViewModel>();
                services.AddSingleton<HomePageViewModel>();
                services.AddSingleton<BetterGenshinImpact.Core.Mask.IMaskWindowHost, MacMaskWindowHost>();
                configure?.Invoke(services);
            })
            .Build();

        if (uiLogSink != null)
        {
            // Upstream's registration assigns Serilog's global logger; add the front end's sink before any
            // category logger is created from it.
            var upstream = Serilog.Log.Logger;
            Serilog.Log.Logger = new Serilog.LoggerConfiguration()
                .MinimumLevel.Debug()
                .WriteTo.Logger(upstream)
                .WriteTo.Sink(uiLogSink, Serilog.Events.LogEventLevel.Information)
                .CreateLogger();
        }

        App.ServiceProvider = host.Services;
        return host;
    }

    /// <summary>
    /// The startup sequence of upstream's App.OnStartup, minus the WPF parts: inference devices, plugins,
    /// hosted services, server time, quest voice.
    /// </summary>
    public static async System.Threading.Tasks.Task StartAsync(IHost host)
    {
        var services = host.Services;
        if (InstanceBootstrap.Current?.Context.IsRoot == true)
        {
            try
            {
                services.GetRequiredService<BetterGenshinImpact.Infrastructure.Storage.PendingCleanupStore>().ExecutePending();
            }
            catch (Exception e)
            {
                Serilog.Log.Warning(e, "执行推迟的存储清理失败，已跳过且不影响程序启动。");
            }
        }

        await services.GetRequiredService<BetterGenshinImpact.Core.Recognition.ONNX.InferenceRuntimeService>().InitializeAsync();
        services.GetRequiredService<BetterGenshinImpact.Core.Plugins.Hosting.PluginManager>().Initialize();
        await host.StartAsync();
        BetterGenshinImpact.Helpers.ServerTimeHelper.Initialize(
            services.GetRequiredService<BetterGenshinImpact.Helpers.IServerTimeProvider>());
        services.GetRequiredService<BetterGenshinImpact.Service.QuestVoiceService>();
    }

    /// <summary>
    /// .NET named pipes are Unix domain sockets on macOS, and the socket file outlives a process that
    /// did not shut down cleanly. Upstream then takes the leftover for a running root instance and exits.
    /// If nothing answers on the socket, it is stale and is removed.
    /// </summary>
    private static void RemoveStaleInstancePipe()
    {
        var path = Path.Combine(Path.GetTempPath(), "CoreFxPipe_" + InstancePipeNames.ForCurrentUser());
        if (!File.Exists(path))
        {
            return;
        }

        try
        {
            using var socket = new System.Net.Sockets.Socket(System.Net.Sockets.AddressFamily.Unix,
                System.Net.Sockets.SocketType.Stream, System.Net.Sockets.ProtocolType.Unspecified);
            socket.Connect(new System.Net.Sockets.UnixDomainSocketEndPoint(path));
            // a live root instance answered: leave it to upstream's activation forwarding
        }
        catch (System.Net.Sockets.SocketException)
        {
            File.Delete(path);
        }
    }

    /// <summary>
    /// Points upstream's path helper at the writable root and links the read-only resource folders
    /// shipped with the application (Assets, GameTask) into it, so upstream's relative paths resolve.
    /// </summary>
    private static void PrepareDataRoot(string dataRoot)
    {
        Directory.CreateDirectory(dataRoot);
        Global.StartUpPath = dataRoot;

        foreach (var name in new[] { "Assets", "GameTask" })
        {
            var source = Path.Combine(AppContext.BaseDirectory, name);
            var link = Path.Combine(dataRoot, name);
            if (!Directory.Exists(source))
            {
                continue;
            }

            var info = new DirectoryInfo(link);
            if (info.Exists && info.LinkTarget is null)
            {
                continue; // a real folder the user put there: leave it alone
            }

            if (info.LinkTarget != source)
            {
                if (info.LinkTarget != null)
                {
                    info.Delete();
                }

                Directory.CreateSymbolicLink(link, source);
            }
        }
    }
}
