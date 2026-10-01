import AppKit
import GLTFCore

func firstPixelNSImage(for url: URL, renderer: RendererKind) -> NSImage {
    let image = FirstPixelPreview.image(for: url, renderer: renderer)
    return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
}
