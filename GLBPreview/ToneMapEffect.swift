import Metal
import RealityKit

/// Khronos Sample Viewer tone maps + exposure, applied after RealityKit renders.
/// Host `RealityView` only (macOS 26 `PostProcessEffect`). Not attached in QL/thumbs.
@available(macOS 26, *)
final class ToneMapEffect: PostProcessEffect, @unchecked Sendable {
    private let lock = NSLock()
    private var pipeline: MTLComputePipelineState?
    private var _exposure: Float = 1
    private var _toneMap: ViewerSession.ToneMap = .khronosPBRNeutral

    var exposure: Float {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _exposure
        }
        set {
            lock.lock()
            _exposure = min(max(newValue, 0), 64)
            lock.unlock()
        }
    }

    var toneMap: ViewerSession.ToneMap {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _toneMap
        }
        set {
            lock.lock()
            _toneMap = newValue
            lock.unlock()
        }
    }

    nonisolated func prepare(for device: any MTLDevice) {
        rebuildPipeline(device: device)
    }

    nonisolated func postProcess(context: borrowing PostProcessEffectContext<any MTLCommandBuffer>) {
        rebuildPipeline(device: context.device)
        let pipeline = lockedPipeline()

        var params = ShaderParams(exposure: exposure, mode: toneMap.shaderMode)
        if let pipeline,
           let encoder = context.commandBuffer.makeComputeCommandEncoder()
        {
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(context.sourceColorTexture, index: 0)
            encoder.setTexture(context.targetColorTexture, index: 1)
            encoder.setBytes(&params, length: MemoryLayout<ShaderParams>.stride, index: 0)

            let width = pipeline.threadExecutionWidth
            let height = max(pipeline.maxTotalThreadsPerThreadgroup / width, 1)
            let threadsPerThreadgroup = MTLSize(width: width, height: height, depth: 1)
            let threadsPerGrid = MTLSize(
                width: context.sourceColorTexture.width,
                height: context.sourceColorTexture.height,
                depth: 1
            )
            encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            encoder.endEncoding()
            return
        }

        let blit = context.commandBuffer.makeBlitCommandEncoder()
        blit?.copy(from: context.sourceColorTexture, to: context.targetColorTexture)
        blit?.endEncoding()
    }

    private func lockedPipeline() -> MTLComputePipelineState? {
        lock.lock()
        defer { lock.unlock() }
        return pipeline
    }

    private func rebuildPipeline(device: MTLDevice) {
        lock.lock()
        defer { lock.unlock() }
        guard pipeline == nil else { return }
        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "toneMapPostProcess")
        else { return }
        pipeline = try? device.makeComputePipelineState(function: function)
    }

    private struct ShaderParams {
        var exposure: Float
        var mode: UInt32
    }
}

extension ViewerSession.ToneMap {
    /// Matches `ToneMap.metal` `applyToneMap` cases.
    var shaderMode: UInt32 {
        switch self {
        case .khronosPBRNeutral: 0
        case .acesHillExposureBoost: 1
        case .acesNarkowicz: 2
        case .acesHill: 3
        case .noneLinear: 4
        }
    }
}
