// Stand-ins for the WPF-UI (Violeta) types upstream's non-UI code mentions.
using System.Collections.Generic;
using System.Linq;

namespace Wpf.Ui.Violeta.Controls
{
    /// <summary>Node of a cascading (multi-level) picker: plain data.</summary>
    public interface ICascadingItem
    {
        string? Header { get; }
        string? Label => Header;
        object? Tag { get; }
        IReadOnlyList<ICascadingItem>? Children { get; }
    }

    public class CascadingItem : ICascadingItem
    {
        public CascadingItem(string? header) => Header = header;

        public CascadingItem(string? header, IEnumerable<ICascadingItem>? children)
        {
            Header = header;
            Children = children?.ToList();
        }

        public string? Header { get; set; }
        public string? Label => Header;
        public object? Tag { get; set; }
        public IReadOnlyList<ICascadingItem>? Children { get; set; }
    }
}

namespace System.Windows.Controls.Primitives { }
namespace Windows.Networking.PushNotifications { }
