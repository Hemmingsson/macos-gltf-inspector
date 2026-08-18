import CoreGraphics
import RealityKit
import simd

enum GLBPreviewLighting {
    static let keyLightName = "keyLight"
    static let iblLightName = "iblLight"
    static let studioLightNames: Set<String> = [keyLightName, iblLightName]

    @MainActor
    static func makeStudioLights() -> [Entity] {
        let key = DirectionalLight()
        key.name = keyLightName
        key.light.intensity = 2_500
        key.look(at: .zero, from: [1.2, 1.8, 1.5], relativeTo: nil)
        GLBLog.info(GLBLog.lighting, "makeStudioLights key=2500")
        return [key]
    }

    @MainActor
    static func makeIBLLight(resource: EnvironmentResource) -> Entity {
        let light = Entity()
        light.name = iblLightName
        light.components.set(
            ImageBasedLightComponent(source: .single(resource), intensityExponent: 0)
        )
        return light
    }

    @MainActor
    static func attachReceivers(on root: Entity, light: Entity) {
        if root.components[ModelComponent.self] != nil {
            root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
        }
        for child in root.children {
            attachReceivers(on: child, light: light)
        }
    }

    @MainActor
    static func removeReceivers(from root: Entity) {
        root.components.remove(ImageBasedLightReceiverComponent.self)
        for child in root.children {
            removeReceivers(from: child)
        }
    }

    /// Finder icons: soft ambient + one gentle key from the camera.
    /// `intensityExponent` is power-of-two (0 ≈ 1×).
    @MainActor
    static func configureThumbnailLighting(on renderer: RealityRenderer, cameraPosition: SIMD3<Float>) async {
        if let resource = await softProbeResource() {
            renderer.lighting.resource = resource
            renderer.lighting.intensityExponent = 0
            GLBLog.event(GLBLog.lighting, "thumbnail IBL probe attached intensityExponent=0")
        } else {
            GLBLog.error(GLBLog.lighting, "thumbnail IBL probe missing; key light only")
        }

        let key = DirectionalLight()
        key.name = "thumbKey"
        key.light.intensity = 2_500
        key.look(at: .zero, from: cameraPosition, relativeTo: nil)
        renderer.entities.append(key)
        GLBLog.event(GLBLog.lighting, "thumbnail key light from \(GLBLog.fmt3(cameraPosition)) intensity=2500")
    }

    @MainActor
    private static var cachedProbe: EnvironmentResource?

    @MainActor
    static func softProbeResource() async -> EnvironmentResource? {
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
