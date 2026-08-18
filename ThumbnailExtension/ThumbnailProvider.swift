import QuickLookThumbnailing
import RealityKit
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let scale = max(request.scale, 1)
        let pixel = max(64, Int(max(request.maximumSize.width, request.maximumSize.height) * scale))
        let url = request.fileURL
        GLBLog.processBanner("thumbnail-request")
        GLBLog.event(
            GLBLog.thumbnail,
            "provideThumbnail pixel=\(pixel) scale=\(request.scale) max=\(request.maximumSize) \(GLBLog.describeURL(url))"
        )

        Task { @MainActor in
            do {
                let entity = try await GLBEntityLoader.load(from: url, includeAnimations: false)
                GLBLog.event(GLBLog.thumbnail, "loaded \(GLBLog.describe(entity))")
                GLBThumbnailPrepare.apply(to: entity)
                let assembled = GLBPreviewCamera.makeTurntable(for: entity)
                let image = try await Self.render(root: assembled.pivot, bounds: assembled.bounds, pixel: pixel)
                let fileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("glb-thumb-\(UUID().uuidString).png")
                try Self.writePNG(image, to: fileURL)
                GLBLog.event(
                    GLBLog.thumbnail,
                    "wrote PNG \(fileURL.path) \(image.width)x\(image.height)"
                )
                // Finder / QLThumbnailGenerator reliably consumes imageFileURL.
                // The CGContext drawing reply works in `qlmanage -x` but fails with
                // QLThumbnailError 102 for the generator path Finder uses.
                handler(QLThumbnailReply(imageFileURL: fileURL), nil)
            } catch {
                GLBLog.error(GLBLog.thumbnail, "thumbnail failed \(url.path) \(error)")
                handler(nil, error)
            }
        }
    }

    @MainActor
    private static func render(root: Entity, bounds: BoundingBox, pixel: Int) async throws -> CGImage {
        GLBLog.event(
            GLBLog.thumbnail,
            "render pixel=\(pixel) bounds.min=\(GLBLog.fmt3(bounds.min)) max=\(GLBLog.fmt3(bounds.max))"
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "GLBThumbnail", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Metal device"])
        }

        let renderer = try RealityRenderer()
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0.94, alpha: 1))
        renderer.cameraSettings.antialiasing = .multisample4X
        renderer.extendedDynamicRangeOutput = false

        let padding = GLBPreviewCamera.thumbnailFitPadding
        let camera = GLBPreviewCamera.makeFrontThreeQuarter(
            minBound: bounds.min,
            maxBound: bounds.max,
            padding: padding
        )
        renderer.entities.append(root)
        await GLBPreviewLighting.configureThumbnailLighting(
            on: renderer,
            cameraPosition: camera.position(relativeTo: nil)
        )
        renderer.entities.append(camera)
        renderer.activeCamera = camera
        GLBLog.event(GLBLog.thumbnail, "renderer entities=\(renderer.entities.count) camera=\(GLBLog.fmt3(camera.position(relativeTo: nil)))")

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: pixel,
            height: pixel,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "GLBThumbnail", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not allocate texture"])
        }

        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))

        // Trailing closure binds to `whenScheduled` — must label `onComplete:`.
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try renderer.updateAndRender(deltaTime: 0.1, cameraOutput: output, onComplete: { _ in
                    do {
                        let image = try image(from: texture, pixel: pixel)
                        GLBLog.event(GLBLog.thumbnail, "render complete \(image.width)x\(image.height)")
                        continuation.resume(returning: image)
                    } catch {
                        GLBLog.error(GLBLog.thumbnail, "texture wrap failed \(error)")
                        continuation.resume(throwing: error)
                    }
                })
            } catch {
                GLBLog.error(GLBLog.thumbnail, "updateAndRender failed \(error)")
                continuation.resume(throwing: error)
            }
        }
    }

    private static func image(from texture: MTLTexture, pixel: Int) throws -> CGImage {
        let bytesPerRow = pixel * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * pixel)
        texture.getBytes(&bytes, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, pixel, pixel), mipmapLevel: 0)

        // RealityRenderer writes straight (non-premultiplied) BGRA.
        guard let context = CGContext(
            data: &bytes,
            width: pixel,
            height: pixel,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        ), let image = context.makeImage() else {
            throw NSError(domain: "GLBThumbnail", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not wrap texture as image"])
        }
        return image
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "GLBThumbnail", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination"])
        }
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) {
            throw NSError(domain: "GLBThumbnail", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not write PNG"])
        }
    }
}
