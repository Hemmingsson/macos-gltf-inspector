import CoreGraphics
import Foundation
import GLTFCore
import QuickLookThumbnailing
import RendererWebKit

/// Finder thumbnail principal class. Renders through the same page the document window and Quick
/// Look use, so a file's Finder icon matches how it opens.
class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let scale = max(request.scale, 1)
        let pixel = max(64, Int(max(request.maximumSize.width, request.maximumSize.height) * scale))
        let url = request.fileURL

        // Quick Look copies the image from the handed-off URL but never deletes it, and the
        // extension gets no completion callback — so clear PNGs left by earlier requests.
        Self.sweepStaleThumbnails()

        Task.detached {
            do {
                let fileURL = try await Self.render(url: url, pixel: pixel)
                // Finder's generator reliably consumes `imageFileURL`. The CGContext drawing
                // reply works under `qlmanage -x` but fails there with QLThumbnailError 102 —
                // do not "simplify" this to the drawing reply.
                handler(QLThumbnailReply(imageFileURL: fileURL), nil)
            } catch {
                AppLog.error(
                    AppLog.thumbnail,
                    "thumbnail failed \(url.lastPathComponent) \(error.localizedDescription)"
                )
                handler(nil, error)
            }
        }
    }

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

    /// PNG file for Quick Look to copy.
    @MainActor
    private static func render(url: URL, pixel: Int) async throws -> URL {
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

        let fileURL = outputURL()
        // The page's PNG as is (sRGB-tagged by WebKit): no decode and re-encode.
        try png.write(to: fileURL)
        do {
            try FirstPixelPreview.store(png: png, for: url)
        } catch {
            AppLog.error(AppLog.webRenderer, "poster cache failed \(url.lastPathComponent): \(error.localizedDescription)")
        }

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

    private static let outputPrefix = "glb-thumb-"

    /// A fresh temp PNG path for one reply. `sweepStaleThumbnails` clears these later.
    static func outputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(outputPrefix)\(UUID().uuidString).png")
    }

    /// Remove `glb-thumb-*.png` files older than a minute. Best-effort: the age guard keeps a
    /// concurrent request's just-written file from being deleted before Quick Look reads it.
    private static func sweepStaleThumbnails() {
        let tmp = FileManager.default.temporaryDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: tmp,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date(timeIntervalSinceNow: -60)
        for entry in entries
        where entry.lastPathComponent.hasPrefix(outputPrefix) && entry.pathExtension == "png" {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }
}
