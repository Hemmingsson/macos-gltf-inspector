import AppKit
import CoreGraphics
import ImageIO
import Metal
import RealityKit
import UniformTypeIdentifiers

/// Offscreen RealityRenderer. No window — used by Finder icons and the promo GIF.
@MainActor
final class GLBStillRenderer {
    private let renderer: RealityRenderer
    private let texture: MTLTexture
    let width: Int
    let height: Int

    init(
        root: Entity,
        bounds: BoundingBox,
        width: Int,
        height: Int,
        background: CGColor,
        padding: Float,
        cameraAspect: Float? = nil,
        fillBackdrop: Bool = false
    ) async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw error("No Metal device", code: 1)
        }
        self.width = width
        self.height = height

        let renderer = try RealityRenderer()
        renderer.cameraSettings.colorBackground = .color(background)
        renderer.cameraSettings.antialiasing = .multisample4X
        renderer.extendedDynamicRangeOutput = false

        let aspect = cameraAspect ?? Float(width) / Float(max(height, 1))
        let camera = GLBPreviewCamera.makeFrontThreeQuarter(
            minBound: bounds.min,
            maxBound: bounds.max,
            padding: padding,
            aspect: aspect
        )
        renderer.entities.append(root)
        await GLBPreviewLighting.configureThumbnailLighting(
            on: renderer,
            cameraPosition: camera.position(relativeTo: nil)
        )
        renderer.entities.append(camera)
        renderer.activeCamera = camera
        if fillBackdrop {
            var sky = PhysicallyBasedMaterial()
            sky.baseColor = .init(tint: .white)
            sky.roughness = .init(floatLiteral: 1)
            sky.metallic = .init(floatLiteral: 0)
            sky.emissiveColor = .init(color: .white)
            sky.emissiveIntensity = 12
            let dome = ModelEntity(mesh: .generateSphere(radius: 80), materials: [sky])
            dome.scale = [-1, 1, 1]
            renderer.entities.append(dome)
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw error("Could not allocate texture", code: 2)
        }
        self.renderer = renderer
        self.texture = texture
    }

    func capture() async throws -> CGImage {
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try renderer.updateAndRender(deltaTime: 0, cameraOutput: output, onComplete: { [texture, width, height] _ in
                    do {
                        continuation.resume(returning: try image(from: texture, width: width, height: height))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                })
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw error("Could not create PNG destination", code: 4)
        }
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) {
            throw error("Could not write PNG", code: 5)
        }
    }
}

private func image(from texture: MTLTexture, width: Int, height: Int) throws -> CGImage {
    let bytesPerRow = width * 4
    var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
    texture.getBytes(
        &bytes,
        bytesPerRow: bytesPerRow,
        from: MTLRegionMake2D(0, 0, width, height),
        mipmapLevel: 0
    )
    guard let context = CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
    ), let image = context.makeImage() else {
        throw error("Could not wrap texture as image", code: 3)
    }
    return image
}

private func error(_ message: String, code: Int) -> NSError {
    NSError(domain: "GLBStillRenderer", code: code, userInfo: [NSLocalizedDescriptionKey: message])
}
