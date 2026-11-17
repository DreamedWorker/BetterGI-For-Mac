// macOS stand-ins for Windows-only features that upstream's portable code refers to by name.
// Each class says whether it is implemented differently here or is inert for now.
using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using System.Windows;
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.GameTask.Runtime;
using BetterGenshinImpact.Mac;
using BetterGenshinImpact.Service.Notification.Model;
using BetterGenshinImpact.Service.Notifier.Interface;
using BetterGI.Mac.Platform;

namespace BetterGenshinImpact.Model
{
    // The data properties are extracted from upstream (Generated/SettingItem.g.cs).
    public partial class SettingItem
    {
        /// <summary>
        /// Upstream builds WPF controls here. On macOS the Avalonia settings view renders the item from
        /// its data properties, so no control objects are produced.
        /// </summary>
        public List<UIElement> ToControl(dynamic context) => [];
    }
}

namespace BetterGenshinImpact.Core.Script.Dependence
{
    /// <summary>JS API `keyMouseHook`: global key / mouse callbacks. Inert until a macOS event tap exists.</summary>
    public class KeyMouseHook(GameRuntime runtime) : IDisposable
    {
        private readonly GameRuntime _runtime = runtime;

        public void Dispose() { }
    }

    /// <summary>JS API `htmlMask`: HTML overlays in WebView2 windows. Inert on macOS.</summary>
    public class HtmlMask(string workDir)
    {
        private readonly string _workDir = workDir;
    }
}

namespace BetterGenshinImpact.Core.Recorder
{
    public enum KeyMouseRecorderStatus { Start, Recording, Stop }

    /// <summary>Records the user's keyboard / mouse into a macro. Needs a global event tap; not available yet.</summary>
    public class GlobalKeyMouseRecord
    {
        public static GlobalKeyMouseRecord Instance { get; } = new();

        public KeyMouseRecorderStatus Status { get; set; } = KeyMouseRecorderStatus.Stop;

        public Task<bool> StartRecord(GameRuntime runtime, params object?[] _)
        {
            UiBridge.Toast(UiMessageKind.Warning, "Key / mouse recording is not available on macOS yet.");
            return Task.FromResult(false);
        }

        public string StopRecord() => string.Empty;
    }
}

namespace BetterGenshinImpact.View
{
    /// <summary>WebView2 HTML overlay windows. There are none on macOS.</summary>
    public static class HtmlMaskWindow
    {
        public static void CloseAll() { }
    }
}

namespace BetterGenshinImpact.View.Windows
{
    public class ScriptRepoWindow : Window;
}

namespace BetterGenshinImpact.View.Controls.Webview
{
    /// <summary>Panel hosting a WebView2 control. A data holder here; nothing is rendered.</summary>
    public class WebpagePanel
    {
        public string? DownloadFolderPath { get; set; }
        public Action? OnWebViewInitializedAction { get; set; }
        public dynamic WebView => throw new PlatformNotSupportedException("WebView2 is not available on macOS.");
    }

    /// <summary>
    /// WebView2 window. On macOS, pages are opened in the default browser instead; pages that rely on the
    /// WebView2 host bridge (the script repository UI) do not work yet.
    /// </summary>
    public class WebpageWindow : Window
    {
        public WebpagePanel? Panel { get; } = new();

        public dynamic WebView => Panel!.WebView;

        public void NavigateToUri(Uri uri)
        {
            if (uri.Scheme is "http" or "https" && !uri.Host.EndsWith(".local", StringComparison.OrdinalIgnoreCase))
            {
                System.Diagnostics.Process.Start("/usr/bin/open", [uri.ToString()]);
            }
            else
            {
                UiBridge.Toast(UiMessageKind.Warning, "This page needs the embedded web view, which is not available on macOS yet.");
            }
        }

        public void NavigateToFile(string path) =>
            UiBridge.Toast(UiMessageKind.Warning, "This page needs the embedded web view, which is not available on macOS yet.");
    }
}

namespace Microsoft.Web.WebView2.Core
{
    public enum CoreWebView2HostResourceAccessKind { Deny = 0, Allow = 1, DenyCors = 2 }
}

namespace BetterGenshinImpact.Core.Script.WebView
{
    /// <summary>Host object of the script repository web UI. Placeholder: the page is not shown on macOS.</summary>
    public class RepoWebBridge(AllConfig config)
    {
        private readonly AllConfig _config = config;
    }
}

