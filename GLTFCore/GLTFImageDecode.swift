import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pixel size + PNG thumbs for glTF images, straight from the encoded bytes.
/// Header-only where possible: no renderer, no full-raster decode for sizing.
enum GLTFImageDecode {
    /// Pixel size + optional inspector thumb from one ImageIO source.
    static func preview(
        of data: Data,
        maxEdge: Int
    ) -> (size: (width: Int, height: Int)?, thumb: Data?) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return (nil, nil)
        }
        return (pixelSize(of: source), maxEdge > 0 ? thumbnailPNG(from: source, maxEdge: maxEdge) : nil)
    }

    /// `(width, height)` from the image header. Nil when the bytes are not a decodable image.
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        preview(of: data, maxEdge: 0).size
    }

    /// Downscaled PNG for the inspector's map rows. ImageIO builds the thumbnail, so a
    /// 4k source never lands in memory at full size.
    static func thumbnailPNG(from data: Data, maxEdge: Int) -> Data? {
        preview(of: data, maxEdge: maxEdge).thumb
    }

    private static func pixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        guard width > 0, height > 0 else { return nil }
        return (width, height)
    }

    private static func thumbnailPNG(from source: CGImageSource, maxEdge: Int) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, thumb, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}
