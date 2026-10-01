import CoreGraphics
import Foundation
import GLTFCore
import Observation
import PreviewUI
import SwiftUI

/// Session + camera + still-path adapter for `ViewportController`.
///
/// Owns per-window view state (DESIGN.md this-window job). Fit / reset / presets / PNG export
/// forward to the `FocusedPreviewCommands` the mounted canvas registered; the PNG goes to the
/// host's `saveScreenshot` (save panel + write). Lighting maps
/// degrees↔radians and `usesFileLights`↔`dimStudioForFileLights`. `usesStudioEnvironment` mirrors
/// `AppLook.useEnvironmentMap` and is never written here — Settings owns that key.
///
/// Settings-backed keys (backdrop / floor / auto-rotate / center / projection) pin overrides in
/// the session's `EngineSettingsStore` on mutate; untouched keys track the app defaults live.
@MainActor
@Observable
final class EngineViewportController: ViewportController {
    var sidebar: HostSidebarModel
    let lookStore: AppLookStore

    /// Host-owned canvas session.
    let previewSession: PreviewSession

    /// Commands of the mounted canvas (the renderer window registers them). Nil while no canvas can
    /// take them, and in unit tests that only exercise setters.
    var commands: FocusedPreviewCommands?

    /// Host save panel + PNG write for `screenshot()`. Tests inject a recorder.
    var saveScreenshot: ((CGImage) async -> Void)?

    /// Mounted renderer's `RendererFeature` set. The View menu hides what this lacks.
    let features: Set<RendererFeature>

    private(set) var activeCameraPreset: PreviewUI.CameraPreset?

    /// Per-window environment and tone mapping (not on `PreviewSession`, which cannot see PreviewUI
    /// types). Seeded from app defaults on `applySession`, then per-window.
    private(set) var environment: StudioEnvironment = .neutral
    private(set) var toneMapping: ToneMapping = .neutral

    init(
        sidebar: HostSidebarModel,
        lookStore: AppLookStore? = nil,
        previewSession: PreviewSession? = nil,
        commands: FocusedPreviewCommands? = nil,
        saveScreenshot: ((CGImage) async -> Void)? = nil,
        features: Set<RendererFeature> = Set(RendererFeature.allCases)
    ) {
        self.sidebar = sidebar
        self.lookStore = lookStore ?? .shared
        self.previewSession = previewSession ?? PreviewSession()
        self.commands = commands
        self.saveScreenshot = saveScreenshot
        self.features = features
    }

    /// Per-window lazy overlay (the session's `EngineSettingsStore`).
    var settings: EngineSettingsStore { previewSession.settings }

    /// Seed environment and tone mapping from the app defaults.
    func applySession() {
        // Environment and tone mapping have no session override yet: they are app defaults, and
        // the extensions read the same two keys so all three surfaces agree.
        environment = StudioEnvironment(rawValue: settings.default(for: .environmentCatalog)) ?? .neutral
        toneMapping = ToneMapping.fromKhronosName(settings.default(for: .toneMapping))
    }

    var backdrop: BackdropStyle { previewSession.backdrop }

    var showsFloor: Bool { previewSession.showFloor }

    var autoRotates: Bool { previewSession.autoRotate }

    var isCentered: Bool { previewSession.centerModel }

    var viewMode: ViewMode {
        ViewMode(previewSession.viewMode)
    }

    var projection: Projection { settings.sessionValue(for: .projection) }

    var lighting: LightingSettings {
        LightingSettings(
            exposure: Double(previewSession.exposureEV),
            environmentRotationDegrees: Double(previewSession.environmentYaw) * 180 / .pi,
            usesFileLights: previewSession.dimStudioForFileLights,
            usesStudioEnvironment: lookStore.look.useEnvironmentMap,
            environment: environment,
            toneMapping: toneMapping
        )
    }

    var activeSceneID: NodeID? {
        let index = sidebar.activeSceneIndex
        guard sidebar.document.scenes.indices.contains(index) else { return nil }
        return NodeID(kind: .scene, index: index)
    }

    var selectedMaterialVariantIndex: Int? {
        sidebar.selectedMaterialVariantIndex
    }

    func setBackdrop(_ style: BackdropStyle) {
        previewSession.backdrop = style
    }

    func setFloor(_ isOn: Bool) {
        previewSession.showFloor = isOn
    }

    func setAutoRotate(_ isOn: Bool) {
        previewSession.autoRotate = isOn
    }

    func setCenter(_ isOn: Bool) {
        previewSession.centerModel = isOn
    }

