import RealityKit
import SwiftUI

@MainActor
@Observable
final class GLBHostSceneController {
    let bridge = GLBPreviewHostSceneBridge()

    private var session: ViewerSession?
    private var resource: EnvironmentResource?
    private var blurredSkybox: EnvironmentResource?
    private var resourceKey: String?
    private var blurKey: String?
    private var loadGeneration = 0
    private var blurGeneration = 0
    private var lastGoodEnvironment: GLBKhronosEnvironments = .studioNeutral
    private var lastGoodUserHDR: URL?
    private var storedToneMapEffect: AnyObject?
    /// `ARView.renderCallbacks.setter` traps if post-process is assigned twice
    /// or after a custom `PerspectiveCamera` is in the scene.
    private var didAssignToneMap = false

    init() {
        installCallbacks()
    }

    func bind(session: ViewerSession?) {
        self.session = session
        lastGoodEnvironment = session?.environment ?? .studioNeutral
        lastGoodUserHDR = session?.selectedUserHDR
        installCallbacks()
        syncBackground()
        refreshResource()
        refreshBlurredSkybox()
        bridge.bump()
    }

    /// RealityView `make` can run before `onAppear` bind; callbacks must already exist.
    func installCallbacks() {
        bridge.applyToneMap = { [weak self] content in
            self?.applyToneMap(to: &content)
        }
        bridge.applyToContent = { [weak self] content, root in
            self?.attach(content: &content, root: root)
        }
    }

    func sessionDidChange() {
        syncBackground()
        refreshResource()
        refreshBlurredSkybox()
        session?.applyIfBound()
        bridge.bump()
    }

    func frameSelection() {
        if case .node(let index) = session?.selected {
            bridge.pendingFrameNodeIndex = index
        } else {
            bridge.pendingFrameNodeIndex = nil
        }
        bridge.frameNonce += 1
        session?.requestFrame()
        bridge.bump()
    }

    private func syncBackground() {
        bridge.backgroundColor = session?.backgroundColor ?? GLBPreviewBackdrop.dark
    }

    private func attach(content: inout RealityViewCameraContent, root: Entity) {
        let ibl = ensureIBL(in: &content)
        session?.bind(root: root, iblEntity: ibl)
        let probe = resource ?? GLBPreviewLighting.studioProbe
        if let probe {
            let exponent = session?.intensityExponent(forSlider: session?.iblIntensity ?? 1) ?? 0
            var light = ImageBasedLightComponent(source: .single(probe), intensityExponent: exponent)
            light.inheritsRotation = false
            ibl.components.set(light)
        }
        session?.apply(root: root, iblEntity: ibl)
        applySkybox(&content)
        syncToneMapParameters()
    }

    /// Assign `customPostProcessing` only once, from RealityView `make`, before the custom camera exists.
    private func applyToneMap(to content: inout RealityViewCameraContent) {
        guard #available(macOS 26, *) else { return }
        let effect = toneMapEffect()
        effect.exposure = session?.exposure ?? 1
        effect.toneMap = session?.toneMap ?? .khronosPBRNeutral
        guard !didAssignToneMap else {
            GLBLog.info(GLBLog.host, "toneMap skip-assign (already attached) exposure=\(effect.exposure) map=\(effect.toneMap.title)")
            return
        }
        content.renderingEffects.customPostProcessing = .effect(effect)
        didAssignToneMap = true
        GLBLog.info(GLBLog.host, "toneMap assigned exposure=\(effect.exposure) map=\(effect.toneMap.title)")
    }

    private func syncToneMapParameters() {
        guard #available(macOS 26, *) else { return }
        guard let effect = storedToneMapEffect as? ToneMapEffect else {
            GLBLog.info(GLBLog.host, "toneMap sync skipped (effect not created)")
            return
        }
        effect.exposure = session?.exposure ?? 1
        effect.toneMap = session?.toneMap ?? .khronosPBRNeutral
        GLBLog.info(GLBLog.host, "toneMap sync exposure=\(effect.exposure) map=\(effect.toneMap.title)")
    }

