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

    func bind(session: ViewerSession?) {
        self.session = session
        lastGoodEnvironment = session?.environment ?? .studioNeutral
        lastGoodUserHDR = session?.selectedUserHDR
        bridge.applyToContent = { [weak self] content, root in
            self?.attach(content: &content, root: root)
        }
        syncBackground()
        refreshResource()
        refreshBlurredSkybox()
        bridge.bump()
    }

    func sessionDidChange() {
        syncBackground()
        refreshResource()
        refreshBlurredSkybox()
        session?.applyIfBound()
        bridge.bump()
    }

    private func syncBackground() {
        bridge.backgroundColor = session?.backgroundColor ?? GLBPreviewBackdrop.dark
    }

    private func attach(content: inout RealityViewCameraContent, root: Entity) {
        let ibl = ensureIBL(in: &content)
        session?.bind(root: root, iblEntity: ibl)
        if let resource {
            let exponent = session?.intensityExponent(forSlider: session?.iblIntensity ?? 1) ?? 0
            ibl.components.set(ImageBasedLightComponent(source: .single(resource), intensityExponent: exponent))
        }
        session?.apply(root: root, iblEntity: ibl)
        applySkybox(&content)
    }

    private func ensureIBL(in content: inout RealityViewCameraContent) -> Entity {
        if let existing = content.entities.first(where: { $0.name == "hostIBL" }) {
            return existing
        }
        let ibl = Entity()
        ibl.name = "hostIBL"
        ibl.components.set(ImageBasedLightComponent(source: .none, intensityExponent: 0))
        content.add(ibl)
        return ibl
    }

    private func applySkybox(_ content: inout RealityViewCameraContent) {
        guard session?.showEnvironmentMap == true else {
            content.environment = .default
            return
        }
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
