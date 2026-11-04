import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// `CGImage` → PNG file, for File ▸ Export PNG and tests.
public enum PNGWriter {
    public static func write(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw error("Could not create PNG destination", code: 4)
        }
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) {
            throw error("Could not write PNG", code: 5)
        }
    }

    private static func error(_ message: String, code: Int) -> NSError {
        NSError(domain: "PNGWriter", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