    func setViewMode(_ mode: ViewMode) {
        // A mode the file does not offer falls back to shaded, as the menu never lists it.
        let wanted = RenderViewMode(mode)
        previewSession.viewMode = previewSession.viewModes.contains(wanted) ? wanted : .shaded
    }

    func setProjection(_ projection: Projection) {
        previewSession.orthographic = projection == .orthographic
    }

    func setLighting(_ lighting: LightingSettings) {
        // Per-window override; deliberately does not write the app default back.
        environment = lighting.environment
        toneMapping = lighting.toneMapping
        previewSession.exposureEV = Float(lighting.exposure)
        previewSession.environmentYaw = Float(lighting.environmentRotationDegrees * .pi / 180)
        previewSession.dimStudioForFileLights = lighting.usesFileLights
        // Intentionally ignore `usesStudioEnvironment` — do not fight `AppLook.useEnvironmentMap`.
    }

    /// Convert-owned file-light dimming. Open resets exposure/yaw; scene/variant keep them.
    func applyConvertedLighting(dimStudioForFileLights: Bool, resetExposureAndYaw: Bool) {
        setLighting(
            LightingSettings(
                exposure: resetExposureAndYaw ? 0 : lighting.exposure,
                environmentRotationDegrees: resetExposureAndYaw ? 0 : lighting.environmentRotationDegrees,
                usesFileLights: dimStudioForFileLights,
                usesStudioEnvironment: lookStore.look.useEnvironmentMap,
                environment: environment,
                toneMapping: toneMapping
            )
        )
    }

    func fit() {
        sidebar.selectedCameraIndex = nil
        commands?.fit()
        activeCameraPreset = nil
    }

    func reset() {
        setBackdrop(settings.default(for: .backdrop))
        setFloor(settings.default(for: .showFloor))
        setAutoRotate(settings.default(for: .autoRotate))
        setCenter(true)
        setViewMode(.shaded)
        setProjection(.perspective)
        setLighting(
            LightingSettings(
                exposure: 0,
                environmentRotationDegrees: 0,
                usesFileLights: false,
                usesStudioEnvironment: lookStore.look.useEnvironmentMap
            )
        )
        setDoubleSided(false)
        setShowSkeleton(false)
        setFieldOfViewDegrees(RenderCamera.defaultFieldOfViewDegrees)
        sidebar.selectedCameraIndex = nil
        activeCameraPreset = nil
        commands?.reset()
    }

    func applyCameraPreset(_ preset: PreviewUI.CameraPreset) {
        sidebar.selectedCameraIndex = nil
        activeCameraPreset = preset
        commands?.applyCameraPreset(GLTFCore.CameraPreset(preset))
    }

    func screenshot() {
        Task { await exportScreenshot() }
    }

    /// Pixels from the mounted canvas, then the host's save panel. Split out so tests can await it.
    func exportScreenshot() async {
        guard let render = commands?.screenshot else { return }
        do {
            let image = try await render()
            await saveScreenshot?(image)
        } catch {
            AppLog.error(AppLog.host, "PNG export failed: \(error.localizedDescription)")
        }
    }

    func setScene(_ id: NodeID) {
        guard id.kind == .scene else { return }
        sidebar.activeSceneIndex = id.index
    }

    func setMaterialVariant(_ index: Int?) {
        sidebar.selectedMaterialVariantIndex = index
        sidebar.overlayRevision += 1
    }

    func setFileCamera(_ id: NodeID?) {
        if let id {
            guard id.kind == .camera else { return }
            sidebar.selectedCameraIndex = id.index
        } else {
            sidebar.selectedCameraIndex = nil
        }
        sidebar.overlayRevision += 1
        activeCameraPreset = nil
    }

    var doubleSided: Bool { previewSession.doubleSided }

    var showSkeleton: Bool { previewSession.showSkeleton }

    var fieldOfViewDegrees: Float { previewSession.fieldOfViewDegrees }

    func setDoubleSided(_ isOn: Bool) {
        previewSession.doubleSided = isOn
    }

    func setShowSkeleton(_ isOn: Bool) {
        previewSession.showSkeleton = isOn
    }

    func setFieldOfViewDegrees(_ degrees: Float) {
        previewSession.fieldOfViewDegrees = RenderCamera.clampedFieldOfView(degrees)
    }
}

extension FocusedValues {
    /// Key-window engine viewport for the host View menu (pill twin).
    @Entry var engineViewport: EngineViewportController?
}