namespace BetterGenshinImpact.GameTask.AutoCombo
{
    /// <summary>Floating window showing the combo tree. Not shown on macOS yet.</summary>
    public sealed class AutoComboTreeWindowService
    {
        public static AutoComboTreeWindowService Instance { get; } = new();

        public void Show() { }

        public void Hide() { }
    }
}

namespace BetterGenshinImpact.GameTask.SkillCd
{
    /// <summary>Draws skill cooldowns on the mask overlay. Not drawn on macOS yet.</summary>
    public static class SkillCdOverlayRenderer
    {
        public static void Update(GameRuntime runtime, object drawingBoard, string overlayKey, object slotCds) { }
    }
}

namespace Wpf.Ui.Controls
{
    public enum MessageBoxResult { None = 0, Primary = 1, Secondary = 2 }

    /// <summary>WPF-UI message box with a primary and a close button, forwarded to the front end.</summary>
    public class MessageBox : Window
    {
        public string CloseButtonText { get; set; } = "Close";
        public string PrimaryButtonText { get; set; } = "";
        public string SecondaryButtonText { get; set; } = "";

        public async Task<MessageBoxResult> ShowDialogAsync()
        {
            var result = await UiBridge.ShowMessageAsync(Content?.ToString() ?? "", Title, MessageBoxButton.OKCancel,
                UiMessageKind.Question, System.Windows.MessageBoxResult.Cancel);
            return result == System.Windows.MessageBoxResult.OK ? MessageBoxResult.Primary : MessageBoxResult.None;
        }
    }
}

namespace System.Windows.Forms
{
    public enum MessageBoxButtons { OK = 0, OKCancel = 1, YesNoCancel = 3, YesNo = 4 }

    public static class MessageBox
    {
        public static void Show(string text, string caption, MessageBoxButtons buttons, MessageBoxIcon icon) =>
            UiBridge.ShowMessage(text, caption, MessageBoxButton.OK,
                icon == MessageBoxIcon.Error ? UiMessageKind.Error : icon == MessageBoxIcon.Warning ? UiMessageKind.Warning : UiMessageKind.Information,
                MessageBoxResult.OK);
    }

    public static class Clipboard
    {
        public static void SetDataObject(object data) => MacClipboard.SetText(data?.ToString() ?? "");
        public static void SetText(string text) => MacClipboard.SetText(text);
        public static string GetText() => MacClipboard.GetText();
        public static void Clear() => MacClipboard.SetText("");
    }

    public static class Control
    {
        public static Keys ModifierKeys
        {
            get
            {
                var keys = Keys.None;
                if (MacInput.IsKeyDown(Vanara.PInvoke.User32.VK.VK_SHIFT)) keys |= Keys.Shift;
                if (MacInput.IsKeyDown(Vanara.PInvoke.User32.VK.VK_CONTROL)) keys |= Keys.Control;
                if (MacInput.IsKeyDown(Vanara.PInvoke.User32.VK.VK_MENU)) keys |= Keys.Alt;
                return keys;
            }
        }
    }
}

namespace Meziantou.Framework.Win32
{
    public enum CredentialPersistence { Session = 1, LocalMachine = 2, Enterprise = 3 }

    public sealed class Credential(string applicationName, string? userName, string? password, string? comment)
    {
        public string ApplicationName { get; } = applicationName;
        public string? UserName { get; } = userName;
        public string? Password { get; } = password;
        public string? Comment { get; } = comment;
    }
}

namespace BetterGenshinImpact.Helpers.Win32
{
    using Meziantou.Framework.Win32;

    /// <summary>Same API as upstream's Windows Credential Manager helper, stored in the macOS login keychain.</summary>
    public static class CredentialManagerHelper
    {
        public static void SaveCredential(string applicationName, string userName, string secret, string comment,
            CredentialPersistence persistence)
        {
            if (!MacKeychain.Set(applicationName, userName, secret))
            {
                throw new InvalidOperationException($"Could not store the credential '{applicationName}' in the keychain.");
            }
        }

        public static Credential? ReadCredential(string applicationName)
        {
            var entry = MacKeychain.Get(applicationName);
            return entry is null ? null : new Credential(applicationName, entry.Value.Account, entry.Value.Secret, null);
        }

        public static void UpdateCredential(string applicationName, string newUserName, string newSecret, string newComment) =>
            SaveCredential(applicationName, newUserName, newSecret, newComment, CredentialPersistence.LocalMachine);

        public static void DeleteCredential(string applicationName) => MacKeychain.Delete(applicationName);
    }
}

namespace BetterGenshinImpact.Pulonia.Services
{
    using BetterGenshinImpact.Helpers.Win32;

