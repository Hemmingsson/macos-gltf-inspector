import AppKit
import GLTFCore

func firstPixelNSImage(for url: URL, renderer: RendererKind) -> NSImage? {
    guard let image = FirstPixelPreview.image(for: url, renderer: renderer) else { return nil }
    return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
}
