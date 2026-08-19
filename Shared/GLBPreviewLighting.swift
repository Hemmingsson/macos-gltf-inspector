import CoreGraphics
import ImageIO
import RealityKit
import SwiftUI

enum GLBPreviewLighting {
    private static var studioHDRName: String {
        GLBKhronosEnvironments.defaultLook.resourceName
    }

    /// Finder icons: key plus IBL when Settings uses an environment map.
    /// `intensityExponent` is power-of-two (0 ≈ 1×).
    @MainActor
    static func configureThumbnailLighting(
        on renderer: RealityRenderer,
        cameraPosition: SIMD3<Float>,
        intensityExponent: Float = 0
    ) async {
        _ = cameraPosition
        let look = AppLook.current
        guard look.useEnvironmentMap else { return }
        await prefetchLook(look)
        if let resource = cachedResource(for: look) ?? cachedProbe {
            renderer.lighting.resource = resource
            renderer.lighting.intensityExponent = intensityExponent
        } else {
            GLBLog.error(GLBLog.lighting, "thumbnail IBL probe missing")
        }
    }

    /// Warm the look (or Studio Neutral) so `applyLook` can attach it synchronously.
    @MainActor
    static func prefetchStudioIBL() async {
        await prefetchLook(.current)
    }

    @MainActor
    static func prefetchLook(_ look: AppLook) async {
        if look.useEnvironmentMap, let url = look.resolvedHDRURL() {
            _ = await resource(for: url)
        } else {
            _ = await studioResource()
        }
    }

    /// QL, host, and QA still-renderer. Skybox stays off.
    @MainActor
    static func applyLook(
        to content: inout RealityViewCameraContent,
        pivot: Entity,
        look: AppLook = .current,
        intensityExponent: Float
    ) {
        for entity in content.entities where lookEntityNames.contains(entity.name) {
            content.remove(entity)
        }
        if look.useEnvironmentMap {
            if let ibl = makeIBLEntity(receiver: pivot, resource: cachedResource(for: look) ?? cachedProbe, intensityExponent: intensityExponent) {
                content.add(ibl)
            }
        } else {
            removeReceivers(from: pivot)
            content.add(makeDirectional(name: "lookKey", intensity: 2_500, from: [4, 7, 6]))
            content.add(makeDirectional(name: "lookFill", intensity: 900, from: [-5, 3, 2]))
        }
    }

    /// World-fixed Studio Neutral IBL. Does not change the RealityView background.
    @MainActor
    static func makeStudioIBLEntity(receiver: Entity, intensityExponent: Float = 0) -> Entity? {
        makeIBLEntity(receiver: receiver, resource: cachedProbe, intensityExponent: intensityExponent)
    }

    private static let lookEntityNames: Set<String> = ["lookIBL", "studioIBL", "lookKey", "lookFill"]

    @MainActor
    private static var cachedProbe: EnvironmentResource?

    @MainActor
    private static var cachedByURL: [String: EnvironmentResource] = [:]

    @MainActor
    private static func cachedResource(for look: AppLook) -> EnvironmentResource? {
        guard let url = look.resolvedHDRURL() else { return cachedProbe }
        return cachedByURL[url.path] ?? (url.path == hdrURL()?.path ? cachedProbe : nil)
    }

    @MainActor
    private static func resource(for url: URL) async -> EnvironmentResource? {
        if let cached = cachedByURL[url.path] { return cached }
        if let loaded = await loadEnvironmentResource(from: url) {
            cachedByURL[url.path] = loaded
            if url.path == hdrURL()?.path {
                cachedProbe = loaded
            }
            return loaded
        }
        if url.path != hdrURL()?.path {
            GLBLog.error(GLBLog.lighting, "HDR failed \(url.lastPathComponent); using Studio Neutral")
            return await studioResource()
        }
        return nil
    }

    @MainActor
    private static func studioResource() async -> EnvironmentResource? {
        if let cachedProbe { return cachedProbe }
        guard let url = hdrURL() else {
            GLBLog.error(GLBLog.lighting, "studio HDR missing from bundle (\(studioHDRName).hdr)")
            return nil
        }
        return await resource(for: url)
    }

    @MainActor
    private static func makeIBLEntity(
        receiver: Entity,
        resource: EnvironmentResource?,
        intensityExponent: Float
    ) -> Entity? {
        guard let resource else { return nil }
        let ibl = Entity()
        ibl.name = "lookIBL"
        var light = ImageBasedLightComponent(source: .single(resource), intensityExponent: intensityExponent)
        light.inheritsRotation = false
        ibl.components.set(light)
        applyReceivers(from: ibl, to: receiver)
        return ibl
    }

    @MainActor
    private static func makeDirectional(name: String, intensity: Float, from: SIMD3<Float>) -> Entity {
        let light = DirectionalLight()
        light.name = name
        light.light.intensity = intensity
        light.look(at: .zero, from: from, relativeTo: nil)
        return light
    }

    @MainActor
    private static func removeReceivers(from entity: Entity) {
        entity.components.remove(ImageBasedLightReceiverComponent.self)
        for child in entity.children {
            removeReceivers(from: child)
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
    static func loadEnvironmentResource(from url: URL) async -> EnvironmentResource? {
        guard let image = loadEquirectangular(from: url) else {
            GLBLog.error(GLBLog.lighting, "HDR decode failed \(url.lastPathComponent)")
            return nil
        }
        do {
            return try await EnvironmentResource(equirectangular: image)
        } catch {
            GLBLog.error(GLBLog.lighting, "EnvironmentResource failed: \(error)")
            return nil
        }
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
