import Foundation
import Testing

/// Opt-in performance bench: `./scripts/dev.sh bench` (sets `GLTF_BENCH=1` for the test runner).
///
/// Skipped by the default `dev.sh test` and free of wall-clock assertions: the renderer suites
/// nested in this one (`PerfBench.WebKitBench`, `PerfBench.RealityKitBench`) only print
/// `bench|…` rows, which `dev.sh bench` turns into a table. Serialized so no two renders share
/// the GPU; numbers are a baseline on whatever else the machine is doing, not a gate.
@Suite(.serialized, .enabled(if: BenchEnvironment.isEnabled, "set GLTF_BENCH=1 (./scripts/dev.sh bench)"))
struct PerfBench {
    /// Repeats per measurement (`GLTF_BENCH_RUNS`, default 3); rows report the median and spread.
    static var runs: Int {
        ProcessInfo.processInfo.environment["GLTF_BENCH_RUNS"].flatMap(Int.init).map { max(1, $0) } ?? 3
    }

    /// Edge of every offscreen still, so window-proxy and thumbnail numbers compare.
    static let stillSize = 512
}

/// Outside `PerfBench`: a suite's own trait cannot name the suite type.
enum BenchEnvironment {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["GLTF_BENCH"] == "1" }
}

/// The files the bench renders: four pinned Khronos samples (texture-heavy and geometry/material
/// heavy) plus the stress files in `~/Downloads` when present. Downloads are never copied into
/// the repo; a missing one is skipped, a missing Khronos sample is an issue.
enum BenchCorpus {
    struct File: Sendable {
        var name: String
        var url: URL
        /// Too heavy for the web page (14 M triangles hangs or kills WebContent).
        var realityKitOnly = false
        /// Worth timing view-mode switches on (geometry, materials, nodes or joints).
        var viewModes = false
    }

    static var files: [File] {
        khronos + stress
    }

    static var khronos: [File] {
        let samples: [(String, Bool)] = [
            ("BoomBox", false),
            ("Corset", true),
            ("BarramundiFish", false),
            ("MetalRoughSpheresNoTextures", true),
        ]
        return samples.compactMap { name, viewModes in
            let url = TestModels.khronosDirectory.appendingPathComponent("\(name)/\(name).glb")
            guard TestFixtures.exists(url) else {
                Issue.record("missing Khronos sample \(name) — ./scripts/fetch-test-models.sh")
                return nil
            }
            // Short enough for the table's file column.
            let short = name == "MetalRoughSpheresNoTextures" ? "MetalRoughSph" : name
            return File(name: short, url: url, viewModes: viewModes)
        }
    }

    /// Stress files by filename prefix (Sketchfab appends a hash).
    static var stress: [File] {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: downloads.path)) ?? []
        let wanted: [(prefix: String, short: String, realityKitOnly: Bool)] = [
            ("Warrior_Girl_2", "WarriorGirl2", true),
            ("Flame_Knight", "FlameKnight", false),
            ("2024_Porsche_992_GT3_R", "Porsche992", false),
            ("EMMA_FROST", "EmmaFrost", false),
        ]
        return wanted.compactMap { item in
            guard let match = names.sorted().first(where: { $0.hasPrefix(item.prefix) && $0.hasSuffix(".glb") })
            else {
                print("bench SKIP \(item.short): not in ~/Downloads")
                return nil
            }
            return File(
                name: item.short,
                url: downloads.appendingPathComponent(match),
                realityKitOnly: item.realityKitOnly,
                viewModes: true
            )
        }
    }
}

/// One `bench|section|file|metric|median|spread|n` line per measurement, in ms.
enum BenchReport {
    static func row(_ section: String, _ file: String, _ metric: String, _ samples: [Double]) {
        guard !samples.isEmpty else { return }
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let spread = sorted.count > 1 ? String(format: "%.0f-%.0f", sorted.first!, sorted.last!) : "-"
        emit(section, file, metric, String(format: "%.1f", median), spread, sorted.count)
    }

    /// A value whose spread is not min–max (e.g. a p95 next to a p50).
    static func row(_ section: String, _ file: String, _ metric: String, value: Double, spread: String, n: Int) {
        emit(section, file, metric, String(format: "%.1f", value), spread, n)
    }

    private static func emit(_ section: String, _ file: String, _ metric: String, _ value: String, _ spread: String, _ n: Int) {
        print("bench|\(section)|\(file)|\(metric)|\(value)|\(spread)|\(n)")
    }
}

/// Wall-clock helpers for the bench.
enum BenchClock {
    static func ms(since start: ContinuousClock.Instant) -> Double {
        ms(ContinuousClock.now - start)
    }

    static func ms(_ duration: Duration) -> Double {
        duration / .milliseconds(1)
    }
}
