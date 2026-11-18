using System;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using OpenCvSharp;

namespace BetterGenshinImpact.Mac;

/// <summary>
/// Parallel replacement for <c>Cv2.MatchTemplate</c>.
/// <para>
/// On Windows, OpenCV's template matching is accelerated by Intel IPP. The Apple Silicon build has no IPP
/// and runs it on a single core: a 42×42 colour template over a 1080p frame takes ~100 ms, and upstream
/// matches templates constantly in triggers and tasks. Here the result rows are split into horizontal
/// strips matched concurrently on the performance cores. Each score depends only on the image window
/// under that position, so the result is the same as one call on the whole image.
/// </para>
/// Upstream's call sites are redirected here by scripts/extract-upstream-members.py.
/// </summary>
public static class FastMatch
{
    /// <summary>Below this many multiply-adds the thread hand-off costs more than it saves.</summary>
    private const long MinWorkForParallel = 4_000_000;

    /// <summary>Each strip should give a core enough rows to be worth it.</summary>
    private const int MinRowsPerStrip = 48;

    private static readonly int Workers = Math.Clamp(PerformanceCores(), 2, 16);

    public static void MatchTemplate(Mat image, Mat templ, Mat result, TemplateMatchModes method, Mat? mask = null)
    {
        var rows = image.Rows - templ.Rows + 1;
        var cols = image.Cols - templ.Cols + 1;
        var strips = rows <= 0 ? 0 : Math.Min(Workers, rows / MinRowsPerStrip);
        var work = (long)Math.Max(rows, 0) * Math.Max(cols, 0) * templ.Rows * templ.Cols * Math.Max(1, image.Channels());
        if (strips < 2 || cols <= 0 || work < MinWorkForParallel || image.Dims > 2)
        {
            Cv2.MatchTemplate(image, templ, result, method, mask);
            return;
        }

        result.Create(rows, cols, MatType.CV_32FC1);
        Parallel.For(0, strips, new ParallelOptions { MaxDegreeOfParallelism = strips }, strip =>
        {
            var first = rows * strip / strips;
            var last = rows * (strip + 1) / strips;
            using var source = new Mat(image, new Rect(0, first, image.Cols, last - first + templ.Rows - 1));
            // A header onto the matching rows of the shared result: OpenCV writes in place because the
            // size and type already match.
            using var target = new Mat(result, new Rect(0, first, cols, last - first));
            Cv2.MatchTemplate(source, templ, target, method, mask);
        });
    }

    [DllImport("libc", EntryPoint = "sysctlbyname")]
    private static extern int SysctlByName(string name, out int value, ref nint size, nint newValue, nint newSize);

    /// <summary>Number of performance cores (Apple Silicon); all cores elsewhere.</summary>
    private static int PerformanceCores()
    {
        try
        {
            nint size = sizeof(int);
            if (OperatingSystem.IsMacOS() && SysctlByName("hw.perflevel0.physicalcpu", out var cores, ref size, 0, 0) == 0 && cores > 0)
            {
                return cores;
            }
        }
        catch
        {
            // fall through
        }

        return Environment.ProcessorCount;
    }
}
