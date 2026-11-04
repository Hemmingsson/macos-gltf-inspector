import CoreGraphics
import CoreText
import Foundation
import GLTFCore
import ImageIO
import UniformTypeIdentifiers

/// The Finder thumbnail's render path, minus Quick Look: one warm `.still` host per process,
/// requests serialized, a PNG back. `ThumbnailExtension/ThumbnailProvider` writes the reply file
/// and the poster cache; the tests drive this same type in-process (qlmanage hangs headless).
@MainActor
public final class ThumbnailRenderer {
    public struct Result: Sendable {
        /// The plain render: the poster cache stores this.
        public let png: Data
        /// `png` with the renderer's short name stamped bottom-left: Finder's icon.
        public let markedPNG: Data
        public let info: WebRendererHost.LoadInfo
        public let rendererName: String
    }

    private let backend: CanvasRenderer.Backend
    private var shared: SharedHost?
    private var renderChain: Task<Result, Error>?

    private struct SharedHost {
        let host: any CanvasRendererHost
        let look: WebPreviewCanvas.Look
    }

    public init(backend: CanvasRenderer.Backend = CanvasRenderer.backend()) {
        self.backend = backend
    }

    /// Renders `url` at `pixel`² with the stored look. Calls run one at a time on one warm host.
    /// On the WebKit page a folder-scale cold start was ~850 ms/file and reuse ~70 ms/file.
    public func render(url: URL, pixel: Int, look: WebPreviewCanvas.Look = .stored()) async throws -> Result {
        let previous = renderChain
        let work = Task<Result, Error> { @MainActor in
            _ = try? await previous?.value
            return try await self.renderNow(url: url, pixel: pixel, look: look)
        }
        renderChain = work
        return try await work.value
    }

    private func renderNow(url: URL, pixel: Int, look: WebPreviewCanvas.Look) async throws -> Result {
        let host = try await reusedHost(look: look, pixel: pixel)
        let info: WebRendererHost.LoadInfo
        let png: Data
        do {
            info = try await host.load(model: url)
            png = try await host.renderStillPNG(size: pixel)
        } catch {
            // A crashed renderer, or one still busy on a call that timed out, is dropped so the
            // next file in this process starts fresh. A file the renderer merely rejected keeps
            // the warm host. Either way the error goes back to Quick Look (generic icon).
            if host.isBroken || error as? WebRendererError == .timedOut { shared = nil }
            throw error
        }
        // Finder's icon carries the renderer's name; the poster cache stays unmarked.
        let shortName = host.rendererName.split(separator: " ").first.map(String.init) ?? host.rendererName
        return Result(
            png: png,
            markedPNG: RendererMark.stamp(shortName, on: png) ?? png,
            info: info,
            rendererName: host.rendererName
        )
    }

    private func reusedHost(look: WebPreviewCanvas.Look, pixel: Int) async throws -> any CanvasRendererHost {
        if let shared, !shared.host.isBroken, shared.look == look {
            return shared.host
        }
        let host = try CanvasRenderer.makeHost(mode: .still, size: pixel, backend: backend)
        try await host.start()
        // Cheap before the first model: the page loads the HDR after `load`, `renderStill` waits.
        try await host.apply(look)
        shared = SharedHost(host: host, look: look)
        return host
    }
}

/// Draws the renderer's name in a small capsule at the bottom-left of a thumbnail PNG.
public enum RendererMark {
    public static func stamp(_ name: String, on png: Data) -> Data? {
        guard
            let source = CGImageSourceCreateWithData(png as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        let edge = CGFloat(min(image.width, image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, edge * 0.045, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, edge * 0.045, nil)
        let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let text = NSAttributedString(string: name, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): white,
        ])
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetImageBounds(line, context)
        let padX = edge * 0.02
        let padY = edge * 0.012
        let margin = edge * 0.025
        let capsule = CGRect(
            x: margin, y: margin,
            width: bounds.width + padX * 2, height: CTFontGetAscent(font) + CTFontGetDescent(font) + padY * 2
        )
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
        context.addPath(CGPath(roundedRect: capsule, cornerWidth: capsule.height / 2, cornerHeight: capsule.height / 2, transform: nil))
        context.fillPath()
        context.textPosition = CGPoint(x: capsule.minX + padX - bounds.minX, y: capsule.minY + padY + CTFontGetDescent(font))
        CTLineDraw(line, context)

        guard let marked = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, marked, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
