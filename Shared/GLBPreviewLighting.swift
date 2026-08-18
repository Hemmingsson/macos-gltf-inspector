import CoreGraphics
import RealityKit
import simd

enum GLBPreviewLighting {
    /// Finder icons: soft ambient + one gentle key from the camera.
    /// `intensityExponent` is power-of-two (0 ≈ 1×).
    @MainActor
    static func configureThumbnailLighting(on renderer: RealityRenderer, cameraPosition: SIMD3<Float>) async {
        if let resource = await softProbeResource() {
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
    private static func softProbeResource() async -> EnvironmentResource? {
        if let cachedProbe { return cachedProbe }
        guard let image = softEquirectangular() else { return nil }
        do {
            let resource = try await EnvironmentResource(equirectangular: image)
            cachedProbe = resource
            return resource
        } catch {
            GLBLog.error(GLBLog.lighting, "EnvironmentResource failed: \(error)")
            return nil
        }
    }

    private static func softEquirectangular() -> CGImage? {
        let width = 64
        let height = 32
        let c: UInt8 = 200
        var pixels = [UInt8](repeating: c, count: width * height * 4)
        for i in stride(from: 3, to: pixels.count, by: 4) {
            pixels[i] = 255
        }
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return context.makeImage()
    }
}
