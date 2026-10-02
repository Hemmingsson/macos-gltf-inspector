import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// First-pixel surface for Quick Look and the document window: a thumbnail-written App Group
/// poster when one exists. A miss is not a drawn stand-in — the owner shows load copy instead.
///
/// Keyed by path, size, mtime, renderer, and the lighting look that changes the thumbnail
/// (environment / tone / whether the env map is on). Pixel size is not part of the key — the
/// last Finder icon for that identity overwrites.
public enum FirstPixelPreview {
    public static let folderName = "posters"

    public enum Surface: Equatable, Sendable {
        case cachedPoster(URL)
        /// No stored PNG. Bounds are from the JSON header when `POSITION` min/max exist.
        case noPoster(ModelBounds?)
    }

    /// Cache hit is the stored PNG path; a miss carries authored bounds for callers that want
    /// them, but `image` stays nil.
    public static func surface(
        for url: URL,
        renderer: RendererKind,
        look: RenderLook = AppGroupSettings.rendererLook(),
        container: URL = AppGroupSettings.containerURL
    ) -> Surface {
        if let stored = storedURL(for: url, renderer: renderer, look: look, container: container) {
            return .cachedPoster(stored)
        }
        return .noPoster(bounds(for: url))
    }

    /// Cached Finder poster, if one exists. Nil on a miss — do not invent geometry.
    public static func image(
        for url: URL,
        renderer: RendererKind,
        look: RenderLook = AppGroupSettings.rendererLook(),
        container: URL = AppGroupSettings.containerURL
    ) -> CGImage? {
        guard case .cachedPoster(let stored) = surface(
            for: url, renderer: renderer, look: look, container: container
        ) else { return nil }
        return loadPNG(at: stored)
    }

    /// Thumbnail extension writes the PNG it just rendered so Quick Look / the window can show it.
    @discardableResult
    public static func store(
        png: Data,
        for url: URL,
        renderer: RendererKind,
        look: RenderLook = AppGroupSettings.rendererLook(),
        container: URL = AppGroupSettings.containerURL
    ) throws -> URL {
        let destination = fileURL(for: url, renderer: renderer, look: look, container: container)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp")
        try png.write(to: staging, options: .atomic)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: staging, to: destination)
        return destination
    }

    /// RealityKit thumbnails write a `CGImage`; same cache as the WebKit PNG path.
    @discardableResult
    public static func store(
        image: CGImage,
        for url: URL,
        renderer: RendererKind,
        look: RenderLook = AppGroupSettings.rendererLook(),
        container: URL = AppGroupSettings.containerURL
    ) throws -> URL {
        let destination = fileURL(for: url, renderer: renderer, look: look, container: container)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try PNGWriter.write(image, to: destination)
        return destination
    }

    public static func storedURL(
        for url: URL,
        renderer: RendererKind,
        look: RenderLook,
        container: URL = AppGroupSettings.containerURL
    ) -> URL? {
        let stored = fileURL(for: url, renderer: renderer, look: look, container: container)
        return FileManager.default.fileExists(atPath: stored.path) ? stored : nil
    }

    public static func fileURL(
        for url: URL,
        renderer: RendererKind,
        look: RenderLook,
        container: URL = AppGroupSettings.containerURL
    ) -> URL {
        container
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("\(identity(for: url, renderer: renderer, look: look)).png")
    }

    /// Stable hex of path + size + mtime + renderer + look. Not a filesystem path — the group
    /// container is world-readable to the host and both extensions.
    public static func identity(
        for url: URL,
        renderer: RendererKind,
        look: RenderLook
    ) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize.map(Int64.init) ?? 0
        let modified = Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        let fingerprint = [
            renderer.rawValue,
            look.environment.rawValue,
            look.toneMapping.rawValue,
            look.usesEnvironment ? "1" : "0",
            url.standardizedFileURL.path,
            String(size),
            String(modified),
        ].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(fingerprint.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func bounds(for url: URL) -> ModelBounds? {
        guard let json = try? GLBBox.peekDocumentJSON(from: url) else { return nil }
        return ModelBounds.from(json: json)
    }

    private static func loadPNG(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
