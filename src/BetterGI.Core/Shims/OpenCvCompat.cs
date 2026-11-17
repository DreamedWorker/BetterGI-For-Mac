// OpenCvSharp 4.11 (upstream) -> 4.13 (the only version with an Apple Silicon runtime):
// Compare() now takes CmpTypes; the old CmpType enum no longer converts. Declaring CmpType here,
// in the namespace that encloses all upstream code, makes upstream's `CmpType.EQ` resolve to CmpTypes.
using OpenCvSharp;

namespace BetterGenshinImpact
{
    public static class CmpType
    {
        public const CmpTypes EQ = CmpTypes.EQ;
        public const CmpTypes GT = CmpTypes.GT;
        public const CmpTypes GE = CmpTypes.GE;
        public const CmpTypes LT = CmpTypes.LT;
        public const CmpTypes LE = CmpTypes.LE;
        public const CmpTypes NE = CmpTypes.NE;
    }
}

namespace BetterGenshinImpact.Platform.Wine
{
    /// <summary>Upstream's Wine-on-Linux add-on (BetterGI itself running in Wine). Never the case here.</summary>
    public static class WinePlatformAddon
    {
        public static bool IsRunningOnWine => false;
    }
}
