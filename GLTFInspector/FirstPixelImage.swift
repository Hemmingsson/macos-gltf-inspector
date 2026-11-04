import AppKit
import GLTFCore

func firstPixelNSImage(for url: URL) -> NSImage? {
    guard let image = FirstPixelPreview.image(for: url) else { return nil }
    return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
}