    /// <summary>Keeps upstream's class name; credentials go to the macOS login keychain.</summary>
    internal sealed class PuloniaWindowsCredentialVault : IPuloniaCredentialVault
    {
        public void Write(string target, string userName, string password) =>
            CredentialManagerHelper.SaveCredential(target, userName, password, "BetterGI",
                Meziantou.Framework.Win32.CredentialPersistence.LocalMachine);

        public void Delete(string target) => CredentialManagerHelper.DeleteCredential(target);
    }
}

namespace BetterGenshinImpact.Service.Notifier
{
    /// <summary>System notification. Uses the macOS Notification Center through osascript.</summary>
    public class WindowsUwpNotifier(object? tempFileService) : INotifier
    {
        public string Name => "系统通知";

        public Task SendAsync(BaseNotificationData data)
        {
            var text = (data.Message ?? "").Replace("\\", "\\\\").Replace("\"", "\\\"");
            System.Diagnostics.Process.Start("/usr/bin/osascript",
                ["-e", $"display notification \"{text}\" with title \"BetterGI\""]);
            return Task.CompletedTask;
        }
    }
}

namespace BetterGenshinImpact.Helpers
{
    public readonly struct DpiScaleF(float x = 1f, float y = 1f)
    {
        public float X { get; } = x;
        public float Y { get; } = y;
    }

    /// <summary>Display scale of the game window's screen (2 on Retina displays).</summary>
    public static class DpiHelper
    {
        public static float ScaleY => GetScale().Y;

        public static float GetScaleY(nint gameWindowHandle) => GetScale(gameWindowHandle).Y;

        public static DpiScaleF GetScale(nint hWnd = 0)
        {
            var id = hWnd != 0 ? (uint)hWnd : MacGameWindowSelection.ResolveWindowId();
            var scale = id == 0 ? 1f : (float)(MacGameWindowSelection.GameArea(id)?.Scale ?? 1);
            return new DpiScaleF(scale, scale);
        }
    }

    /// <summary>Stable per-machine id (upstream derives it from Windows hardware ids).</summary>
    public static class DeviceIdHelper
    {
        private static readonly Lazy<string> LazyDeviceId = new(() =>
            global::DeviceId.DeviceIdBuilderExtensions.AddMacAddress(global::DeviceId.DeviceIdBuilderExtensions.AddUserName(global::DeviceId.DeviceIdBuilderExtensions.AddMachineName(new global::DeviceId.DeviceIdBuilder()))).ToString());

        public static string DeviceId => LazyDeviceId.Value;
    }
}

namespace BetterGenshinImpact.Infrastructure.WebView
{
    using System.IO;
    using System.Linq;
    using BetterGenshinImpact.Infrastructure.Storage;

    /// <summary>Folder layout of upstream's WebView2 data (same paths; nothing writes there on macOS).</summary>
    public static class WebViewDataFolders
    {
        private static readonly string[] ProfileCacheFolderNames =
            ["Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache"];

        public static IReadOnlyList<string> GetCacheFolders(string profileFolder) =>
            ProfileCacheFolderNames.Select(name => Path.Combine(profileFolder, name)).ToList();

        public static string GetCloudGameFolder(string instanceName) =>
            Path.Combine(AppPaths.WebViewCloudGame, instanceName.Trim());

        public static string GetCloudGameProfileFolder(string instanceName) =>
            Path.Combine(GetCloudGameFolder(instanceName), "EBWebView", "Default");
    }
}

namespace BetterGenshinImpact.GameTask.Runtime.WebPage
{
    using System.Threading;

    /// <summary>Cloud-game web runtime (WebView2). Not available on macOS; never registered.</summary>
    public sealed class WebPageRuntimeProvider : IGameRuntimeProvider
    {
        public GameRuntimeKind Kind => GameRuntimeKind.WebPage;

        public Func<Task>? StopCaptureBeforeCloseAsync { private get; set; }

        public Task<GameRuntime?> AcquireAsync(CancellationToken ct) => Task.FromResult<GameRuntime?>(null);

        public void CloseGame(GameRuntime? current) { }
    }
}

namespace BetterGenshinImpact.Service.ChildSession
{
    /// <summary>Windows child-session (RDP) multi-instance support. Does not exist on macOS.</summary>
    public sealed class ChildSessionService
    {
        public bool TryGetRelativeMouseCaptureBounds(out System.Drawing.Rectangle bounds)
        {
            bounds = default;
            return false;
        }
    }
}
