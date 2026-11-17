// Empty marker types for UI classes that upstream's task code only names (typeof(...) in attributes,
// nullable window fields). The Avalonia front end supplies the real views.
using System;
using System.Windows.Forms;
using CommunityToolkit.Mvvm.ComponentModel;
using Vanara.PInvoke;

namespace BetterGenshinImpact.View.Pages.SoloTaskSettings
{
    public class AutoBossSettingsView;
    public class AutoDomainSettingsView;
    public class AutoLeyLineOutcropSettingsView;
    public class AutoStygianOnslaughtSettingsView;
    public class ClaimDailyRewardsSettingsView;
    public class CraftCondensedResinSettingsView;
    public class ResinPlanSettingsView;
    public class SereniteaPotSettingsView;
}

namespace BetterGenshinImpact.ViewModel.SoloTaskSettings
{
    public partial class AutoBossSettingsViewModel : ObservableObject;
    public partial class AutoDomainSettingsViewModel : ObservableObject;
    public partial class AutoLeyLineOutcropSettingsViewModel : ObservableObject;
    public partial class AutoStygianOnslaughtSettingsViewModel : ObservableObject;
    public partial class ClaimDailyRewardsSettingsViewModel : ObservableObject;
    public partial class CraftCondensedResinSettingsViewModel : ObservableObject;
    public partial class ResinPlanSettingsViewModel : ObservableObject;
    public partial class SereniteaPotSettingsViewModel : ObservableObject;
}

namespace Wpf.Ui.Controls
{
    public enum WindowBackdropType { None = 0, Auto = 1, Mica = 2, Acrylic = 3, Tabbed = 4 }
}

namespace Gma.System.MouseKeyHook
{
    /// <summary>Same shape as MouseKeyHook's MouseEventExtArgs, as far as upstream reads it.</summary>
    public class MouseEventExtArgs(MouseButtons button, int clicks, int x, int y, int delta) : MouseEventArgs(button, clicks, x, y, delta)
    {
        public bool Handled { get; set; }
        public bool WheelScrolled => Delta != 0;
        public bool Clicked => Clicks > 0;
        public bool IsMouseButtonDown { get; init; }
        public bool IsMouseButtonUp { get; init; }
        public int Timestamp { get; init; }
    }
}
