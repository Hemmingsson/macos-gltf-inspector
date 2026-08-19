import CoreGraphics
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

    private static func hdrURL() -> URL? {
        let name = studioHDRName
        return Bundle.main.url(forResource: name, withExtension: "hdr", subdirectory: "khronos")
            ?? Bundle.main.url(forResource: name, withExtension: "hdr")
    }

    private static func loadEquirectangular(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldAllowFloat: true,
            kCGImageSourceShouldCache: true,
        ]
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }
}
