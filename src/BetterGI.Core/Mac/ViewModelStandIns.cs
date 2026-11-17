// Hand-written halves of the view models whose static helpers are extracted from upstream
// (see Generated/). They hold only what upstream's task code reads; the Avalonia view models
// will take over these roles as the UI is ported.
using BetterGenshinImpact.Core.Config;
using BetterGenshinImpact.Service;

namespace BetterGenshinImpact.ViewModel.Pages
{
    public partial class KeyBindingsSettingsPageViewModel;

    public partial class MapPathingViewModel;

    public partial class ScriptControlViewModel
    {
        private static AllConfig RootConfig => ConfigService.Config!;
    }

    public partial class TaskSettingsPageViewModel
    {
        public AllConfig Config { get; set; } = ConfigService.Config!;

        /// <summary>Auto-wood rounds, entered on the task page upstream.</summary>
        public int AutoWoodRoundNum { get; set; }

        public int AutoWoodDailyMaxCount { get; set; } = 2000;

        public bool SaveScreenshotOnKeyTick { get; set; }

        /// <summary>Upstream flips the task-page button caption; there is no such button here yet.</summary>
        public static void SetSwitchAutoFightButtonText(bool running) { }
    }

    public partial class HomePageViewModel
    {
        /// <summary>Second-instance activation with command-line options. Not used on macOS yet.</summary>
        public void HandleActivation(object? commandLineOptions) { }
    }
}

namespace BetterGenshinImpact.GameTask.AutoPathing
{
    public partial class PathRecorder;
}
