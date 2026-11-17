using System;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

namespace BetterGenshinImpact;

/// <summary>
/// macOS counterpart of upstream's App (App.xaml.cs): the static service locator that upstream's
/// non-UI code reaches through App.GetService / App.GetLogger. The front end builds the host and
/// assigns <see cref="ServiceProvider"/> before any upstream code runs.
/// </summary>
public partial class App : System.Windows.Application
{
    private static IServiceProvider? _serviceProvider;

    public static IServiceProvider ServiceProvider
    {
        get => _serviceProvider ?? throw new InvalidOperationException("App.ServiceProvider has not been initialised.");
        set => _serviceProvider = value;
    }

    public static ILogger<T> GetLogger<T>() =>
        _serviceProvider?.GetService<ILogger<T>>() ?? NullLogger<T>.Instance;

    public static T? GetService<T>() where T : class => _serviceProvider?.GetService<T>();

    public static object? GetService(Type type) => _serviceProvider?.GetService(type);
}
