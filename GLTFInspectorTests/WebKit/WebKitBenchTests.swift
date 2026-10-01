import Foundation
import GLTFCore
import Testing
@testable import RendererWebKit

/// WebKit half of the opt-in bench (restored from the first-paint bench removed in `68328b05`).
///
/// Surfaces: `wk.live` is what a window and Quick Look wait on (new live page → apply → `open`,
/// which draws the first frame); `wk.thumb.cold` is a new still page per icon; `wk.thumb.warm` is
/// one still page reused, as the thumbnail extension does. `wk.mode` is view-mode cost: the first
/// still after a switch (shader compile on first visit) and the page's per-frame CPU p50/p95.
extension PerfBench {
    @MainActor
    @Suite struct WebKitBench {
        private static let timeout: Duration = .seconds(180)
        private static let modes: [(String, RenderViewMode)] = [
            ("shaded", .shaded),
            ("wire", .wireframe),
            ("normals", .channel(.normals)),
            ("uv", .channel(.textureCoordinates)),
            ("base", .channel(.baseColor)),
        ]
        /// Stills per mode after the first; frame p50/p95 cover all of them.
        private static let framesPerMode = 3

        private var files: [BenchCorpus.File] { BenchCorpus.files.filter { !$0.realityKitOnly } }

        @Test func firstPixel() async throws {
            // The first page in a process pays WebContent launch + module compile: Quick Look
            // and the first window. Only one sample exists per process.
            let first = try await live(TestFixtures.tiny)
            BenchReport.row("wk.proc-cold", "tiny", "page", [first.page])
            BenchReport.row("wk.proc-cold", "tiny", "visible", [first.visible])

            for file in files {
                var page: [Double] = [], visible: [Double] = [], parse: [Double] = [], frame: [Double] = []
                var coldTotal: [Double] = [], coldStill: [Double] = []
                for _ in 0..<PerfBench.runs {
                    let run = try await live(file.url)
                    page.append(run.page)
                    visible.append(run.visible)
                    parse.append(Double(run.info.parseMs))
                    frame.append(Double(run.info.firstFrameMs))
                    let cold = try await coldThumbnail(file.url)
                    coldTotal.append(cold.total)
                    coldStill.append(cold.still)
                }
                BenchReport.row("wk.live", file.name, "page", page)
                BenchReport.row("wk.live", file.name, "parse", parse)
                BenchReport.row("wk.live", file.name, "first frame", frame)
                BenchReport.row("wk.live", file.name, "visible", visible)
                BenchReport.row("wk.thumb.cold", file.name, "still", coldStill)
                BenchReport.row("wk.thumb.cold", file.name, "total", coldTotal)
            }

            let warm = try WebRendererHost(mode: .still, size: PerfBench.stillSize, timeout: Self.timeout)
            try await warm.start()
            try await warm.apply(WebPreviewCanvas.Look())
            try await warm.load(model: TestFixtures.tiny)
            _ = try await warm.renderStillPNG()
            for file in files {
                var total: [Double] = []
                for _ in 0..<PerfBench.runs {
                    let start = ContinuousClock.now
                    try await warm.load(model: file.url)
                    _ = try await warm.renderStillPNG()
                    total.append(BenchClock.ms(since: start))
                }
                BenchReport.row("wk.thumb.warm", file.name, "total", total)
            }
        }

        /// One live page per file, every mode visited once: shader programs are cached for the
        /// page's lifetime, so a second round would only measure the steady state again.
        @Test func viewModes() async throws {
            for file in files where file.viewModes {
                let host = try WebRendererHost(mode: .live, size: PerfBench.stillSize, timeout: Self.timeout)
                try await host.start()
                try await host.apply(WebPreviewCanvas.Look())
                try await host.load(model: file.url)
                _ = try await host.renderStillPNG()
                for (name, mode) in Self.modes {
                    _ = try await host.stats()
                    let start = ContinuousClock.now
                    try await host.apply(WebPreviewCanvas.Look(viewMode: mode))
                    _ = try await host.renderStillPNG()
                    let first = BenchClock.ms(since: start)
                    // Drain the compile frame so p50/p95 below are the steady state.
                    _ = try await host.stats()
                    var later: [Double] = []
                    for _ in 0..<Self.framesPerMode {
                        let frameStart = ContinuousClock.now
                        _ = try await host.renderStillPNG()
                        later.append(BenchClock.ms(since: frameStart))
                    }
                    let stats = try await host.stats()
                    BenchReport.row("wk.mode", file.name, "\(name) first still", [first])
                    BenchReport.row("wk.mode", file.name, "\(name) still", later)
                    BenchReport.row(
                        "wk.mode", file.name, "\(name) frame cpu p50",
                        value: stats.frameP50Ms,
                        spread: String(format: "p95 %.1f", stats.frameP95Ms),
                        n: stats.frameCount
                    )
                }
            }
        }

        private struct LiveRun {
            var page: Double
            var visible: Double
            var info: WebRendererHost.LoadInfo
        }

        private func live(_ url: URL) async throws -> LiveRun {
            let start = ContinuousClock.now
            let host = try WebRendererHost(mode: .live, size: PerfBench.stillSize, timeout: Self.timeout)
            try await host.start()
            let page = BenchClock.ms(since: start)
            try await host.apply(WebPreviewCanvas.Look())
            let info = try await host.load(model: url)
            return LiveRun(page: page, visible: BenchClock.ms(since: start), info: info)
        }

        private func coldThumbnail(_ url: URL) async throws -> (total: Double, still: Double) {
            let start = ContinuousClock.now
            let host = try WebRendererHost(mode: .still, size: PerfBench.stillSize, timeout: Self.timeout)
            try await host.start()
            try await host.apply(WebPreviewCanvas.Look())
            try await host.load(model: url)
            let stillStart = ContinuousClock.now
            _ = try await host.renderStillPNG()
            return (BenchClock.ms(since: start), BenchClock.ms(since: stillStart))
        }
    }
}
