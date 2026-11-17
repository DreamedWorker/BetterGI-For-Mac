using System.Threading.Tasks;
using System.Windows;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Layout;
using Avalonia.Media;
using BetterGenshinImpact.Mac;

namespace BetterGI.Mac.Ui;

/// <summary>
/// Modal message box for the core's ThemedMessageBox / MessageBox calls.
/// </summary>
public static class MessageDialog
{
    public static async Task<MessageBoxResult> ShowAsync(string content, string title, MessageBoxButton button,
        UiMessageKind kind, MessageBoxResult defaultResult)
    {
        var owner = (Avalonia.Application.Current?.ApplicationLifetime as IClassicDesktopStyleApplicationLifetime)?.MainWindow;
        var result = defaultResult != MessageBoxResult.None
            ? defaultResult
            : button is MessageBoxButton.OK ? MessageBoxResult.OK : MessageBoxResult.Cancel;

        var window = new Avalonia.Controls.Window
        {
            Title = string.IsNullOrEmpty(title) ? "BetterGI" : title,
            Width = 460,
            SizeToContent = SizeToContent.Height,
            CanResize = false,
            WindowStartupLocation = owner is null ? Avalonia.Controls.WindowStartupLocation.CenterScreen : Avalonia.Controls.WindowStartupLocation.CenterOwner,
        };

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right };
        void Add(string text, MessageBoxResult value, bool accent = false)
        {
            var control = new Button { Content = text, MinWidth = 80, HorizontalContentAlignment = HorizontalAlignment.Center };
            if (accent)
            {
                control.Classes.Add("accent");
            }

            control.Click += (_, _) =>
            {
                result = value;
                window.Close();
            };
            buttons.Children.Add(control);
        }

        switch (button)
        {
            case MessageBoxButton.OKCancel:
                Add("取消 Cancel", MessageBoxResult.Cancel);
                Add("确定 OK", MessageBoxResult.OK, true);
                break;
            case MessageBoxButton.YesNo:
                Add("否 No", MessageBoxResult.No);
                Add("是 Yes", MessageBoxResult.Yes, true);
                break;
            case MessageBoxButton.YesNoCancel:
                Add("取消 Cancel", MessageBoxResult.Cancel);
                Add("否 No", MessageBoxResult.No);
                Add("是 Yes", MessageBoxResult.Yes, true);
                break;
            default:
                Add("确定 OK", MessageBoxResult.OK, true);
                break;
        }

        var prefix = kind switch
        {
            UiMessageKind.Error => "⛔  ",
            UiMessageKind.Warning => "⚠️  ",
            UiMessageKind.Question => "❓  ",
            UiMessageKind.Success => "✅  ",
            _ => "",
        };
        window.Content = new StackPanel
        {
            Margin = new Avalonia.Thickness(20),
            Spacing = 18,
            Children =
            {
                new ScrollViewer
                {
                    MaxHeight = 360,
                    Content = new SelectableTextBlock { Text = prefix + content, TextWrapping = TextWrapping.Wrap },
                },
                buttons,
            },
        };

        if (owner is { IsVisible: true })
        {
            await window.ShowDialog(owner);
        }
        else
        {
            var closed = new TaskCompletionSource();
            window.Closed += (_, _) => closed.TrySetResult();
            window.Show();
            await closed.Task;
        }

        return result;
    }
}
