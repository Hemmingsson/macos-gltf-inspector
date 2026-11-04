import Darwin
import Foundation
import GLTFCore
import Testing
@testable import RendererMetal

extension PerfBench {
    @MainActor
    @Suite struct MetalBench {
        /// In-process measurements, matching wk.thumb.cold/warm rather than claiming to
        /// measure a fresh extension process. The warm measurement reuses the Metal device.
        @Test func offscreenFirstPixel() async throws {
            let manifest = try PixelDiffManifest.load()
            let look = try PixelDiffWebKit.renderLook(manifest.look)
            let warm = try MetalRenderer()
            for file in BenchCorpus.khronos {
                guard let entry = manifest.entries.first(where: { $0.modelURL == file.url }) else {
                    continue
                }
                let pose = MetalCameraPose(try PixelDiffRun.camera(of: entry))
                var coldTimes: [Double] = [], warmTimes: [Double] = []
                var gpuTimes: [Double] = [], pipelineTimes: [Double] = []
                for _ in 0..<PerfBench.runs {
                    let coldStart = ContinuousClock.now
                    let renderer = try MetalRenderer()
                    try await renderer.load(url: file.url)
                    _ = try renderer.still(look: look, pose: pose, size: PerfBench.stillSize)
                    coldTimes.append(BenchClock.ms(since: coldStart))
                    let previousPipelineTime = warm.pipelineMilliseconds
                    let warmStart = ContinuousClock.now
                    try await warm.load(url: file.url)
                    _ = try warm.still(look: look, pose: pose, size: PerfBench.stillSize)
                    warmTimes.append(BenchClock.ms(since: warmStart))
                    pipelineTimes.append(warm.pipelineMilliseconds - previousPipelineTime)
                    _ = try warm.image(look: look, pose: pose, width: 1920, height: 1080)
                    gpuTimes.append(warm.gpuMilliseconds)
                }
                BenchReport.row("mtl.thumb.cold", file.name, "total", coldTimes)
                BenchReport.row("mtl.thumb.warm", file.name, "total", warmTimes)
                BenchReport.row("mtl.gpu", file.name, "1080p frame ms", gpuTimes)
                BenchReport.row("mtl.pipeline", file.name, "specialize ms", pipelineTimes)
                if let footprint = physicalFootprintMB() {
                    BenchReport.row("mtl.process", file.name, "footprint MB", value: footprint, spread: "test process", n: 1)
                }
            }
        }

        private func physicalFootprintMB() -> Double? {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), raw, &count)
                }
            }
            guard result == KERN_SUCCESS else { return nil }
            return Double(info.phys_footprint) / 1_048_576
        }
    }
}
