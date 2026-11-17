using System;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media.Imaging;
using Avalonia.Threading;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;

namespace BetterGI.Mac;

public partial class App : Application
{
    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            var viewModel = new MainViewModel();
            desktop.MainWindow = new MainWindow { DataContext = viewModel };
            desktop.ShutdownRequested += (_, _) => viewModel.Dispose();
            SnapshotIfRequested(desktop.MainWindow);
        }

        base.OnFrameworkInitializationCompleted();
    }

    /// <summary>
    /// Development aid: BGI_UI_SNAPSHOT=/path/file.png renders the main window to a PNG shortly after start,
    /// which lets the UI be checked without the Screen Recording permission.
    /// </summary>
    private static void SnapshotIfRequested(Window window)
    {
        var path = Environment.GetEnvironmentVariable("BGI_UI_SNAPSHOT");
        if (string.IsNullOrEmpty(path))
        {
            return;
        }

        // BGI_UI_PAGE=<n> switches to that page first (the core needs a few seconds to start).
        var page = int.TryParse(Environment.GetEnvironmentVariable("BGI_UI_PAGE"), out var index) ? index : 0;
        DispatcherTimer.RunOnce(() => (window as MainWindow)?.SelectPage(page), TimeSpan.FromSeconds(6));
        DispatcherTimer.RunOnce(() =>
        {
            var size = new PixelSize((int)window.Bounds.Width * 2, (int)window.Bounds.Height * 2);
            using var bitmap = new RenderTargetBitmap(size, new Vector(192, 192));
            bitmap.Render(window);
            bitmap.Save(path);
        }, TimeSpan.FromSeconds(8));
    }
}
