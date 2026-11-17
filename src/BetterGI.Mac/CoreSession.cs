using System;
using System.IO;
using System.Threading.Tasks;
using Avalonia.Threading;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask;
using BetterGenshinImpact.GameTask.Runtime;
using BetterGenshinImpact.Mac;
using BetterGenshinImpact.Service.Interface;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog.Core;
using Serilog.Events;

namespace BetterGI.Mac;

/// <summary>
/// Owns upstream BetterGI's service container inside the macOS app and connects it to Avalonia:
/// the UI dispatcher, message boxes / toasts, and the log view.
/// </summary>
public sealed class CoreSession : IDisposable
{
    private IHost? _host;

    public GameRuntimeService Runtime { get; private set; } = null!;

    public TaskTriggerDispatcher Dispatcher { get; private set; } = null!;

    public AllConfig Config { get; private set; } = null!;

    public IConfigService ConfigService { get; private set; } = null!;

    public IServiceProvider Services => _host!.Services;

    public bool IsReady { get; private set; }

    /// <summary>Builds the container and runs upstream's startup sequence. Call on the UI thread.</summary>
    public async Task StartAsync()
    {
        System.Windows.Threading.Dispatcher.Post = action => Avalonia.Threading.Dispatcher.UIThread.Post(action);
        System.Windows.Threading.Dispatcher.HasAccess = Avalonia.Threading.Dispatcher.UIThread.CheckAccess;

        UiBridge.ToastHandler = (kind, message) => AppLog.Raw($"{DateTime.Now:HH:mm:ss} [{kind}] {message}");
        UiBridge.MessageBoxHandler = (content, title, button, kind, defaultResult) =>
        {
            AppLog.Raw($"{DateTime.Now:HH:mm:ss} [{kind}] {title}: {content}");
            // Dialogs must be created on the UI thread; callers on other threads wait for the answer.
            return Avalonia.Threading.Dispatcher.UIThread.CheckAccess()
                ? Ui.MessageDialog.ShowAsync(content, title, button, kind, defaultResult)
                : Avalonia.Threading.Dispatcher.UIThread.InvokeAsync(() => Ui.MessageDialog.ShowAsync(content, title, button, kind, defaultResult));
        };

        _host = MacAppHost.Build(uiLogSink: new UiLogSink());
        var services = _host.Services;
        ConfigService = services.GetRequiredService<IConfigService>();
        Config = ConfigService.Get();
        Runtime = services.GetRequiredService<GameRuntimeService>();
        Dispatcher = services.GetRequiredService<TaskTriggerDispatcher>();
        await MacAppHost.StartAsync(_host);
        IsReady = true;
    }

    public void Dispose()
    {
        if (_host is null)
        {
            return;
        }

        try
        {
            if (IsReady && Runtime.IsRunning)
            {
                Runtime.StopAsync().Wait(TimeSpan.FromSeconds(3));
            }

            System.Windows.Application.Current.Dispatcher.NotifyShutdown();
            _host.StopAsync(TimeSpan.FromSeconds(3)).Wait(TimeSpan.FromSeconds(4));
        }
        catch (Exception e)
        {
            AppLog.Warn("Shutdown: " + e.Message);
        }

        _host.Dispose();
        _host = null;
    }

    /// <summary>Formats core log events (Information and above) for the log view.</summary>
    private sealed class UiLogSink : ILogEventSink
    {
        public void Emit(LogEvent logEvent)
        {
            using var writer = new StringWriter();
            writer.Write($"{logEvent.Timestamp:HH:mm:ss} [{Short(logEvent.Level)}] ");
            logEvent.RenderMessage(writer);
            if (logEvent.Exception != null)
            {
                writer.Write(" | " + logEvent.Exception.GetBaseException().Message);
            }

            AppLog.Raw(writer.ToString());
        }

        private static string Short(LogEventLevel level) => level switch
        {
            LogEventLevel.Warning => "WRN",
            LogEventLevel.Error => "ERR",
            LogEventLevel.Fatal => "FTL",
            _ => "INF",
        };
    }
}
