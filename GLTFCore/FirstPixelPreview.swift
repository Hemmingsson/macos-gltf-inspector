import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// First-pixel poster for Quick Look and the document window: the PNG the thumbnail extension
/// last wrote to the App Group, when one exists. A miss is not a drawn stand-in — the owner shows
/// load copy instead.
///
/// Keyed by path, size, mtime, and the lighting look that changes the thumbnail
/// (environment and tone mapping). Pixel size is not part of the key — the
/// last Finder icon for that identity overwrites.
public enum FirstPixelPreview {
    public static let folderName = "posters"

    /// Cached Finder poster, if one exists. Nil on a miss — do not invent geometry.
    public static func image(
        for url: URL,
        look: RenderLook = AppGroupSettings.rendererLook(),
        container: URL = AppGroupSettings.containerURL
    ) -> CGImage? {
        guard let stored = storedURL(for: url, look: look, container: container),
              let source = CGImageSourceCreateWithURL(stored as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Thumbnail extension writes the PNG it just rendered so Quick Look / the window can show it.
    @discardableResult
    public static func store(
        png: Data,
        for url: URL,
        look: RenderLook = AppGroupSettings.rendererLook(),
        container: URL = AppGroupSettings.containerURL
    ) throws -> URL {
        let destination = fileURL(for: url, look: look, container: container)
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

    public static func storedURL(
        for url: URL,
        look: RenderLook,
        container: URL = AppGroupSettings.containerURL
    ) -> URL? {
        let stored = fileURL(for: url, look: look, container: container)
        return FileManager.default.fileExists(atPath: stored.path) ? stored : nil
    }

    public static func fileURL(
        for url: URL,
        look: RenderLook,
        container: URL = AppGroupSettings.containerURL
    ) -> URL {
        container
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("\(identity(for: url, look: look)).png")
    }

    /// Stable hex of path + size + mtime + look. Not a filesystem path — the group
    /// container is world-readable to the host and both extensions.
    public static func identity(
        for url: URL,
        look: RenderLook
    ) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize.map(Int64.init) ?? 0
        let modified = Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        let fingerprint = [
            look.environment.rawValue,
            look.toneMapping.rawValue,
            url.standardizedFileURL.path,
            String(size),
            String(modified),
        ].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(fingerprint.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
