import AppKit
import CoreGraphics
import ImageIO
@preconcurrency import Metal
import RealityKit
import simd
import UniformTypeIdentifiers

/// Live preview camera pose for an offscreen re-render.
/// `StillRenderer` builds its own `RealityRenderer` — not a framebuffer grab.
/// Pose + projection are copied from the live camera so framing matches.
struct StillCameraPose: Sendable {
    enum Projection: Sendable {
        case perspective(fieldOfViewDegrees: Float, near: Float, far: Float)
        case orthographic(scale: Float, near: Float, far: Float)
    }

    var position: SIMD3<Float>
    var orientation: simd_quatf
    var projection: Projection

    /// Snapshot world transform + projection from the live preview camera entity.
    @MainActor
    static func capturing(from camera: Entity) -> StillCameraPose? {
        let position = camera.position(relativeTo: nil)
        let orientation = camera.orientation(relativeTo: nil)
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { return nil }

        if let orthographic = camera.components[OrthographicCameraComponent.self] {
            return StillCameraPose(
                position: position,
                orientation: orientation,
                projection: .orthographic(
                    scale: orthographic.scale,
                    near: orthographic.near,
                    far: orthographic.far
                )
            )
        }
        if let perspective = camera.components[PerspectiveCameraComponent.self] {
            return StillCameraPose(
                position: position,
                orientation: orientation,
                projection: .perspective(
                    fieldOfViewDegrees: perspective.fieldOfViewInDegrees,
                    near: perspective.near,
                    far: perspective.far
                )
            )
        }
        return nil
    }

    /// Build a camera entity posed like the live preview for `RealityRenderer.activeCamera`.
    @MainActor
    func makeCameraEntity() -> Entity {
        let camera = Entity()
        camera.name = "stillCamera"
        camera.setPosition(position, relativeTo: nil)
        camera.orientation = orientation
        switch projection {
        case .perspective(let fov, let near, let far):
            var perspective = PerspectiveCameraComponent()
            perspective.fieldOfViewInDegrees = fov
            perspective.fieldOfViewOrientation = .vertical
            perspective.near = near
            perspective.far = far
            camera.components.set(perspective)
        case .orthographic(let scale, let near, let far):
            var orthographic = OrthographicCameraComponent()
            orthographic.scale = scale
            orthographic.scaleDirection = .vertical
            orthographic.near = near
            orthographic.far = far
            camera.components.set(orthographic)
        }
        return camera
    }
}

/// Offscreen `RealityRenderer` for Finder thumbnails and host screenshot re-renders.
@MainActor
final class StillRenderer {
    private let renderer: RealityRenderer
    private let texture: MTLTexture
    let width: Int
    let height: Int

    /// Thumbnail / fit camera path — front-¾ framing from bounds.
    init(
        root: Entity,
        bounds: BoundingBox,
        width: Int,
        height: Int,
        background: CGColor,
        padding: Float,
        intensityExponent: Float = 0
    ) async throws {
        let aspect = Float(width) / Float(max(height, 1))
        let camera = PreviewCamera.makeFrontThreeQuarter(
            minBound: bounds.min,
            maxBound: bounds.max,
            padding: padding,
            aspect: aspect
        )
        let built = try await Self.build(
            root: root,
            camera: camera,
            width: width,
            height: height,
            background: background,
            intensityExponent: intensityExponent,
            environmentYaw: 0,
            useEntityIBL: false
        )
        self.renderer = built.renderer
        self.texture = built.texture
        self.width = width
        self.height = height
    }

    /// Host screenshot — re-render at the current live camera pose.
    init(
        root: Entity,
        cameraPose: StillCameraPose,
        width: Int,
        height: Int,
        background: CGColor,
        intensityExponent: Float = 0,
        environmentYaw: Float = 0
    ) async throws {
        let built = try await Self.build(
            root: root,
            camera: cameraPose.makeCameraEntity(),
            width: width,
            height: height,
            background: background,
            intensityExponent: intensityExponent,
            environmentYaw: environmentYaw,
            useEntityIBL: true
        )
        self.renderer = built.renderer
        self.texture = built.texture
        self.width = width
        self.height = height
    }

    private static func build(
        root: Entity,
        camera: Entity,
        width: Int,
        height: Int,
        background: CGColor,
        intensityExponent: Float,
        environmentYaw: Float,
        useEntityIBL: Bool
    ) async throws -> (renderer: RealityRenderer, texture: MTLTexture) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw error("No Metal device", code: 1)
        }

        let renderer = try RealityRenderer()
        renderer.cameraSettings.colorBackground = .color(background)
        renderer.cameraSettings.antialiasing = .multisample4X
        renderer.extendedDynamicRangeOutput = false

        renderer.entities.append(root)
        if useEntityIBL {
            // Match live Look path (incl. session env yaw). Thumbnails use renderer.lighting.
            await PreviewLighting.prefetchLook(AppLook.current)
            let lookRoot = Entity()
            lookRoot.name = PreviewLighting.lookRootName
            PreviewLighting.applyLook(
                lookRoot: lookRoot,
                pivot: root,
                intensityExponent: intensityExponent,
                environmentYaw: environmentYaw
            )
            renderer.entities.append(lookRoot)
        } else {
            await PreviewLighting.configureThumbnailLighting(
                on: renderer,
                intensityExponent: intensityExponent
            )
        }
        renderer.entities.append(camera)
        renderer.activeCamera = camera

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
        return (renderer, texture)
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

    /// Save-panel + offscreen re-render at `cameraPose`. Returns the written URL, or `nil` if cancelled.
    ///
    /// Prefer a sheet on the key window so AX / Peekaboo can target it; fall back to `runModal`
    /// only when no window is available.
    static func exportPNGViaSavePanel(
        root: Entity,
        cameraPose: StillCameraPose,
        background: CGColor,
        intensityExponent: Float,
        environmentYaw: Float,
        suggestedName: String,
        pixelHeight: Int = 1080,
        aspect: Float = 16 / 9
    ) async throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedName.hasSuffix(".png") ? suggestedName : "\(suggestedName).png"
        panel.title = "Export Screenshot"
        panel.message = "Offscreen re-render at the current camera pose (not a live framebuffer grab)."

        let url: URL? = await withCheckedContinuation { cont in
            if let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
                panel.beginSheetModal(for: window) { response in
                    cont.resume(returning: response == .OK ? panel.url : nil)
                }
            } else {
                let response = panel.runModal()
                cont.resume(returning: response == .OK ? panel.url : nil)
            }
        }
        guard let url else { return nil }

        let safeAspect = (aspect > 0.05 && aspect < 20) ? aspect : (16 / 9)
        let height = max(64, pixelHeight)
        let width = max(64, Int((Float(height) * safeAspect).rounded()))
        let still = try await StillRenderer(
            root: root,
            cameraPose: cameraPose,
            width: width,
            height: height,
            background: background,
            intensityExponent: intensityExponent,
            environmentYaw: environmentYaw
        )
        let image = try await still.capture()
        try writePNG(image, to: url)
        return url
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
    NSError(domain: "StillRenderer", code: code, userInfo: [NSLocalizedDescriptionKey: message])
}
