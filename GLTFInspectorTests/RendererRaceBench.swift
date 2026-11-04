import Foundation
import GLTFCore
import Testing
@testable import RendererWebKit

/// Filament against the WebKit page on the same files, the same look and the same 512 px still.
///
/// Sections (`bench|<section>|<file>|<metric>|median|spread|n`):
/// - `race.proc-cold.<renderer>`: the first host in this process — engine or WebContent start,
///   look, `tiny.glb`, one still. Once per process, what a cold Quick Look or Finder pays.
/// - `race.<renderer>`: one warm still host per renderer, as the thumbnail extension keeps —
///   `load` and `still` per file, alternating renderers each run.
///
/// The last run's still per file is written to `.build/renderer-race/<renderer>/<file>.png`.
extension PerfBench {
    @MainActor
    @Suite struct RendererRace {
        enum Renderer: String, CaseIterable {
            case filament, webkit

            @MainActor func makeHost() throws -> any CanvasRendererHost {
                switch self {
                case .filament: FilamentRendererHost(mode: .still, size: PerfBench.stillSize)
                case .webkit: try WebRendererHost(mode: .still, size: PerfBench.stillSize, timeout: .seconds(180))
                }
            }
        }

        static var output: URL {
            TestFixtures.repoRoot.appendingPathComponent(".build/renderer-race")
        }

        /// Every Khronos sample on disk (`.glb` and `.gltf`), the repo's `.gltf` fixtures, and the
        /// `~/Downloads` stress files.
        static var corpus: [BenchCorpus.File] {
            let manager = FileManager.default
            let root = TestModels.khronosDirectory
            let samples = ((try? manager.contentsOfDirectory(atPath: root.path)) ?? []).sorted().compactMap { name -> BenchCorpus.File? in
                let folder = root.appendingPathComponent(name)
                for ext in ["glb", "gltf"] {
                    let url = folder.appendingPathComponent("\(name).\(ext)")
                    if manager.fileExists(atPath: url.path) { return BenchCorpus.File(name: name, url: url) }
                }
                return nil
            }
            let fixtures: [(String, URL)] = [
                ("fx-cube.gltf", TestFixtures.cube),
                ("fx-lights.gltf", TestFixtures.lights),
                ("fx-cameras.gltf", TestFixtures.cameras),
                ("fx-BoxAnimated", TestFixtures.boxAnimated),
            ]
            // Large local files: `GLTF_BENCH_EXTRA=/path/a.glb:/path/b.glb` (never copied into the repo).
            let extra = (ProcessInfo.processInfo.environment["GLTF_BENCH_EXTRA"] ?? "")
                .split(separator: ":").map { URL(fileURLWithPath: String($0)) }
                .filter { manager.fileExists(atPath: $0.path) }
                .map { BenchCorpus.File(name: "x-" + $0.deletingPathExtension().lastPathComponent, url: $0) }
            return samples + fixtures.map { BenchCorpus.File(name: $0.0, url: $0.1) } + BenchCorpus.stress + extra
        }

        @Test func race() async throws {
            let manager = FileManager.default
            for renderer in Renderer.allCases {
                try manager.createDirectory(
                    at: Self.output.appendingPathComponent(renderer.rawValue), withIntermediateDirectories: true
                )
            }

            var hosts: [Renderer: any CanvasRendererHost] = [:]
            for renderer in Renderer.allCases {
                let began = ContinuousClock.now
                let host = try renderer.makeHost()
                try await host.start()
                let started = BenchClock.ms(since: began)
                try await host.apply(.stored())
                try await host.load(model: TestFixtures.tiny)
                _ = try await host.renderStillPNG(size: PerfBench.stillSize)
                let total = BenchClock.ms(since: began)
                BenchReport.row("race.proc-cold.\(renderer.rawValue)", "tiny", "start", [started])
                BenchReport.row("race.proc-cold.\(renderer.rawValue)", "tiny", "first still", [total])
                hosts[renderer] = host
            }

            for file in Self.corpus {
                var load: [Renderer: [Double]] = [:]
                var still: [Renderer: [Double]] = [:]
                var failed: Set<Renderer> = []
                for run in 0..<PerfBench.runs {
                    let order = run.isMultiple(of: 2) ? Renderer.allCases : Renderer.allCases.reversed()
                    for renderer in order where !failed.contains(renderer) {
                        let host = hosts[renderer]!
                        do {
                            let began = ContinuousClock.now
                            try await host.load(model: file.url)
                            let loaded = ContinuousClock.now
                            let png = try await host.renderStillPNG(size: PerfBench.stillSize)
                            load[renderer, default: []].append(BenchClock.ms(loaded - began))
                            still[renderer, default: []].append(BenchClock.ms(since: loaded))
                            if run == PerfBench.runs - 1 {
                                try png.write(to: Self.output.appendingPathComponent("\(renderer.rawValue)/\(file.name).png"))
                            }
                        } catch {
                            failed.insert(renderer)
                            print("bench|race.\(renderer.rawValue)|\(file.name)|FAILED|\(error)|-|0")
                        }
                    }
                }
                for renderer in Renderer.allCases where !failed.contains(renderer) {
                    let loads = load[renderer] ?? []
                    let stills = still[renderer] ?? []
                    BenchReport.row("race.\(renderer.rawValue)", file.name, "load", loads)
                    BenchReport.row("race.\(renderer.rawValue)", file.name, "still", stills)
                    BenchReport.row("race.\(renderer.rawValue)", file.name, "total", zip(loads, stills).map(+))
                }
            }
        }
    }
}
