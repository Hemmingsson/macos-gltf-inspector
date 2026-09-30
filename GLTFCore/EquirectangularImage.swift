import CoreGraphics
import Foundation
import ImageIO

/// Decodes an equirectangular `.hdr` / `.exr` with float samples kept. Renderer-free, so the host
/// can check a custom environment before Settings stores it.
public enum EquirectangularImage {
    public static func load(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldAllowFloat: true,
            kCGImageSourceShouldCache: true,
        ]
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    public static func canDecode(at url: URL) -> Bool {
        load(from: url) != nil
    }
}
