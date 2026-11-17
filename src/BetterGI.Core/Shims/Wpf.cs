// Stand-ins for the WPF types upstream's non-UI code mentions (config models, mask drawing models,
// dispatcher calls). They carry data only; the Avalonia front end converts them where it draws.
using System;
using System.Threading;
using System.Threading.Tasks;

namespace System.Windows
{
    public enum WindowState { Normal = 0, Minimized = 1, Maximized = 2 }

    public enum Visibility { Visible = 0, Hidden = 1, Collapsed = 2 }

    public enum MessageBoxButton { OK = 0, OKCancel = 1, YesNoCancel = 3, YesNo = 4 }

    public enum MessageBoxResult { None = 0, OK = 1, Cancel = 2, Yes = 6, No = 7 }

    public enum MessageBoxImage { None = 0, Error = 16, Question = 32, Warning = 48, Information = 64 }

    public record struct Point(double X, double Y);

    public record struct Size(double Width, double Height);

    public record struct Vector(double X, double Y);

    public record struct Thickness(double Left, double Top, double Right, double Bottom)
    {
        public Thickness(double uniform) : this(uniform, uniform, uniform, uniform) { }
    }

    public record struct Rect(double X, double Y, double Width, double Height)
    {
        public static Rect Empty => new(double.PositiveInfinity, double.PositiveInfinity, double.NegativeInfinity, double.NegativeInfinity);
        public Rect(Point location, Size size) : this(location.X, location.Y, size.Width, size.Height) { }
        public readonly bool IsEmpty => Width < 0;
        public readonly double Left => X;
        public readonly double Top => Y;
        public readonly double Right => X + Width;
        public readonly double Bottom => Y + Height;
        public readonly Point TopLeft => new(X, Y);
        public readonly Point BottomRight => new(Right, Bottom);
        public readonly Size Size => new(Width, Height);
        public readonly Point Location => new(X, Y);
        public readonly bool Contains(Point point) => point.X >= X && point.X <= Right && point.Y >= Y && point.Y <= Bottom;
        public readonly bool Contains(double x, double y) => Contains(new Point(x, y));
        public readonly bool IntersectsWith(Rect other) =>
            !IsEmpty && !other.IsEmpty && other.Left <= Right && other.Right >= Left && other.Top <= Bottom && other.Bottom >= Top;
    }

    public class DependencyObject;

    public class UIElement : DependencyObject;

    public class FrameworkElement : UIElement
    {
        public double Width { get; set; } = double.NaN;
        public double Height { get; set; } = double.NaN;
        public double MaxHeight { get; set; } = double.PositiveInfinity;
        public object? DataContext { get; set; }
        public object? Tag { get; set; }
        public Thickness Margin { get; set; }
    }

    public enum WindowStartupLocation { Manual = 0, CenterScreen = 1, CenterOwner = 2 }

    /// <summary>
    /// Stand-in for a WPF window. It holds the properties upstream's non-UI code sets and never appears
    /// on screen; windows that matter on macOS are opened by the Avalonia front end instead.
    /// </summary>
    public class Window : FrameworkElement
    {
        public WindowState WindowState { get; set; }
        public WindowStartupLocation WindowStartupLocation { get; set; }
        public string Title { get; set; } = "";
        public Window? Owner { get; set; }
        public object? Content { get; set; }
        public double Left { get; set; }
        public double Top { get; set; }
        public bool IsVisible { get; private set; }
        public bool Topmost { get; set; }
        public event EventHandler? Closed;
        public event EventHandler? SourceInitialized;

        public virtual void Show()
        {
            IsVisible = true;
            SourceInitialized?.Invoke(this, EventArgs.Empty);
        }

        public virtual bool? ShowDialog() => false;

        public virtual bool Activate() => IsVisible;

        public virtual void Hide() => IsVisible = false;

