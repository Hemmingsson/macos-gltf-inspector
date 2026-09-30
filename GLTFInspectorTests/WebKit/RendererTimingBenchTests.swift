import Foundation
import Testing
@testable import GLTFInspector
@testable import RendererWebKit

/// Phased first-paint timings for the WebKit renderer.
///
/// Prints `wk-fp` lines for `scripts/webkit-first-paint-bench.sh`. Not a product assertion
/// suite — missing optional files are skipped, required ones fail.
///
/// `visibleMs` is what Quick Look and a new window wait on: page + IBL + `loadGltf`.
/// `stillMs` is the extra thumbnail snapshot after that.
@MainActor
struct RendererTimingBenchTests {
    private static let repeats = 2
    private static let stillSize = 512

    private struct Asset {
        var name: String
        var url: URL
        var required: Bool
    }

    @Test func webKitFirstPaint() async throws {
        let assets = Self.assets()
        #expect(!assets.isEmpty, "no first-paint fixtures found")

        print("wk-fp header mode name bytesMB pageMs iblMs loadMs parseMs fitMs stillMs visibleMs totalMs px tris")

        let request = Self.request()
        let mode = request.mode
        let wanted = request.asset

        if mode == "proc-cold" {
            let asset = try #require(Self.resolve(wanted, in: assets))
            try await renderCold(asset.url, name: asset.name, mode: "proc-cold")
            return
        }

        // First host in this process is Quick Look / first-window latency.
        // Later "cold" hosts are new WKWebViews in an already-warm WebKit process.
        try await renderCold(TestFixtures.tiny, name: "warmup-tiny", mode: "proc-cold")

        for asset in assets {
            if !FileManager.default.fileExists(atPath: asset.url.path) {
                if asset.required {
                    Issue.record("missing required fixture \(asset.name) at \(asset.url.path)")
                } else {
                    print("wk-fp SKIP \(asset.name)")
                }
                continue
            }
            for _ in 0..<Self.repeats {
                do {
                    try await renderCold(asset.url, name: asset.name, mode: "cold")
                } catch {
                    print("wk-fp FAIL cold \(asset.name) \(error.localizedDescription)")
                    throw error
                }
            }
        }

        let host = try WebRendererHost(mode: .still, size: Self.stillSize, timeout: .seconds(180))
        let tPage = CFAbsoluteTimeGetCurrent()
        try await host.start()
        let tIbl = CFAbsoluteTimeGetCurrent()
        try await host.apply(WebPreviewCanvas.Look())
        print(String(
            format: "wk-fp warmup-host pageMs=%.0f iblMs=%.0f",
            (tIbl - tPage) * 1000,
            (CFAbsoluteTimeGetCurrent() - tIbl) * 1000
        ))
        _ = try await host.load(model: TestFixtures.tiny)
        _ = try await host.renderStill()

        for asset in assets where FileManager.default.fileExists(atPath: asset.url.path) {
            do {
                try await renderWarm(host, asset.url, name: asset.name)
            } catch {
                print("wk-fp FAIL warm \(asset.name) \(error.localizedDescription)")
                throw error
            }
        }
    }

    private static func assets() -> [Asset] {
        let khronos = URL(fileURLWithPath: "/Users/mattias/dev/glb-preview/TestModels/Khronos samples")
        let downloads = URL(fileURLWithPath: "/Users/mattias/Downloads")
        return [
            Asset(name: "tiny.glb", url: TestFixtures.tiny, required: true),
            Asset(
                name: "BoomBox.glb",
                url: khronos.appendingPathComponent("BoomBox/BoomBox.glb"),
                required: true
            ),
            Asset(
                name: "Corset.glb",
                url: khronos.appendingPathComponent("Corset/Corset.glb"),
                required: true
            ),
            Asset(
                name: "Jaguar.glb",
                url: downloads.appendingPathComponent("Jaguar_MK2_cartoon_stylized-bcdb3d9c.glb"),
                required: false
            ),
            Asset(
                name: "Stylized_House.glb",
                url: downloads.appendingPathComponent("Stylized_House-a8939656.glb"),
                required: false
            ),
        ]
    }

    private static func request() -> (mode: String, asset: String?) {
        let env = ProcessInfo.processInfo.environment
        if let mode = env["WK_FP_MODE"] {
            return (mode, env["WK_FP_ASSET"])
        }
        let file = URL(fileURLWithPath: "/tmp/glb-preview-webkit-fp-bench/request")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            return ("full", nil)
        }
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        return (parts.first ?? "full", parts.dropFirst().first)
    }

    private static func resolve(_ wanted: String?, in assets: [Asset]) -> Asset? {
        let name = wanted ?? "tiny.glb"
        return assets.first { $0.name == name }
    }

    @discardableResult
    private func renderCold(_ url: URL, name: String, mode: String) async throws -> Void {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let t0 = CFAbsoluteTimeGetCurrent()
        let host = try WebRendererHost(mode: .still, size: Self.stillSize, timeout: .seconds(180))
        try await host.start()
        let tPage = CFAbsoluteTimeGetCurrent()
        try await host.apply(WebPreviewCanvas.Look())
        let tIbl = CFAbsoluteTimeGetCurrent()
        let info = try await host.load(model: url)
        let tLoad = CFAbsoluteTimeGetCurrent()
        let image = try await host.renderStill()
        let tEnd = CFAbsoluteTimeGetCurrent()
        printLine(
            mode: mode,
            name: name,
            bytes: bytes,
            pageMs: (tPage - t0) * 1000,
            iblMs: (tIbl - tPage) * 1000,
            loadMs: (tLoad - tIbl) * 1000,
            parseMs: info.parseMs,
            fitMs: info.fitMs,
            stillMs: (tEnd - tLoad) * 1000,
            visibleMs: (tLoad - t0) * 1000,
            totalMs: (tEnd - t0) * 1000,
            width: image.width,
            triangles: info.triangles
        )
    }

    private func renderWarm(_ host: WebRendererHost, _ url: URL, name: String) async throws {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let t0 = CFAbsoluteTimeGetCurrent()
        let info = try await host.load(model: url)
        let tLoad = CFAbsoluteTimeGetCurrent()
        let image = try await host.renderStill()
        let tEnd = CFAbsoluteTimeGetCurrent()
        printLine(
            mode: "warm",
            name: name,
            bytes: bytes,
            pageMs: 0,
            iblMs: 0,
            loadMs: (tLoad - t0) * 1000,
            parseMs: info.parseMs,
            fitMs: info.fitMs,
            stillMs: (tEnd - tLoad) * 1000,
            visibleMs: (tLoad - t0) * 1000,
            totalMs: (tEnd - t0) * 1000,
            width: image.width,
            triangles: info.triangles
        )
    }

    private func printLine(
        mode: String,
        name: String,
        bytes: Int,
        pageMs: Double,
        iblMs: Double,
        loadMs: Double,
        parseMs: Int,
        fitMs: Int,
        stillMs: Double,
        visibleMs: Double,
        totalMs: Double,
        width: Int,
        triangles: Int
    ) {
        print(String(
            format: "wk-fp %@ %@ %.1f %.0f %.0f %.0f %d %d %.0f %.0f %.0f %d %d",
            mode,
            name,
            Double(bytes) / 1_000_000,
            pageMs,
            iblMs,
            loadMs,
            parseMs,
            fitMs,
            stillMs,
            visibleMs,
            totalMs,
            width,
            triangles
        ))
    }
}