    @available(macOS 26, *)
    private func toneMapEffect() -> ToneMapEffect {
        if let existing = storedToneMapEffect as? ToneMapEffect {
            return existing
        }
        let effect = ToneMapEffect()
        storedToneMapEffect = effect
        return effect
    }

    private func ensureIBL(in content: inout RealityViewCameraContent) -> Entity {
        if let existing = content.entities.first(where: { $0.name == "hostIBL" }) {
            return existing
        }
        let ibl = Entity()
        ibl.name = "hostIBL"
        if let probe = resource ?? GLBPreviewLighting.studioProbe {
            var light = ImageBasedLightComponent(source: .single(probe), intensityExponent: 0)
            light.inheritsRotation = false
            ibl.components.set(light)
        } else {
            ibl.components.set(ImageBasedLightComponent(source: .none, intensityExponent: 0))
        }
        content.add(ibl)
        return ibl
    }

    private func applySkybox(_ content: inout RealityViewCameraContent) {
        guard session?.showEnvironmentMap == true else {
            // Non-skybox: RealityViewEnvironment.default uses the view backgroundStyle.
            content.environment = .default
            return
        }
        // RealityViewEnvironment.skybox has no yaw; IBL entity orientation still applies.
        if session?.blurEnvironment == true, let blurredSkybox {
            content.environment = .skybox(blurredSkybox)
        } else if let resource {
            content.environment = .skybox(resource)
        } else {
            content.environment = .default
        }
    }

    private func refreshResource() {
        guard let session else { return }
        let key: String
        let url: URL?
        if let user = session.selectedUserHDR {
            key = "user:" + user.absoluteString
            url = user
        } else {
            key = "catalog:" + session.environment.rawValue
            url = GLBPreviewLighting.catalogURL(session.environment)
        }
        guard key != resourceKey else { return }

        loadGeneration += 1
        let generation = loadGeneration
        guard let url else {
            revertEnvironment()
            session.inspectorError = "Could not load HDR"
            return
        }

        blurredSkybox = nil
        blurKey = nil
        blurGeneration += 1
        Task {
            if let loaded = await GLBPreviewLighting.loadEnvironmentResource(from: url) {
                guard generation == loadGeneration else { return }
                resource = loaded
                resourceKey = key
                lastGoodEnvironment = session.environment
                lastGoodUserHDR = session.selectedUserHDR
                session.inspectorError = nil
                if let ibl = session.boundIBL {
                    let exponent = session.intensityExponent(forSlider: session.iblIntensity)
                    ibl.components.set(ImageBasedLightComponent(source: .single(loaded), intensityExponent: exponent))
                }
                session.applyIfBound()
                refreshBlurredSkybox()
                bridge.bump()
            } else {
                guard generation == loadGeneration else { return }
                revertEnvironment()
                session.inspectorError = "Could not load HDR"
            }
        }
    }

    private func refreshBlurredSkybox() {
        guard let session, session.blurEnvironment, session.showEnvironmentMap else { return }
        let key: String
        let url: URL?
        if let user = session.selectedUserHDR {
            key = "user:" + user.absoluteString
            url = user
        } else {
            key = "catalog:" + session.environment.rawValue
            url = GLBPreviewLighting.catalogURL(session.environment)
        }
        guard key != blurKey else { return }
        guard let url else { return }

        blurGeneration += 1
        let generation = blurGeneration
        Task {
            if let loaded = await GLBPreviewLighting.loadEnvironmentResource(from: url, blurSkybox: true) {
                guard generation == blurGeneration else { return }
                blurredSkybox = loaded
                blurKey = key
                bridge.bump()
            }
        }
    }

    private func revertEnvironment() {
        guard let session else { return }
        session.environment = lastGoodEnvironment
        session.selectedUserHDR = lastGoodUserHDR
    }
}