        public virtual void Close()
        {
            var wasVisible = IsVisible;
            IsVisible = false;
            if (wasVisible)
            {
                Closed?.Invoke(this, EventArgs.Empty);
            }
        }
    }

    public static class SystemParameters
    {
        /// <summary>Main display size in points (the Dock and menu bar are not subtracted).</summary>
        public static Rect WorkArea
        {
            get
            {
                var (width, height) = BetterGI.Mac.Platform.MacDisplays.MainSize;
                return new Rect(0, 0, width, height);
            }
        }

        public static double PrimaryScreenWidth => WorkArea.Width;
        public static double PrimaryScreenHeight => WorkArea.Height;
    }

    public static class Clipboard
    {
        public static void SetText(string text) => BetterGI.Mac.Platform.MacClipboard.SetText(text);
        public static void SetDataObject(object data) => SetText(data?.ToString() ?? "");
        public static void SetDataObject(object data, bool copy) => SetDataObject(data);
        public static string GetText() => BetterGI.Mac.Platform.MacClipboard.GetText();
        public static bool ContainsText() => GetText().Length > 0;
        public static void Clear() => SetText("");
    }

    /// <summary>
    /// Stand-in for WPF's Application: exposes the UI dispatcher the front end installed.
    /// </summary>
    public class Application
    {
        public static Application Current { get; } = new();
        public Threading.Dispatcher Dispatcher => Threading.Dispatcher.UiDispatcher;
        public Collections.Generic.Dictionary<object, object?> Resources { get; } = [];
        public Window? MainWindow { get; set; }
        public void Shutdown() => ShutdownRequested?.Invoke();

        /// <summary>The front end subscribes to quit the real application.</summary>
        public static event Action? ShutdownRequested;
    }
}

namespace System.Windows.Threading
{
    public enum DispatcherPriority
    {
        Inactive = 0, SystemIdle, ApplicationIdle, ContextIdle, Background, Input, Loaded, Render, DataBind, Normal, Send,
    }

    public class DispatcherOperation(Task task, Func<bool>? abort = null)
    {
        public Task Task { get; } = task;
        public Runtime.CompilerServices.TaskAwaiter GetAwaiter() => Task.GetAwaiter();
        public void Wait() => Task.Wait();

        /// <summary>Cancels the operation if it has not started; returns false when it already ran or is running.</summary>
        public bool Abort() => abort?.Invoke() ?? false;
    }

    public sealed class DispatcherOperation<T>(Task<T> task, Func<bool>? abort = null) : DispatcherOperation(task, abort)
    {
        public new Task<T> Task { get; } = task;
        public new Runtime.CompilerServices.TaskAwaiter<T> GetAwaiter() => Task.GetAwaiter();
        public T Result => Task.GetAwaiter().GetResult();
    }

    /// <summary>
    /// Stand-in for the WPF dispatcher. The Avalonia front end installs <see cref="Post"/> and
    /// <see cref="HasAccess"/>; until then work runs inline on the calling thread (headless / tests).
    /// </summary>
    public sealed class Dispatcher
    {
        public static Dispatcher UiDispatcher { get; } = new();

        public static Dispatcher CurrentDispatcher => UiDispatcher;

        /// <summary>Queues work on the UI thread. Set by the front end.</summary>
        public static Action<Action>? Post { get; set; }

        /// <summary>True when the caller is on the UI thread. Set by the front end.</summary>
        public static Func<bool>? HasAccess { get; set; }

        public bool CheckAccess() => HasAccess?.Invoke() ?? true;

        public void VerifyAccess()
        {
            if (!CheckAccess())
            {
                throw new InvalidOperationException("The calling thread cannot access this object because a different thread owns it.");
            }
        }

        public bool HasShutdownStarted { get; private set; }

        public event EventHandler? ShutdownStarted;

        /// <summary>Called by the front end when the application is quitting.</summary>
        public void NotifyShutdown()
        {
            HasShutdownStarted = true;
            ShutdownStarted?.Invoke(this, EventArgs.Empty);
        }

