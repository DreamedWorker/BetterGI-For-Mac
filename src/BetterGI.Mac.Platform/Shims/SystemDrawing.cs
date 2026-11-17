// The part of System.Drawing (GDI+) that upstream's non-UI code uses, implemented without GDI+.
// The real System.Drawing.Common package only works on Windows, so it is not referenced; these types
// take its place under the same names. Value types (Color, Rectangle, RectangleF...) still come from
// System.Drawing.Primitives, which is cross-platform.
//
// Pens and brushes are plain data. Bitmap wraps an OpenCV Mat. Graphics draws with OpenCV; its text
// rendering uses OpenCV's built-in Latin font, so non-ASCII characters (upstream's debug labels are
// partly Chinese) come out as '?'.
using OpenCvSharp;

namespace System.Drawing
{
    public sealed class Pen : IDisposable, ICloneable
    {
        public Pen(Color color) : this(color, 1f) { }

        public Pen(Color color, float width)
        {
            Color = color;
            Width = width;
        }

        public Color Color { get; set; }

        public float Width { get; set; }

        public object Clone() => new Pen(Color, Width);

        public void Dispose() { }
    }

    public static class Pens
    {
        public static Pen Black { get; } = new(Color.Black);
        public static Pen White { get; } = new(Color.White);
        public static Pen Red { get; } = new(Color.Red);
        public static Pen Lime { get; } = new(Color.Lime);
        public static Pen Green { get; } = new(Color.Green);
        public static Pen Blue { get; } = new(Color.Blue);
        public static Pen Yellow { get; } = new(Color.Yellow);
        public static Pen Orange { get; } = new(Color.Orange);
        public static Pen Cyan { get; } = new(Color.Cyan);
        public static Pen Magenta { get; } = new(Color.Magenta);
        public static Pen Gray { get; } = new(Color.Gray);
        public static Pen LightPink { get; } = new(Color.LightPink);
        public static Pen DodgerBlue { get; } = new(Color.DodgerBlue);
        public static Pen Gold { get; } = new(Color.Gold);
    }

    public abstract class Brush : IDisposable
    {
        public void Dispose() { }
    }

    public sealed class SolidBrush(Color color) : Brush
    {
        public Color Color { get; set; } = color;
    }

    [Flags]
    public enum FontStyle { Regular = 0, Bold = 1, Italic = 2, Underline = 4, Strikeout = 8 }

    public enum GraphicsUnit { World = 0, Display = 1, Pixel = 2, Point = 3, Inch = 4, Document = 5, Millimeter = 6 }

    public enum StringAlignment { Near = 0, Center = 1, Far = 2 }

    [Flags]
    public enum StringFormatFlags { None = 0, NoWrap = 0x1000 }

    public enum StringTrimming { None = 0, Character = 1, Word = 2, EllipsisCharacter = 3, EllipsisWord = 4, EllipsisPath = 5 }

    public sealed class StringFormat : IDisposable
    {
        public StringAlignment Alignment { get; set; }
        public StringAlignment LineAlignment { get; set; }
        public StringFormatFlags FormatFlags { get; set; }
        public StringTrimming Trimming { get; set; }
        public void Dispose() { }
    }

    public sealed class Font(string familyName, float size, FontStyle style = FontStyle.Regular, GraphicsUnit unit = GraphicsUnit.Point) : IDisposable
    {
        public string Name { get; } = familyName;
        public float Size { get; } = size;
        public FontStyle Style { get; } = style;
        public GraphicsUnit Unit { get; } = unit;
        public bool Bold => Style.HasFlag(FontStyle.Bold);
        public void Dispose() { }
    }

    public abstract class Image : IDisposable
    {
        /// <summary>Pixel data (BGR or BGRA), owned by this image.</summary>
        public Mat Mat { get; protected init; } = new();

        public int Width => Mat.Width;

        public int Height => Mat.Height;

        public Size Size => new(Width, Height);

        public void Save(string filename) => Mat.SaveImage(filename);

        public void Save(string filename, Imaging.ImageFormat format) => Mat.SaveImage(filename);

        public void Save(IO.Stream stream, Imaging.ImageFormat format)
        {
            Cv2.ImEncode(format.Extension, Mat, out var bytes);
            stream.Write(bytes, 0, bytes.Length);
        }

        public void Dispose()
        {
            Mat.Dispose();
            GC.SuppressFinalize(this);
        }
    }

