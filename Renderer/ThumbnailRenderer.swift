import AppKit

/// Finder thumbnails: one off-screen `ModelView` per process, one request at a time, so a folder
/// of files does not hold a renderer's GPU memory per file. `ThumbnailProvider` writes the
/// image for Quick Look; the tests drive this same type in-process (qlmanage hangs headless).
@MainActor
public final class ThumbnailRenderer {
    private var view: ModelView?
    private var queue: Task<CGImage, Error>?

    public init() {}

    /// `url` framed from the front at `pixel`², lit with the stored Settings look.
    public func render(url: URL, pixel: Int) async throws -> CGImage {
        let previous = queue
        let request = Task {
            _ = try? await previous?.value
            return try await self.renderNow(url: url, pixel: pixel)
        }
        queue = request
        return try await request.value
    }

    private func renderNow(url: URL, pixel: Int) async throws -> CGImage {
        let view = try self.view ?? ModelView(renderer: MetalRenderer())
        self.view = view
        view.frame = NSRect(x: 0, y: 0, width: pixel, height: pixel)
        try await view.apply(.stored())
        try await view.load(url)
        // Thumbnails at Finder sizes match the transmission prepass to the image, not 1024².
        return try view.image(width: pixel, height: pixel, transmissionResolution: pixel <= 256 ? pixel : 1024)
    }
}
