// Same static API as upstream's ThemedMessageBox (View/Windows) and WPF-UI Violeta's Toast,
// forwarded to BetterGenshinImpact.Mac.UiBridge.
using System.Threading.Tasks;
using System.Windows;
using BetterGenshinImpact.Mac;

namespace BetterGenshinImpact.View.Windows
{
    public static class ThemedMessageBox
    {
        public enum MessageBoxIcon { None, Information, Warning, Error, Question, Success }

        private static UiMessageKind Kind(MessageBoxIcon icon) => (UiMessageKind)(int)icon;

        public static MessageBoxResult Show(string content, string title = "提示", MessageBoxButton button = MessageBoxButton.OK,
            MessageBoxIcon icon = MessageBoxIcon.Information, MessageBoxResult defaultResult = MessageBoxResult.None, Window? owner = null) =>
            UiBridge.ShowMessage(content, title, button, Kind(icon), defaultResult);

        public static Task<MessageBoxResult> ShowAsync(string content, string title = "提示", MessageBoxButton button = MessageBoxButton.OK,
            MessageBoxIcon icon = MessageBoxIcon.Information, MessageBoxResult defaultResult = MessageBoxResult.None, Window? owner = null) =>
            UiBridge.ShowMessageAsync(content, title, button, Kind(icon), defaultResult);

        public static void Error(string message, string title = "错误") => Show(message, title, MessageBoxButton.OK, MessageBoxIcon.Error);
        public static MessageBoxResult Error(string message, string title, MessageBoxButton button, MessageBoxResult defaultResult = MessageBoxResult.None) => Show(message, title, button, MessageBoxIcon.Error, defaultResult);
        public static Task<MessageBoxResult> ErrorAsync(string message, string title = "错误") => ShowAsync(message, title, MessageBoxButton.OK, MessageBoxIcon.Error);
        public static Task<MessageBoxResult> ErrorAsync(string message, string title, MessageBoxButton button, MessageBoxResult defaultResult = MessageBoxResult.None) => ShowAsync(message, title, button, MessageBoxIcon.Error, defaultResult);

        public static void Warning(string message, string title = "警告") => Show(message, title, MessageBoxButton.OK, MessageBoxIcon.Warning);
        public static MessageBoxResult Warning(string message, string title, MessageBoxButton button, MessageBoxResult defaultResult = MessageBoxResult.None) => Show(message, title, button, MessageBoxIcon.Warning, defaultResult);
        public static Task<MessageBoxResult> WarningAsync(string message, string title = "警告") => ShowAsync(message, title, MessageBoxButton.OK, MessageBoxIcon.Warning);
        public static Task<MessageBoxResult> WarningAsync(string message, string title, MessageBoxButton button, MessageBoxResult defaultResult = MessageBoxResult.None) => ShowAsync(message, title, button, MessageBoxIcon.Warning, defaultResult);

        public static void Information(string message, string title = "信息") => Show(message, title, MessageBoxButton.OK, MessageBoxIcon.Information);
        public static MessageBoxResult Information(string message, string title, MessageBoxButton button, MessageBoxResult defaultResult = MessageBoxResult.None) => Show(message, title, button, MessageBoxIcon.Information, defaultResult);
        public static Task<MessageBoxResult> InformationAsync(string message, string title = "信息") => ShowAsync(message, title, MessageBoxButton.OK, MessageBoxIcon.Information);
        public static Task<MessageBoxResult> InformationAsync(string message, string title, MessageBoxButton button, MessageBoxResult defaultResult = MessageBoxResult.None) => ShowAsync(message, title, button, MessageBoxIcon.Information, defaultResult);

        public static void Success(string message, string title = "成功") => Show(message, title, MessageBoxButton.OK, MessageBoxIcon.Success);
        public static MessageBoxResult Success(string message, string title, MessageBoxButton button, MessageBoxResult defaultResult = MessageBoxResult.None) => Show(message, title, button, MessageBoxIcon.Success, defaultResult);
        public static Task<MessageBoxResult> SuccessAsync(string message, string title = "成功") => ShowAsync(message, title, MessageBoxButton.OK, MessageBoxIcon.Success);
        public static Task<MessageBoxResult> SuccessAsync(string message, string title, MessageBoxButton button, MessageBoxResult defaultResult = MessageBoxResult.None) => ShowAsync(message, title, button, MessageBoxIcon.Success, defaultResult);

        public static MessageBoxResult Question(string message, string title, MessageBoxButton button, MessageBoxResult defaultResult = MessageBoxResult.None) => Show(message, title, button, MessageBoxIcon.Question, defaultResult);
        public static Task<MessageBoxResult> QuestionAsync(string message, string title = "确认") => ShowAsync(message, title, MessageBoxButton.YesNo, MessageBoxIcon.Question);
        public static Task<MessageBoxResult> QuestionAsync(string message, string title, MessageBoxButton button, MessageBoxResult defaultResult = MessageBoxResult.None) => ShowAsync(message, title, button, MessageBoxIcon.Question, defaultResult);
    }
}

namespace Wpf.Ui.Violeta.Controls
{
    public enum ToastLocation { TopCenter, Center, BottomCenter, TopLeft, TopRight, BottomLeft, BottomRight }

    public static class Toast
    {
        public static void Information(string message, ToastLocation location = ToastLocation.TopCenter, System.Windows.Thickness offsetMargin = default, int time = 3000) => UiBridge.Toast(UiMessageKind.Information, message);
        public static void Success(string message, ToastLocation location = ToastLocation.TopCenter, System.Windows.Thickness offsetMargin = default, int time = 3000) => UiBridge.Toast(UiMessageKind.Success, message);
        public static void Warning(string message, ToastLocation location = ToastLocation.TopCenter, System.Windows.Thickness offsetMargin = default, int time = 3000) => UiBridge.Toast(UiMessageKind.Warning, message);
        public static void Error(string message, ToastLocation location = ToastLocation.TopCenter, System.Windows.Thickness offsetMargin = default, int time = 3000) => UiBridge.Toast(UiMessageKind.Error, message);
        public static void Question(string message, ToastLocation location = ToastLocation.TopCenter, System.Windows.Thickness offsetMargin = default, int time = 3000) => UiBridge.Toast(UiMessageKind.Question, message);
    }
}
