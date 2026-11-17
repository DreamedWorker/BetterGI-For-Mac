using System;
using System.Threading.Tasks;
using System.Windows;

namespace BetterGenshinImpact.Mac;

public enum UiMessageKind { None, Information, Warning, Error, Question, Success }

/// <summary>
/// The only channel from upstream's non-UI code to the macOS front end for things WPF did directly:
/// message boxes and toasts. The Avalonia app installs the handlers; without them (headless, tests)
/// messages are logged to the console and dialogs return their default result.
/// </summary>
public static class UiBridge
{
    /// <summary>Shows a modal message and returns the pressed button.</summary>
    public static Func<string, string, MessageBoxButton, UiMessageKind, MessageBoxResult, Task<MessageBoxResult>>? MessageBoxHandler { get; set; }

    /// <summary>Shows a transient notification.</summary>
    public static Action<UiMessageKind, string>? ToastHandler { get; set; }

    public static Task<MessageBoxResult> ShowMessageAsync(string content, string title, MessageBoxButton button,
        UiMessageKind kind, MessageBoxResult defaultResult)
    {
        var handler = MessageBoxHandler;
        if (handler is null)
        {
            Console.WriteLine($"[{kind}] {title}: {content}");
            return Task.FromResult(Fallback(button, defaultResult));
        }

        return handler(content, title, button, kind, defaultResult);
    }

    /// <summary>
    /// Blocking variant for upstream's synchronous call sites. Must not be called on the UI thread with a
    /// handler that needs that thread; such callers get the default result instead of a deadlock.
    /// </summary>
    public static MessageBoxResult ShowMessage(string content, string title, MessageBoxButton button,
        UiMessageKind kind, MessageBoxResult defaultResult)
    {
        if (MessageBoxHandler != null && Application.Current.Dispatcher.CheckAccess()
                                      && System.Windows.Threading.Dispatcher.Post != null)
        {
            _ = ShowMessageAsync(content, title, button, kind, defaultResult);
            return Fallback(button, defaultResult);
        }

        return ShowMessageAsync(content, title, button, kind, defaultResult).GetAwaiter().GetResult();
    }

    public static void Toast(UiMessageKind kind, string message)
    {
        var handler = ToastHandler;
        if (handler is null)
        {
            Console.WriteLine($"[{kind}] {message}");
            return;
        }

        handler(kind, message);
    }

    private static MessageBoxResult Fallback(MessageBoxButton button, MessageBoxResult defaultResult) =>
        defaultResult != MessageBoxResult.None
            ? defaultResult
            : button is MessageBoxButton.OK or MessageBoxButton.OKCancel ? MessageBoxResult.OK : MessageBoxResult.None;
}
