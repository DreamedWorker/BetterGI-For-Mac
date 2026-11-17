// Stand-ins for upstream helpers that only decorate WPF windows.
using System.Windows;

namespace BetterGenshinImpact.Helpers.Ui
{
    public static class WindowHelper
    {
        public static void TryApplySystemBackdrop(Window window) { }
        public static void CenterOnVisibleOwner(Window window) { }
    }
}
