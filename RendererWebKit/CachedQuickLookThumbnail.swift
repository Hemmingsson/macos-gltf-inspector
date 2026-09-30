import AppKit
import UniformTypeIdentifiers

/// Finder icon already in Icon Services — the cached Quick Look thumbnail when one exists.
///
/// Current `QLThumbnailGenerator.Request.RepresentationTypes` are not cache-only:
/// `.thumbnail` is "retrieved from the cache, or generated"; `.lowQualityThumbnail` is
/// "cached copy or faster lower quality generation" (QuickLookThumbnailing headers).
/// Either can start `ThumbnailExtension` / a second WebKit. This path never calls the
/// generator. `icon(forFile:)` reads the current icon; a never-thumbnailed file matches
/// the UTI icon and we skip so QL does not flash a generic document glyph.
@MainActor
public enum CachedQuickLookThumbnail {
    private static let compareSize = CGSize(width: 128, height: 128)
    /// Fraction of 128² pixels that must differ before we treat the file icon as a real thumb.
    private static let differenceFloor = 0.08

    public static func existingIcon(for url: URL) -> NSImage? {
        let fileIcon = NSWorkspace.shared.icon(forFile: url.path)
        let typeIcon = Self.typeIcon(for: url)
        guard differsFromTypeIcon(fileIcon, typeIcon: typeIcon) else { return nil }
        return (fileIcon.copy() as? NSImage) ?? fileIcon
    }

    static func differsFromTypeIcon(_ fileIcon: NSImage, typeIcon: NSImage) -> Bool {
        guard let filePixels = raster(fileIcon, size: compareSize),
              let typePixels = raster(typeIcon, size: compareSize),
              filePixels.count == typePixels.count,
              filePixels.count >= 4
        else { return false }

        var different = 0
        let pixelCount = filePixels.count / 4
        var index = 0
        while index < filePixels.count {
            if filePixels[index] != typePixels[index]
                || filePixels[index + 1] != typePixels[index + 1]
                || filePixels[index + 2] != typePixels[index + 2]
                || filePixels[index + 3] != typePixels[index + 3]
            {
                different += 1
            }
            index += 4
        }
        return Double(different) / Double(pixelCount) > differenceFloor
    }

    private static func typeIcon(for url: URL) -> NSImage {
        if let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
            return NSWorkspace.shared.icon(for: type)
        }
        if let type = UTType(filenameExtension: url.pathExtension) {
            return NSWorkspace.shared.icon(for: type)
        }
        return NSWorkspace.shared.icon(for: .data)
    }

    private static func raster(_ image: NSImage, size: CGSize) -> [UInt8]? {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: CGRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return pixels
    }
}
