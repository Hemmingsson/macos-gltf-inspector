import Foundation
import GLTFCore
import RendererWebKit

/// Finder icons on the WebKit renderer.
enum WebThumbnail {
    /// Renders through the same page the document window and Quick Look use, so a file's Finder
    /// icon matches how it opens.
    ///
    /// One warm host per extension process, serialized. Folder-scale cold start is ~850 ms/file;
    /// reuse is ~70 ms/file on the same path.
    @MainActor
    private static var shared: SharedHost?
    @MainActor
    private static var renderChain: Task<URL, Error>?

    private struct SharedHost {
        let host: WebRendererHost
        let look: WebPreviewCanvas.Look
    }

    @MainActor
    static func render(url: URL, pixel: Int) async throws -> URL {
        let previous = renderChain
        let work = Task<URL, Error> { @MainActor in
            _ = try? await previous?.value
            return try await renderNow(url: url, pixel: pixel)
        }
        renderChain = work
        return try await work.value
    }

    @MainActor
    private static func renderNow(url: URL, pixel: Int) async throws -> URL {
        let started = CFAbsoluteTimeGetCurrent()
        let host = try await reusedHost(look: .stored(), pixel: pixel)
        let info: WebRendererHost.LoadInfo
        let png: Data
        do {
            info = try await host.load(model: url)
            png = try await host.renderStillPNG(size: pixel)
        } catch {
            // A crashed page, or one still busy on a call that timed out, is dropped so the next
            // file in this process starts a fresh page. A file the page merely rejected keeps the
            // warm host. Either way the error goes back to Quick Look (generic icon).
            if host.isBroken || error as? WebRendererError == .timedOut { shared = nil }
            throw error
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("glb-thumb-\(UUID().uuidString).png")
        // The page's PNG as is (sRGB-tagged by WebKit): no decode and re-encode.
        try png.write(to: fileURL)

        AppLog.info(
            AppLog.webRenderer,
            String(
                format: "thumbnail ready %@ %.0fms %dpx %dB tris=%d",
                url.lastPathComponent, (CFAbsoluteTimeGetCurrent() - started) * 1000,
                pixel, png.count, info.triangles
            )
        )
        return fileURL
    }

    @MainActor
    private static func reusedHost(look: WebPreviewCanvas.Look, pixel: Int) async throws -> WebRendererHost {
        if let shared, !shared.host.isBroken, shared.look == look {
            return shared.host
        }
        let host = try WebRendererHost(mode: .still, size: pixel)
        try await host.start()
        // Cheap before the first model: the page loads the HDR after `load`, `renderStill` waits.
        try await host.apply(look)
        shared = SharedHost(host: host, look: look)
        return host
    }
}
