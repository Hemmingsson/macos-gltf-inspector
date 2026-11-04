import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import Foundation
import GLTFCore
import QuickLookThumbnailing
import RendererWebKit

/// Finder thumbnail principal class. Renders through the same page the document window and Quick
/// Look use, so a file's Finder icon matches how it opens.
class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let scale = max(request.scale, 1)
        let pixel = max(64, Int(max(request.maximumSize.width, request.maximumSize.height) * scale))
        let url = request.fileURL

        // Quick Look copies the image from the handed-off URL but never deletes it, and the
        // extension gets no completion callback — so clear PNGs left by earlier requests.
        Self.sweepStaleThumbnails()

        Task.detached {
            do {
                let fileURL = try await Self.render(url: url, pixel: pixel)
                // Finder's generator reliably consumes `imageFileURL`. The CGContext drawing
                // reply works under `qlmanage -x` but fails there with QLThumbnailError 102 —
                // do not "simplify" this to the drawing reply.
                handler(QLThumbnailReply(imageFileURL: fileURL), nil)
            } catch {
                AppLog.error(
                    AppLog.thumbnail,
                    "thumbnail failed \(url.lastPathComponent) \(error.localizedDescription)"
                )
                handler(nil, error)
            }
        }
    }

    /// One warm host per extension process, serialized. Folder-scale cold start is ~850 ms/file;
    /// reuse is ~70 ms/file on the same path.
    @MainActor
    private static var shared: SharedHost?
    @MainActor
    private static var renderChain: Task<URL, Error>?

    private struct SharedHost {
        let host: any CanvasRendererHost
        let look: WebPreviewCanvas.Look
    }

    /// PNG file for Quick Look to copy.
    @MainActor
    private static func render(url: URL, pixel: Int) async throws -> URL {
        let previous = renderChain
        let work = Task<URL, Error> { @MainActor in
            _ = try? await previous?.value
            return try await renderNow(url: url, pixel: pixel)
        }
        renderChain = work
        return try await work.value
    }

    @MainActor
    private static func renderNow(url: URL, pixel: Int) async throws -> URL {
        let started = CFAbsoluteTimeGetCurrent()
        let host = try await reusedHost(look: .stored(), pixel: pixel)
        let info: WebRendererHost.LoadInfo
        let png: Data
        do {
            info = try await host.load(model: url)
            png = try await host.renderStillPNG(size: pixel)
        } catch {
            // A crashed page, or one still busy on a call that timed out, is dropped so the next
            // file in this process starts a fresh page. A file the page merely rejected keeps the
            // warm host. Either way the error goes back to Quick Look (generic icon).
            if host.isBroken || error as? WebRendererError == .timedOut { shared = nil }
            throw error
        }

        let fileURL = outputURL()
        // Finder's icon carries the renderer's name; the poster cache below stays unmarked.
        let shortName = host.rendererName.split(separator: " ").first.map(String.init) ?? host.rendererName
        try (RendererMark.stamp(shortName, on: png) ?? png).write(to: fileURL)
        do {
            try FirstPixelPreview.store(png: png, for: url)
        } catch {
            AppLog.error(AppLog.webRenderer, "poster cache failed \(url.lastPathComponent): \(error.localizedDescription)")
        }

        AppLog.info(
            AppLog.webRenderer,
            String(
                format: "thumbnail ready %@ %.0fms %dpx %dB tris=%d renderer=%@",
                url.lastPathComponent, (CFAbsoluteTimeGetCurrent() - started) * 1000,
                pixel, png.count, info.triangles, host.rendererName
            )
        )
        return fileURL
    }

    @MainActor
    private static func reusedHost(look: WebPreviewCanvas.Look, pixel: Int) async throws -> any CanvasRendererHost {
        if let shared, !shared.host.isBroken, shared.look == look {
            return shared.host
        }
        let host = try CanvasRenderer.makeHost(mode: .still, size: pixel)
        try await host.start()
        // Cheap before the first model: the page loads the HDR after `load`, `renderStill` waits.
        try await host.apply(look)
        shared = SharedHost(host: host, look: look)
        return host
    }

    private static let outputPrefix = "glb-thumb-"

    /// A fresh temp PNG path for one reply. `sweepStaleThumbnails` clears these later.
    static func outputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(outputPrefix)\(UUID().uuidString).png")
    }

    /// Remove `glb-thumb-*.png` files older than a minute. Best-effort: the age guard keeps a
    /// concurrent request's just-written file from being deleted before Quick Look reads it.
    private static func sweepStaleThumbnails() {
        let tmp = FileManager.default.temporaryDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: tmp,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date(timeIntervalSinceNow: -60)
        for entry in entries
        where entry.lastPathComponent.hasPrefix(outputPrefix) && entry.pathExtension == "png" {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }
}

/// Draws the renderer's name in a small capsule at the bottom-left of a thumbnail PNG.
enum RendererMark {
    static func stamp(_ name: String, on png: Data) -> Data? {
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
