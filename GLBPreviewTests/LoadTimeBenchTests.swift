import CoreGraphics
import Foundation
import Testing
@testable import GLBPreview

/// Timed `EntityLoader.load` for the Quick Look convert path.
/// Skips unless `GLB_LOAD_BENCH=1`. Writes JSON to `GLB_LOAD_BENCH_OUT`.
struct LoadTimeBenchTests {
    @Test(.timeLimit(.minutes(15)))
    @MainActor
    func loadTimeBench() async throws {
        let configURL = URL(fileURLWithPath: "/tmp/glb-preview-load-bench/config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }
        let config = (try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any]) ?? [:]
        let manifestPath = config["manifest"] as? String
            ?? "/Users/mattias/dev/glb-preview/docs/superpowers/reviews/load-time-opt/manifest.json"
        let outPath = config["out"] as? String ?? "/tmp/glb-preview-load-bench/latest.json"
        let label = config["label"] as? String ?? "unlabeled"

        let data = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
        let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let reps = (manifest?["reps"] as? Int) ?? 3
        let includeAnimations = (manifest?["includeAnimations"] as? Bool) ?? true
        let files = (manifest?["files"] as? [[String: Any]]) ?? []
        try #require(!files.isEmpty)

        if let first = files.first, let path = first["path"] as? String {
            let warmup = URL(fileURLWithPath: path)
            _ = try await EntityLoader.load(from: warmup, includeAnimations: includeAnimations)
        }

        var results: [[String: Any]] = []
        for file in files {
            let id = file["id"] as? String ?? "unknown"
            let path = try #require(file["path"] as? String)
            let url = URL(fileURLWithPath: path)
            try #require(FileManager.default.fileExists(atPath: path), "missing \(path)")
            var loadSamples: [Double] = []
            var renderSamples: [Double] = []
            var lastError: String?
            print("LOAD_BENCH file=\(id) path=\(path)")
            for _ in 0..<reps {
                let loadStart = ContinuousClock.now
                do {
                    let model = try await EntityLoader.load(from: url, includeAnimations: includeAnimations)
                    let loadMs = milliseconds(from: loadStart)
                    loadSamples.append(loadMs)
                    let renderStart = ContinuousClock.now
                    let assembled = PreviewCamera.makeTurntable(for: model.entity)
                    let still = try await StillRenderer(
                        root: assembled.pivot,
                        bounds: assembled.bounds,
                        width: 256,
                        height: 256,
                        background: CGColor(gray: 0.94, alpha: 1),
                        padding: PreviewCamera.thumbnailFitPadding,
                        intensityExponent: model.studioIBLExponent
                    )
                    _ = try await still.capture()
                    renderSamples.append(milliseconds(from: renderStart))
                } catch {
                    lastError = String(describing: error)
                }
            }
            func summary(_ samples: [Double]) -> (median: Double?, mean: Double?, p90: Double?) {
                let sorted = samples.sorted()
                guard !sorted.isEmpty else { return (nil, nil, nil) }
                let median = sorted[sorted.count / 2]
                let mean = samples.reduce(0, +) / Double(samples.count)
                let p90 = sorted[min(sorted.count - 1, Int((Double(sorted.count) * 0.9).rounded(.down)))]
                return (median, mean, p90)
            }
            let load = summary(loadSamples)
            let render = summary(renderSamples)
            let totals = zip(loadSamples, renderSamples).map { $0 + $1 }
            let total = summary(totals)
            results.append([
                "id": id,
                "path": path,
                "bytes": (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0,
                "samples_load_ms": loadSamples,
                "samples_first_render_ms": renderSamples,
                "samples_total_ms": totals,
                "median_load_ms": load.median as Any,
                "mean_load_ms": load.mean as Any,
                "p90_load_ms": load.p90 as Any,
                "median_first_render_ms": render.median as Any,
                "median_total_ms": total.median as Any,
                "mean_total_ms": total.mean as Any,
                "file_read_ms": NSNull(),
                "parse_ms": NSNull(),
                "decode_ms": NSNull(),
                "texture_ms": NSNull(),
                "scene_build_ms": NSNull(),
                "gpu_upload_ms": NSNull(),
                "error": lastError as Any,
            ])
            let partial: [String: Any] = [
                "label": label,
                "partial": true,
                "sum_median_total_ms": results.compactMap { $0["median_total_ms"] as? Double }.reduce(0, +),
                "sum_median_load_ms": results.compactMap { $0["median_load_ms"] as? Double }.reduce(0, +),
                "files": results,
            ]
            if let encoded = try? JSONSerialization.data(withJSONObject: partial, options: [.prettyPrinted, .sortedKeys]) {
                try? encoded.write(to: URL(fileURLWithPath: outPath))
            }
        }

        let medians = results.compactMap { $0["median_total_ms"] as? Double }
        let loadMedians = results.compactMap { $0["median_load_ms"] as? Double }
        let payload: [String: Any] = [
            "label": label,
            "started": ISO8601DateFormatter().string(from: Date()),
            "reps": reps,
            "includeAnimations": includeAnimations,
            "sum_median_total_ms": medians.reduce(0, +),
            "sum_median_load_ms": loadMedians.reduce(0, +),
            "sum_median_ms": medians.reduce(0, +),
            "files": results,
        ]
        let encoded = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: outPath).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoded.write(to: URL(fileURLWithPath: outPath))
        print("LOAD_BENCH \(label) sum_median_total_ms=\(medians.reduce(0, +)) sum_median_load_ms=\(loadMedians.reduce(0, +)) out=\(outPath)")
    }

    private func milliseconds(from start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: .now)
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
    }
}
