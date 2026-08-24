import QuickLookThumbnailing
import RealityKit
import CoreGraphics

class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let scale = max(request.scale, 1)
        let pixel = max(64, Int(max(request.maximumSize.width, request.maximumSize.height) * scale))
        let url = request.fileURL

        // Quick Look copies the image from the handed-off URL but never deletes it, and the
        // extension gets no completion callback — so clear PNGs left by earlier requests.
        Self.sweepStaleThumbnails()

        // SPIKE: route to the WebGL renderer when the marker file is present. Extensions do
        // not inherit the shell environment, and a sandboxed extension cannot see a shared
        // UserDefaults suite either, so a home-directory marker file is the switch:
        //     touch ~/.gltf-inspector-web-thumbnail
        // Absent by default, so the shipping RealityKit path is untouched.
        if Self.usesWebRenderer {
            Task.detached {
                do {
                    let fileURL = try await Self.renderWithWebGL(url: url, pixel: pixel)
                    handler(QLThumbnailReply(imageFileURL: fileURL), nil)
                } catch {
                    AppLog.error(
                        AppLog.webRenderer,
                        "web thumbnail failed \(url.lastPathComponent) \(error)"
                    )
                    handler(nil, error)
                }
            }
            return
        }

        // Detached like Quick Look: prepare/parse off the main actor; RealityKit
        // convert and StillRenderer hop to MainActor inside EntityLoader / capture.
        Task.detached {
            do {
                let model = try await EntityLoader.loadThumbnail(from: url)
                let assembled = await PreviewCamera.makeTurntable(for: model.entity)
                let still = try await StillRenderer(
                    root: assembled.pivot,
                    bounds: assembled.bounds,
                    width: pixel,
                    height: pixel,
                    background: CGColor(gray: 0.94, alpha: 1),
                    padding: PreviewCamera.thumbnailFitPadding,
                    intensityExponent: model.studioIBLExponent
                )
                let image = try await still.capture()
                let fileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("glb-thumb-\(UUID().uuidString).png")
                try await MainActor.run {
                    try StillRenderer.writePNG(image, to: fileURL)
                }
                // Finder / QLThumbnailGenerator reliably consumes imageFileURL.
                // The CGContext drawing reply works in `qlmanage -x` but fails with
                // QLThumbnailError 102 for the generator path Finder uses.
                handler(QLThumbnailReply(imageFileURL: fileURL), nil)
            } catch {
                AppLog.error(AppLog.thumbnail, "thumbnail failed \(url.lastPathComponent) \(error)")
                handler(nil, error)
            }
        }
    }

    // MARK: - WebGL spike

    /// Feature flag for the WebGL thumbnail spike. Remove with the spike.
    ///
    /// A marker file, not a `UserDefaults` suite: the extension is sandboxed, so it reads
    /// preferences from its own container and never sees `defaults write` on a shared suite.
    /// That failed silently — the flag read `false` and the RealityKit path ran while looking
    /// like a successful web render. The existing home-relative read-only exception in
    /// `ThumbnailExtension.entitlements` makes a file in the home directory readable, so this
    /// needs no entitlement change and leaves the sandbox profile untouched for the spike.
    ///
    ///     touch ~/.gltf-inspector-web-thumbnail     # web
    ///     rm    ~/.gltf-inspector-web-thumbnail     # RealityKit
    /// `homeDirectoryForCurrentUser` and `NSHomeDirectory()` both return the *container* home
    /// inside a sandboxed extension, so they look for the marker in the wrong place and
    /// silently report false. `getpwuid` reports the real home, which is also what the
    /// home-relative read-only exception is scoped against.
    private static var usesWebRenderer: Bool {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return false }
        let home = FileManager.default.string(
            withFileSystemRepresentation: dir, length: strlen(dir)
        )
        let marker = URL(fileURLWithPath: home)
            .appendingPathComponent(".gltf-inspector-web-thumbnail")
        return FileManager.default.fileExists(atPath: marker.path)
    }

    /// Renders through `WKWebView` and writes the PNG where Quick Look can pick it up.
    ///
    /// Reply mechanism is deliberately identical to the RealityKit path: Finder's generator
    /// consumes `imageFileURL` reliably, while the `CGContext` drawing reply fails with
    /// `QLThumbnailError 102` there even though it works under `qlmanage -x`.
    @MainActor
    private static func renderWithWebGL(url: URL, pixel: Int) async throws -> URL {
        let started = CFAbsoluteTimeGetCurrent()
        AppLog.info(AppLog.webRenderer, "web thumbnail start \(url.lastPathComponent) \(pixel)px")

        let host = try WebRendererHost(mode: .still)
        try await host.start(size: pixel)
        try await host.setEnvironment(named: "neutral")
        let info = try await host.load(model: url)
        let image = try await host.renderStill()

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("glb-thumb-\(UUID().uuidString).png")
        try StillRenderer.writePNG(image, to: fileURL)

        let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
        AppLog.info(
            AppLog.webRenderer,
            String(
                format: "web thumbnail ready %@ %.0fms total (%d triangles)",
                url.lastPathComponent, elapsed, info.triangles
            )
        )
        return fileURL
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
