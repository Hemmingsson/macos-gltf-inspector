import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import simd

/// First-pixel surface for Quick Look and the document window: a thumbnail-written App Group
/// poster when one exists, otherwise a cheap JSON bounding-box proxy.
///
/// Keyed by path, size, mtime, renderer, and the lighting look that changes the thumbnail
/// (environment / tone / whether the env map is on). Pixel size is not part of the key — the
/// last Finder icon for that identity overwrites.
public enum FirstPixelPreview {
    public static let folderName = "posters"

    public enum Surface: Equatable, Sendable {
        case cachedPoster(URL)
        case boundingBoxProxy(ModelBounds?)
    }

    /// Cache hit is the stored PNG path; a miss is the authored box (nil only when the JSON has
    /// no usable `POSITION` min/max).
    public static func surface(
        for url: URL,
        renderer: RendererKind,
        look: RenderLook = AppGroupSettings.rendererLook(),
        container: URL = AppGroupSettings.containerURL
    ) -> Surface {
        if let stored = storedURL(for: url, renderer: renderer, look: look, container: container) {
            return .cachedPoster(stored)
        }
        return .boundingBoxProxy(bounds(for: url))
    }

    /// Picture to show immediately: the cached poster, or a drawn box on a miss.
    public static func image(
        for url: URL,
        renderer: RendererKind,
        look: RenderLook = AppGroupSettings.rendererLook(),
        container: URL = AppGroupSettings.containerURL,
        pixel: Int = 512
    ) -> CGImage {
        if case .cachedPoster(let stored) = surface(
            for: url, renderer: renderer, look: look, container: container
        ), let image = loadPNG(at: stored) {
            return image
        }
        return BoundingBoxProxy.image(bounds: bounds(for: url), pixel: pixel)
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

/// Front-¾ wire box from authored `POSITION` bounds. Cheap: no vertex data, no renderer.
enum BoundingBoxProxy {
    static func image(bounds: ModelBounds?, pixel: Int) -> CGImage {
        let box = bounds ?? ModelBounds(min: SIMD3(-0.5, -0.5, -0.5), max: SIMD3(0.5, 0.5, 0.5))
        let width = max(pixel, 32)
        let height = width
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return fallback(width: width, height: height)
        }

        let boundsRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 0.94, alpha: 1))
        context.fill(boundsRect)

        let corners = projectedCorners(box)
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 1
        let span = max(maxX - minX, maxY - minY, 0.001)
        let inset = CGFloat(width) * 0.18
        let scale = (CGFloat(width) - inset * 2) / CGFloat(span)
        let midX = (minX + maxX) * 0.5
        let midY = (minY + maxY) * 0.5
        func point(_ index: Int) -> CGPoint {
            let p = corners[index]
            return CGPoint(
                x: CGFloat(width) * 0.5 + CGFloat(p.x - midX) * scale,
                y: CGFloat(height) * 0.5 + CGFloat(p.y - midY) * scale
            )
        }

        context.setStrokeColor(CGColor(gray: 0.28, alpha: 1))
        context.setLineWidth(max(1.5, CGFloat(width) / 160))
        context.setLineJoin(.round)
        context.setLineCap(.round)
        let edges: [(Int, Int)] = [
            (0, 1), (1, 3), (3, 2), (2, 0),
            (4, 5), (5, 7), (7, 6), (6, 4),
            (0, 4), (1, 5), (2, 6), (3, 7),
        ]
        context.beginPath()
        for (a, b) in edges {
            context.move(to: point(a))
            context.addLine(to: point(b))
        }
        context.strokePath()

        return context.makeImage() ?? fallback(width: width, height: height)
    }

    /// Front-¾: +X right, +Y up, +Z toward the viewer, yawed like the thumbnail camera.
    private static func projectedCorners(_ box: ModelBounds) -> [SIMD2<Float>] {
        var points: [SIMD2<Float>] = []
        points.reserveCapacity(8)
        for corner in 0..<8 {
            let x = corner & 1 == 0 ? box.min.x : box.max.x
            let y = corner & 2 == 0 ? box.min.y : box.max.y
            let z = corner & 4 == 0 ? box.min.z : box.max.z
            points.append(SIMD2(x - z * 0.72, y + (x + z) * 0.28))
        }
        return points
    }

    private static func fallback(width: Int, height: Int) -> CGImage {
        var pixels = [UInt8](repeating: 240, count: width * height * 4)
        for index in stride(from: 3, to: pixels.count, by: 4) {
            pixels[index] = 255
        }
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return context?.makeImage() ?? CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data([240, 240, 240, 255]) as CFData)!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}