        public DispatcherOperation<T> InvokeAsync<T>(Func<T> func, DispatcherPriority priority = DispatcherPriority.Normal)
        {
            var completion = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
            var state = 0; // 0 = queued, 1 = running or done, 2 = aborted
            void Run()
            {
                if (Interlocked.CompareExchange(ref state, 1, 0) != 0)
                {
                    return;
                }

                try
                {
                    completion.SetResult(func());
                }
                catch (Exception e)
                {
                    completion.SetException(e);
                }
            }

            bool Abort()
            {
                if (Interlocked.CompareExchange(ref state, 2, 0) != 0)
                {
                    return false;
                }

                completion.TrySetCanceled();
                return true;
            }

            if (Post is null)
            {
                Run();
            }
            else
            {
                Post(Run);
            }

            return new DispatcherOperation<T>(completion.Task, Abort);
        }

        public DispatcherOperation InvokeAsync(Action action, DispatcherPriority priority, CancellationToken cancellationToken) =>
            InvokeAsync(action, priority);

        public DispatcherOperation InvokeAsync(Action action, DispatcherPriority priority = DispatcherPriority.Normal) =>
            InvokeAsync<object?>(() =>
            {
                action();
                return null;
            }, priority);

        public void Invoke(Action action, DispatcherPriority priority = DispatcherPriority.Normal)
        {
            if (Post is null || CheckAccess())
            {
                action();
                return;
            }

            InvokeAsync(action, priority).Task.GetAwaiter().GetResult();
        }

        public T Invoke<T>(Func<T> func, DispatcherPriority priority = DispatcherPriority.Normal)
        {
            if (Post is null || CheckAccess())
            {
                return func();
            }

            return InvokeAsync(func, priority).Task.GetAwaiter().GetResult();
        }

        /// <summary>WPF semantics: throws TimeoutException when the UI thread does not run the call in time.</summary>
        public T Invoke<T>(Func<T> func, DispatcherPriority priority, CancellationToken cancellationToken, TimeSpan timeout)
        {
            if (Post is null || CheckAccess())
            {
                return func();
            }

            var operation = InvokeAsync(func, priority);
            if (!operation.Task.Wait((int)timeout.TotalMilliseconds, cancellationToken))
            {
                if (operation.Abort())
                {
                    throw new TimeoutException();
                }
            }

            return operation.Task.GetAwaiter().GetResult();
        }

        public object? Invoke(Delegate method, params object?[] args)
        {
            object? result = null;
            Invoke(() => { result = method.DynamicInvoke(args); });
            return result;
        }

        public DispatcherOperation BeginInvoke(Action action, DispatcherPriority priority = DispatcherPriority.Normal) => InvokeAsync(action);

        public DispatcherOperation BeginInvoke(DispatcherPriority priority, Action action) => InvokeAsync(action);

        public DispatcherOperation BeginInvoke(Delegate method, params object?[] args) => InvokeAsync(() => { method.DynamicInvoke(args); });
    }

    /// <summary>
    /// Timer whose Tick is delivered through the dispatcher.
    /// </summary>
    public sealed class DispatcherTimer
    {
        private Timer? _timer;

        public DispatcherTimer() { }

        public DispatcherTimer(DispatcherPriority priority) { }

        public DispatcherTimer(DispatcherPriority priority, Dispatcher dispatcher) { }

        public TimeSpan Interval { get; set; }

        public bool IsEnabled => _timer != null;

        public object? Tag { get; set; }

        public event EventHandler? Tick;

        public void Start()
        {
            Stop();
            var interval = Interval <= TimeSpan.Zero ? TimeSpan.FromMilliseconds(1) : Interval;
            _timer = new Timer(_ => Dispatcher.UiDispatcher.InvokeAsync(() =>
            {
                if (_timer != null)
                {
                    Tick?.Invoke(this, EventArgs.Empty);
                }
            }), null, interval, interval);
        }

