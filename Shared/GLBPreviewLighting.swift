import CoreGraphics
import ImageIO
import RealityKit

enum GLBPreviewLighting {
    private static let studioHDRName = "studio_small_09_1k"

    /// Finder icons: same studio HDR as Quick Look. `intensityExponent` is power-of-two (0 ≈ 1×).
    @MainActor
    static func configureThumbnailLighting(
        on renderer: RealityRenderer,
        cameraPosition: SIMD3<Float>,
        intensityExponent: Float = 0
    ) async {
        _ = cameraPosition
        if let resource = await studioResource() {
            renderer.lighting.resource = resource
            renderer.lighting.intensityExponent = intensityExponent
        } else {
            GLBLog.error(GLBLog.lighting, "thumbnail studio HDR missing")
        }
    }

    /// Warm the studio IBL cache so `makeStudioIBLEntity` can attach it synchronously.
    @MainActor
    static func prefetchStudioIBL() async {
        _ = await studioResource()
    }

    /// World-fixed studio light for reflections. Does not change the RealityView background.
    @MainActor
    static func makeStudioIBLEntity(receiver: Entity, intensityExponent: Float = 0) -> Entity? {
        guard let resource = cachedStudio else { return nil }
        let ibl = Entity()
        ibl.name = "studioIBL"
        var light = ImageBasedLightComponent(source: .single(resource), intensityExponent: intensityExponent)
        light.inheritsRotation = false
        ibl.components.set(light)
        applyReceivers(from: ibl, to: receiver)
        return ibl
    }

    @MainActor
    private static var cachedStudio: EnvironmentResource?

    @MainActor
    private static func studioResource() async -> EnvironmentResource? {
        if let cachedStudio { return cachedStudio }
        guard let url = Bundle.main.url(forResource: studioHDRName, withExtension: "hdr") else {
            GLBLog.error(GLBLog.lighting, "studio HDR missing from bundle (\(studioHDRName).hdr)")
            return nil
        }
        guard let image = loadEquirectangular(from: url) else {
            GLBLog.error(GLBLog.lighting, "studio HDR decode failed \(url.lastPathComponent)")
            return nil
        }
        do {
            let resource = try await EnvironmentResource(equirectangular: image)
            cachedStudio = resource
            return resource
        } catch {
            GLBLog.error(GLBLog.lighting, "studio EnvironmentResource failed: \(error)")
            return nil
        }
    }

    private static func loadEquirectangular(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldAllowFloat: true,
            kCGImageSourceShouldCache: true,
        ]
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    @MainActor
    private static func applyReceivers(from light: Entity, to entity: Entity) {
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
        for child in entity.children {
            applyReceivers(from: light, to: child)
        }
    }
}
