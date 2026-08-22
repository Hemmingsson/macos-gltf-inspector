import CoreGraphics
import ImageIO
import RealityKit
import SwiftUI

enum PreviewLighting {
    private static var studioHDRName: String {
        KhronosEnvironments.defaultLook.rawValue
    }

    /// Finder icons: key plus IBL when Settings uses an environment map.
    /// `intensityExponent` is power-of-two (0 ≈ 1×).
    @MainActor
    static func configureThumbnailLighting(
        on renderer: RealityRenderer,
        intensityExponent: Float = 0
    ) async {
        let look = AppLook.current
        guard look.useEnvironmentMap else { return }
        await prefetchLook(look)
        if let resource = cachedResource(for: look) ?? cachedProbe {
            renderer.lighting.resource = resource
            renderer.lighting.intensityExponent = intensityExponent
        } else {
            AppLog.error(AppLog.lighting, "thumbnail IBL probe missing")
        }
    }

    @MainActor
    static func prefetchLook(_ look: AppLook) async {
        if look.useEnvironmentMap, let url = look.resolvedHDRURL() {
            _ = await resource(for: url)
        } else {
            _ = await studioResource()
        }
    }

    /// Parent for IBL / key+fill. Kept off `content.entities` iteration — walking
    /// `RealityViewEntityCollection` during update traps (`EXC_BREAKPOINT`).
    static let lookRootName = "lookRoot"

    /// QL, host, and thumbnail still-renderer. Skybox stays off.
    /// Lights are children of `lookRoot` (created once in `PreviewScene.make`).
    @MainActor
    static func applyLook(
        lookRoot: Entity,
        pivot: Entity,
        look: AppLook = .current,
        intensityExponent: Float,
        environmentYaw: Float = 0
    ) {
        // Drop receivers before removing IBL entities — leaving receivers aimed at
        // torn-down lights traps RealityKit (`EXC_BREAKPOINT` during updates).
        removeReceivers(from: pivot)
        let stale = Array(lookRoot.children)
        for entity in stale {
            entity.removeFromParent()
        }
        if look.useEnvironmentMap,
           let ibl = makeIBLEntity(
            receiver: pivot,
            resource: cachedResource(for: look) ?? cachedProbe,
            intensityExponent: intensityExponent,
            environmentYaw: environmentYaw
           )
        {
            lookRoot.addChild(ibl)
        } else {
            // No env map, or HDR still loading — key+fill so first paint isn't black.
            lookRoot.addChild(makeDirectional(name: "lookKey", intensity: 2_500, from: [4, 7, 6], castsShadow: true))
            lookRoot.addChild(makeDirectional(name: "lookFill", intensity: 900, from: [-5, 3, 2], castsShadow: false))
        }
    }

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
            AppLog.error(AppLog.lighting, "HDR failed \(url.lastPathComponent); using Studio Neutral")
            return await studioResource()
        }
        return nil
    }

    @MainActor
    private static func studioResource() async -> EnvironmentResource? {
        if let cachedProbe { return cachedProbe }
        guard let url = hdrURL() else {
            AppLog.error(AppLog.lighting, "studio HDR missing from bundle (\(studioHDRName).hdr)")
            return nil
        }
        return await resource(for: url)
    }

    @MainActor
    private static func makeIBLEntity(
        receiver: Entity,
        resource: EnvironmentResource?,
        intensityExponent: Float,
        environmentYaw: Float
    ) -> Entity? {
        guard let resource else { return nil }
        let ibl = Entity()
        ibl.name = "lookIBL"
        var light = ImageBasedLightComponent(source: .single(resource), intensityExponent: intensityExponent)
        // Session env yaw rotates the probe; re-applied whenever `applyLook` rebuilds.
        light.inheritsRotation = true
        ibl.orientation = simd_quatf(angle: environmentYaw, axis: [0, 1, 0])
        ibl.components.set(light)
        applyReceivers(from: ibl, to: receiver)
        return ibl
    }

    @MainActor
    private static func makeDirectional(
        name: String,
        intensity: Float,
        from: SIMD3<Float>,
        castsShadow: Bool
    ) -> Entity {
        let light = DirectionalLight()
        light.name = name
        light.light.intensity = intensity
        if castsShadow {
            light.shadow = DirectionalLightComponent.Shadow()
        }
        // Same safe basis as the orbit camera — avoid Entity.look(at:from:).
        PreviewCamera.applyView(to: light, eye: from, target: .zero)
        return light
    }

    @MainActor
    private static func removeReceivers(from entity: Entity) {
        entity.components.remove(ImageBasedLightReceiverComponent.self)
        for child in entity.children {
            removeReceivers(from: child)
        }
    }

    static func catalogURL(_ environment: KhronosEnvironments, bundle: Bundle = .main) -> URL? {
        let name = environment.rawValue
        return bundle.url(forResource: name, withExtension: "hdr", subdirectory: "khronos")
            ?? bundle.url(forResource: name, withExtension: "hdr")
    }

    static func canDecodeHDR(at url: URL) -> Bool {
        loadEquirectangular(from: url) != nil
    }

    @MainActor
    static func loadEnvironmentResource(from url: URL) async -> EnvironmentResource? {
        guard let image = loadEquirectangular(from: url) else {
            AppLog.error(AppLog.lighting, "HDR decode failed \(url.lastPathComponent)")
            return nil
        }
        do {
            return try await EnvironmentResource(equirectangular: image)
        } catch {
            AppLog.error(AppLog.lighting, "EnvironmentResource failed: \(error)")
            return nil
        }
    }

    private static func hdrURL() -> URL? {
        catalogURL(KhronosEnvironments.defaultLook)
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