        public void Stop()
        {
            _timer?.Dispose();
            _timer = null;
        }
    }
}

namespace System.Windows.Media
{
    public enum Stretch { None = 0, Fill = 1, Uniform = 2, UniformToFill = 3 }

    public struct Color : IEquatable<Color>
    {
        public byte A { get; set; }
        public byte R { get; set; }
        public byte G { get; set; }
        public byte B { get; set; }

        public static Color FromArgb(byte a, byte r, byte g, byte b) => new() { A = a, R = r, G = g, B = b };
        public static Color FromRgb(byte r, byte g, byte b) => FromArgb(255, r, g, b);
        public readonly bool Equals(Color other) => A == other.A && R == other.R && G == other.G && B == other.B;
        public override readonly bool Equals(object? obj) => obj is Color other && Equals(other);
        public override readonly int GetHashCode() => HashCode.Combine(A, R, G, B);
        public static bool operator ==(Color left, Color right) => left.Equals(right);
        public static bool operator !=(Color left, Color right) => !left.Equals(right);
        public override readonly string ToString() => $"#{A:X2}{R:X2}{G:X2}{B:X2}";
    }

    public static class Colors
    {
        public static Color Transparent => Color.FromArgb(0, 255, 255, 255);
        public static Color Black => Color.FromRgb(0, 0, 0);
        public static Color White => Color.FromRgb(255, 255, 255);
        public static Color Red => Color.FromRgb(255, 0, 0);
        public static Color Green => Color.FromRgb(0, 128, 0);
        public static Color Lime => Color.FromRgb(0, 255, 0);
        public static Color Blue => Color.FromRgb(0, 0, 255);
        public static Color Yellow => Color.FromRgb(255, 255, 0);
        public static Color Orange => Color.FromRgb(255, 165, 0);
        public static Color Gray => Color.FromRgb(128, 128, 128);
        public static Color Gold => Color.FromRgb(255, 215, 0);
        public static Color Cyan => Color.FromRgb(0, 255, 255);
        public static Color Magenta => Color.FromRgb(255, 0, 255);
    }

    public static class ColorConverter
    {
        /// <summary>Parses #RGB, #RRGGBB and #AARRGGBB.</summary>
        public static object ConvertFromString(string value)
        {
            var hex = value.Trim().TrimStart('#');
            if (hex.Length == 3)
            {
                hex = string.Concat(hex[0], hex[0], hex[1], hex[1], hex[2], hex[2]);
            }

            if (hex.Length == 6)
            {
                hex = "FF" + hex;
            }

            var argb = Convert.ToUInt32(hex, 16);
            return Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb);
        }
    }

    public abstract class Brush
    {
        public double Opacity { get; set; } = 1;
        public void Freeze() { }
        public bool IsFrozen => true;
    }

    public sealed class SolidColorBrush(Color color) : Brush
    {
        public SolidColorBrush() : this(Colors.Transparent) { }
        public Color Color { get; set; } = color;
    }

    public static class Brushes
    {
        public static SolidColorBrush Transparent { get; } = new(Colors.Transparent);
        public static SolidColorBrush Black { get; } = new(Colors.Black);
        public static SolidColorBrush White { get; } = new(Colors.White);
        public static SolidColorBrush Red { get; } = new(Colors.Red);
        public static SolidColorBrush Green { get; } = new(Colors.Green);
        public static SolidColorBrush Lime { get; } = new(Colors.Lime);
        public static SolidColorBrush Blue { get; } = new(Colors.Blue);
        public static SolidColorBrush Yellow { get; } = new(Colors.Yellow);
        public static SolidColorBrush Orange { get; } = new(Colors.Orange);
        public static SolidColorBrush Gray { get; } = new(Colors.Gray);
        public static SolidColorBrush Gold { get; } = new(Colors.Gold);
    }

    /// <summary>Opaque image handle; the front end decides what it holds.</summary>
    public abstract class ImageSource
    {
        public virtual double Width => 0;
        public virtual double Height => 0;
        public void Freeze() { }
    }

    public class DrawingContext;
}

