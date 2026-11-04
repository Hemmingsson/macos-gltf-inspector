import Darwin
import Foundation
import GLTFCore
import Testing
@testable import Renderer

/// Opt-in performance bench: `./scripts/dev.sh bench` (sets `GLTF_BENCH=1` for the test runner).
///
/// Skipped by the default `dev.sh test` and free of wall-clock assertions: it prints
/// `bench|section|file|metric|median|spread|n` rows, which `dev.sh bench` turns into a table.
/// Numbers are a baseline on whatever else the machine is doing, not a gate.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["GLTF_BENCH"] == "1", "set GLTF_BENCH=1 (./scripts/dev.sh bench)"))
struct PerfBench {
    /// Texture-heavy and material-heavy pinned samples.
    static let samples = ["BoomBox", "Corset", "MetalRoughSpheresNoTextures"]
    static let stillSize = 512
    /// Repeats per measurement (`GLTF_BENCH_RUNS`, default 3).
    static var runs: Int {
        ProcessInfo.processInfo.environment["GLTF_BENCH_RUNS"].flatMap(Int.init).map { max(1, $0) } ?? 3
    }

    /// Load + first still on a new renderer (cold) and on one reused renderer (warm), pipeline
    /// specialisation on the warm one, and a 1080p frame's GPU time. In-process, so "cold" is a
    /// fresh renderer, not a fresh extension process.
    @Test func loadAndFirstStill() async throws {
        let manifest = try PixelDiffManifest.load()
        let options = ViewOptions(look: try PixelDiffMetal.renderLook(manifest.look))
        let warm = try MetalRenderer()
        for name in Self.samples {
            let entry = try #require(manifest.entries.first { $0.name == name }, "\(name) is not a pinned sample")
            let pose = MetalCameraPose(try PixelDiffRun.camera(of: entry))
            var cold: [Double] = [], reused: [Double] = [], gpu: [Double] = [], pipelines: [Double] = []
            for _ in 0..<Self.runs {
                let coldStart = ContinuousClock.now
                let renderer = try MetalRenderer()
                try await renderer.load(url: entry.modelURL)
                _ = try renderer.image(options, pose: pose, width: Self.stillSize, height: Self.stillSize)
                cold.append(milliseconds(since: coldStart))

                let pipelineBefore = warm.pipelineMilliseconds
                let warmStart = ContinuousClock.now
                try await warm.load(url: entry.modelURL)
                _ = try warm.image(options, pose: pose, width: Self.stillSize, height: Self.stillSize)
                reused.append(milliseconds(since: warmStart))
                pipelines.append(warm.pipelineMilliseconds - pipelineBefore)

                _ = try warm.image(options, pose: pose, width: 1920, height: 1080)
                gpu.append(warm.gpuMilliseconds)
            }
            row("still.cold", name, "total", cold)
            row("still.warm", name, "total", reused)
            row("pipeline", name, "specialize ms", pipelines)
            row("gpu", name, "1080p frame ms", gpu)
            if let footprint = physicalFootprintMB() {
                print("bench|process|\(name)|footprint MB|\(String(format: "%.1f", footprint))|test process|1")
            }
        }
    }

    private func row(_ section: String, _ file: String, _ metric: String, _ samples: [Double]) {
        let sorted = samples.sorted()
        guard let first = sorted.first, let last = sorted.last else { return }
        let spread = sorted.count > 1 ? String(format: "%.0f-%.0f", first, last) : "-"
        print("bench|\(section)|\(file)|\(metric)|\(String(format: "%.1f", sorted[sorted.count / 2]))|\(spread)|\(sorted.count)")
    }

    private func milliseconds(since start: ContinuousClock.Instant) -> Double {
        (ContinuousClock.now - start) / .milliseconds(1)
    }

    private func physicalFootprintMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : nil
    }
}
