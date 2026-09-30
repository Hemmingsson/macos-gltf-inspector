import QuickLookThumbnailing
import CoreGraphics
import Foundation

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
                    AppLog.webRenderer,
                    "thumbnail failed \(url.lastPathComponent) \(error.localizedDescription)"
                )
                handler(nil, error)
            }
        }
    }

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
        let look = AppGroupSettings.rendererLook()
        let host = try await reusedHost(environment: look.environment, toneMapping: look.toneMapping, pixel: pixel)
        let info = try await host.load(model: url)
        let image = try await host.renderStill()

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("glb-thumb-\(UUID().uuidString).png")
        try StillRenderer.writePNG(image, to: fileURL)

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
        if let shared, shared.environment == environment, shared.toneMapping == toneMapping {
            try await shared.host.start(size: pixel)
            return shared.host
        }
        let host = try WebRendererHost(mode: .still)
        try await host.start(size: pixel)
        // Cheap first call: load proceeds without waiting on HDR. `renderStill` joins IBL.
        try await host.setEnvironment(named: environment)
        try await host.send { .setToneMapping(id: $0, name: toneMapping) }
        shared = SharedHost(host: host, environment: environment, toneMapping: toneMapping)
        return host
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
        where entry.lastPathComponent.hasPrefix("glb-thumb-") && entry.pathExtension == "png" {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }
}