namespace System.ComponentModel
{
    /// <summary>
    /// WPF's weak-event helper. Subscribes strongly here: the listeners in upstream's non-UI code live as
    /// long as the application.
    /// </summary>
    public static class PropertyChangedEventManager
    {
        public static void AddHandler(INotifyPropertyChanged source, EventHandler<PropertyChangedEventArgs> handler, string propertyName)
        {
            source.PropertyChanged += (sender, e) =>
            {
                if (string.IsNullOrEmpty(e.PropertyName) || e.PropertyName == propertyName)
                {
                    handler(sender, e);
                }
            };
        }

        public static void RemoveHandler(INotifyPropertyChanged source, EventHandler<PropertyChangedEventArgs> handler, string propertyName) { }
    }
}

namespace System.Windows.Media.Imaging
{
    public class BitmapSource : Media.ImageSource
    {
        public int PixelWidth { get; init; }
        public int PixelHeight { get; init; }
        public override double Width => PixelWidth;
        public override double Height => PixelHeight;

        /// <summary>Encoded or raw image bytes, when the producer has them.</summary>
        public byte[]? Data { get; init; }
    }

    public class BitmapImage : BitmapSource
    {
        public Uri? UriSource { get; set; }
    }

    public class WriteableBitmap : BitmapSource;
}

namespace System.Windows.Input
{
    [Flags]
    public enum ModifierKeys { None = 0, Alt = 1, Control = 2, Shift = 4, Windows = 8 }

    public enum MouseButton { Left = 0, Middle = 1, Right = 2, XButton1 = 3, XButton2 = 4 }
}

namespace System.Windows.Controls
{
    public enum ScrollBarVisibility { Disabled = 0, Auto = 1, Hidden = 2, Visible = 3 }

    public class ScrollViewer : FrameworkElement
    {
        public object? Content { get; set; }
        public ScrollBarVisibility VerticalScrollBarVisibility { get; set; }
    }

    public class StackPanel : FrameworkElement
    {
        public Collections.Generic.List<UIElement> Children { get; } = [];
    }
}

namespace System.Windows.Interop
{
    /// <summary>There are no HWNDs on macOS; the handle is always zero.</summary>
    public sealed class WindowInteropHelper(Window window)
    {
        public Window Window { get; } = window;
        public nint Handle => 0;
        public nint EnsureHandle() => 0;
    }
}

namespace System.Windows
{
    /// <summary>WPF data templates are how upstream maps plugin view models to views; inert here.</summary>
    public class DataTemplate(object? dataType)
    {
        public object? DataType { get; } = dataType;
        public FrameworkElementFactory? VisualTree { get; set; }
        public void Seal() { }
    }

    public class DataTemplateKey(object? dataType)
    {
        public object? DataType { get; } = dataType;
        public override bool Equals(object? obj) => obj is DataTemplateKey other && Equals(other.DataType, DataType);
        public override int GetHashCode() => DataType?.GetHashCode() ?? 0;
    }

    public class FrameworkElementFactory(Type type)
    {
        public Type Type { get; } = type;
    }
}

namespace System.Windows.Media.Imaging
{
    public enum BitmapCreateOptions { None = 0 }

    public enum BitmapCacheOption { Default = 0, OnDemand = 0, OnLoad = 1, None = 2 }

    public class BitmapFrame : BitmapSource
    {
        /// <summary>Keeps the encoded bytes; the front end decodes them when it draws.</summary>
        public static BitmapFrame Create(IO.Stream stream, BitmapCreateOptions createOptions, BitmapCacheOption cacheOption)
        {
            using var memory = new IO.MemoryStream();
            stream.CopyTo(memory);
            return new BitmapFrame { Data = memory.ToArray() };
        }
    }
}