    public sealed class Bitmap : Image
    {
        public Bitmap(int width, int height) => Mat = new Mat(height, width, MatType.CV_8UC3, Scalar.Black);

        /// <summary>Takes a copy of the Mat.</summary>
        public Bitmap(Mat source) => Mat = source.Clone();

        public Bitmap(string filename) => Mat = Cv2.ImRead(filename, ImreadModes.Unchanged);
    }

    public sealed class Graphics : IDisposable
    {
        private readonly Mat _target;

        private Graphics(Mat target) => _target = target;

        public static Graphics FromImage(Image image) => new(image.Mat);

        private static Scalar ToScalar(Color color) => new(color.B, color.G, color.R, color.A);

        public void FillRectangle(Brush brush, RectangleF rectangle)
        {
            var color = brush is SolidBrush solid ? solid.Color : Color.Black;
            var area = new Rect((int)rectangle.X, (int)rectangle.Y, (int)rectangle.Width, (int)rectangle.Height)
                .Intersect(new Rect(0, 0, _target.Width, _target.Height));
            if (area.Width <= 0 || area.Height <= 0)
            {
                return;
            }

            if (color.A == 255)
            {
                Cv2.Rectangle(_target, area, ToScalar(color), -1);
                return;
            }

            // translucent fill: blend the colour over the existing pixels
            using var region = new Mat(_target, area);
            using var overlay = new Mat(region.Size(), region.Type(), ToScalar(color));
            var alpha = color.A / 255d;
            Cv2.AddWeighted(overlay, alpha, region, 1 - alpha, 0, region);
        }

        public void FillRectangle(Brush brush, Rectangle rectangle) => FillRectangle(brush, (RectangleF)rectangle);

        public void DrawRectangle(Pen pen, Rectangle rectangle) =>
            Cv2.Rectangle(_target, new Rect(rectangle.X, rectangle.Y, rectangle.Width, rectangle.Height), ToScalar(pen.Color),
                Math.Max(1, (int)pen.Width));

        public void DrawString(string text, Font font, Brush brush, RectangleF layout, StringFormat? format = null)
        {
            var color = brush is SolidBrush solid ? solid.Color : Color.White;
            var ascii = new string(text.Select(c => c is >= ' ' and <= '~' ? c : '?').ToArray());
            var scale = Math.Max(0.3, font.Size / 22d);
            var thickness = font.Bold ? 2 : 1;
            var size = Cv2.GetTextSize(ascii, HersheyFonts.HersheySimplex, scale, thickness, out var baseline);
            var x = (format?.Alignment ?? StringAlignment.Near) switch
            {
                StringAlignment.Center => layout.X + (layout.Width - size.Width) / 2,
                StringAlignment.Far => layout.Right - size.Width,
                _ => layout.X,
            };
            var y = (format?.LineAlignment ?? StringAlignment.Near) switch
            {
                StringAlignment.Center => layout.Y + (layout.Height + size.Height) / 2,
                StringAlignment.Far => layout.Bottom - baseline,
                _ => layout.Y + size.Height,
            };
            Cv2.PutText(_target, ascii, new OpenCvSharp.Point((int)x, (int)y), HersheyFonts.HersheySimplex, scale,
                ToScalar(color), thickness, LineTypes.AntiAlias);
        }

        public void DrawString(string text, Font font, Brush brush, float x, float y) =>
            DrawString(text, font, brush, new RectangleF(x, y, _target.Width - x, font.Size * 1.5f));

        public void Dispose() { }
    }
}

namespace System.Drawing.Imaging
{
    public sealed class ImageFormat
    {
        private ImageFormat(string extension) => Extension = extension;

        /// <summary>File extension OpenCV encodes by.</summary>
        public string Extension { get; }

        public static ImageFormat Png { get; } = new(".png");
        public static ImageFormat Bmp { get; } = new(".bmp");
        public static ImageFormat Jpeg { get; } = new(".jpg");
    }
}

namespace OpenCvSharp.Extensions
{
    /// <summary>Same entry point as OpenCvSharp4.Extensions' GDI+ converter.</summary>
    public static class BitmapConverter
    {
        public static System.Drawing.Bitmap ToBitmap(this Mat mat) => new(mat);

        public static Mat ToMat(this System.Drawing.Bitmap bitmap) => bitmap.Mat.Clone();
    }
}
