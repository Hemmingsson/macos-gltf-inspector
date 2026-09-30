import CoreGraphics
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
        let environment: String
        let toneMapping: String
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
        let look = AppGroupSettings.rendererLook()
        let host = try await reusedHost(environment: look.environment, toneMapping: look.toneMapping, pixel: pixel)
        let info: WebRendererHost.LoadInfo
        let image: CGImage
        do {
            info = try await host.load(model: url)
            image = try await host.renderStill()
        } catch {
            // A timed-out or crashed page stays wedged: drop it so the next file in this process
            // starts a fresh page instead of waiting out another timeout. A file the page merely
            // rejected keeps the warm host. Either way the error goes back to Quick Look, which
            // falls back to the generic icon.
            if host.isBroken { shared = nil }
            throw error
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("glb-thumb-\(UUID().uuidString).png")
        try PNGWriter.write(image, to: fileURL)

        AppLog.info(
            AppLog.webRenderer,
            String(
                format: "thumbnail ready %@ %.0fms %dpx tris=%d",
                url.lastPathComponent, (CFAbsoluteTimeGetCurrent() - started) * 1000,
                image.width, info.triangles
            )
        )
        return fileURL
    }

    @MainActor
    private static func reusedHost(environment: String, toneMapping: String, pixel: Int) async throws -> WebRendererHost {
        if let shared, !shared.host.isBroken,
           shared.environment == environment, shared.toneMapping == toneMapping {
            try await shared.host.start(size: pixel)
            return shared.host
        }
        let host = try WebRendererHost(mode: .still)
        try await host.start(size: pixel)
        // Cheap first call: load proceeds without waiting on HDR. `renderStill` joins IBL.
        try await host.setEnvironment(named: environment)
        try await host.setToneMapping(named: toneMapping)
        shared = SharedHost(host: host, environment: environment, toneMapping: toneMapping)
        return host
    }
}
