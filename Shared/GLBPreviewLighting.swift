import CoreGraphics
import CoreImage
import ImageIO
import RealityKit
import simd

enum GLBPreviewLighting {
    private static var studioHDRName: String {
        GLBKhronosEnvironments.defaultLook.resourceName
    }

    /// Finder icons: soft key plus Studio Neutral IBL.
    /// `intensityExponent` is power-of-two (0 ≈ 1×).
    @MainActor
    static func configureThumbnailLighting(on renderer: RealityRenderer, cameraPosition: SIMD3<Float>) async {
        if let resource = await studioResource() {
            renderer.lighting.resource = resource
            renderer.lighting.intensityExponent = 0
        } else {
            GLBLog.error(GLBLog.lighting, "thumbnail IBL probe missing; key light only")
        }

        let key = DirectionalLight()
        key.name = "thumbKey"
        key.light.intensity = 2_500
        key.look(at: .zero, from: cameraPosition, relativeTo: nil)
        renderer.entities.append(key)
    }

    /// Warm the Studio Neutral cache so `makeStudioIBLEntity` can attach it synchronously.
    @MainActor
    static func prefetchStudioIBL() async {
        _ = await studioResource()
    }

    /// World-fixed Studio Neutral IBL. Does not change the RealityView background.
    @MainActor
    static func makeStudioIBLEntity(receiver: Entity, intensityExponent: Float = 0) -> Entity? {
        guard let resource = cachedProbe else { return nil }
        let ibl = Entity()
        ibl.name = "studioIBL"
        var light = ImageBasedLightComponent(source: .single(resource), intensityExponent: intensityExponent)
        light.inheritsRotation = false
        ibl.components.set(light)
        applyReceivers(from: ibl, to: receiver)
        return ibl
    }

    /// Studio Neutral after `prefetchStudioIBL`. Host uses this so the first frame
    /// matches Quick Look instead of binding receivers to `ImageBasedLightComponent.source.none`.
    @MainActor
    static var studioProbe: EnvironmentResource? { cachedProbe }

    @MainActor
    private static var cachedProbe: EnvironmentResource?

    @MainActor
    private static func studioResource() async -> EnvironmentResource? {
        if let cachedProbe { return cachedProbe }
        guard let url = hdrURL() else {
            GLBLog.error(GLBLog.lighting, "studio HDR missing from bundle (\(studioHDRName).hdr)")
            return nil
        }
        guard let image = loadEquirectangular(from: url) else {
            GLBLog.error(GLBLog.lighting, "studio HDR decode failed \(url.lastPathComponent)")
            return nil
        }
        do {
            let resource = try await EnvironmentResource(equirectangular: image)
            cachedProbe = resource
            return resource
        } catch {
            GLBLog.error(GLBLog.lighting, "EnvironmentResource failed: \(error)")
            return nil
        }
    }

    static func catalogURL(_ environment: GLBKhronosEnvironments) -> URL? {
        let name = environment.resourceName
        return Bundle.main.url(forResource: name, withExtension: "hdr", subdirectory: "khronos")
            ?? Bundle.main.url(forResource: name, withExtension: "hdr")
    }

    static func canDecodeHDR(at url: URL) -> Bool {
        loadEquirectangular(from: url) != nil
    }

    @MainActor
    static func loadEnvironmentResource(from url: URL, blurSkybox: Bool = false) async -> EnvironmentResource? {
        guard let image = loadEquirectangular(from: url) else {
            GLBLog.error(GLBLog.lighting, "HDR decode failed \(url.lastPathComponent)")
            return nil
        }
        let source = blurSkybox ? blurredEquirectangular(image) ?? image : image
        do {
            return try await EnvironmentResource(equirectangular: source)
        } catch {
            GLBLog.error(GLBLog.lighting, "EnvironmentResource failed: \(error)")
            return nil
        }
    }

    static func blurredEquirectangular(_ image: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let blurred = ci
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 48])
            .cropped(to: ci.extent)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(blurred, from: blurred.extent)
    }

    private static func hdrURL() -> URL? {
        catalogURL(GLBKhronosEnvironments.defaultLook)
    }

    static func loadEquirectangular(from url: URL) -> CGImage? {
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
