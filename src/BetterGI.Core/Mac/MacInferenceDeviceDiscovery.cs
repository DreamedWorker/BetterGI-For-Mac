using System.Collections.Generic;

namespace BetterGenshinImpact.Core.Recognition.ONNX;

// Upstream declares this interface in InferenceDeviceDiscovery.cs next to the DirectML / CUDA probing,
// which is excluded on macOS (see Exclude.props).
public interface IInferenceDeviceDiscovery
{
    IReadOnlyList<InferenceDeviceInfo> GetDevices(InferenceDeviceType engine, string runtimeDirectory);
}

/// <summary>
/// macOS device list: CPU only for now. CoreML execution provider is the planned accelerator.
/// </summary>
public sealed class InferenceDeviceDiscovery : IInferenceDeviceDiscovery
{
    public IReadOnlyList<InferenceDeviceInfo> GetDevices(InferenceDeviceType engine, string runtimeDirectory) =>
        engine == InferenceDeviceType.Cpu ? [ResolvedInferenceRuntime.CpuDevice] : [];
}
