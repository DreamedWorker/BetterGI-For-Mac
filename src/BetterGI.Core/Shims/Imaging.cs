// Replacements for upstream's WPF / GDI image helpers (Helpers/Extensions/BitmapExtension.cs,
// MatExtension.cs, Service/ImageSourceDecoder.cs), which are excluded on macOS.
using System.IO;
using System.Threading.Tasks;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using OpenCvSharp;

namespace BetterGenshinImpact.Helpers.Extensions
{
    public static class BitmapExtension
    {
        /// <summary>BGR scalar for OpenCV from a WPF-style colour.</summary>
        public static Scalar ToScalar(this Color color) => new(color.B, color.G, color.R);

        public static Scalar ToScalar(this System.Drawing.Color color) => new(color.B, color.G, color.R);
    }
}

namespace BetterGenshinImpact.Service
{
    public static class ImageSourceDecoder
    {
        /// <summary>Keeps the encoded bytes; the front end decodes them when it draws.</summary>
        public static Task<ImageSource?> DecodeAsync(byte[] bytes) =>
            Task.FromResult<ImageSource?>(new BitmapImage { Data = bytes });
    }
}
