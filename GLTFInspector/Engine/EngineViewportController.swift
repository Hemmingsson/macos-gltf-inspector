import CoreGraphics
import Foundation
import GLTFCore
import Observation
import PreviewUI
import SwiftUI

/// Session + camera + still-path adapter for `ViewportController`.
///
/// Owns per-window view state (DESIGN.md this-window job). Fit / reset / presets / PNG export
/// forward to the `FocusedPreviewCommands` the web canvas registered; the PNG goes to the
/// host's `saveScreenshot` (save panel + write). Lighting maps the environment yaw
/// degrees↔radians.
///
/// Settings-backed keys (backdrop / floor / auto-rotate / center / projection) pin overrides in
/// the session's `EngineSettingsStore` on mutate; untouched keys track the app defaults live.
@MainActor
@Observable
final class EngineViewportController: ViewportController {
    var sidebar: HostSidebarModel

    /// Host-owned canvas session.
    let previewSession: PreviewSession

    /// Commands of the web canvas (`DocumentWindow` registers them). Nil while no canvas can take
    /// them, and in unit tests that only exercise setters.
    var commands: FocusedPreviewCommands?

    /// Host save panel + PNG write for `screenshot()`. Tests inject a recorder.
    var saveScreenshot: ((CGImage) async -> Void)?

    private(set) var activeCameraPreset: PreviewUI.CameraPreset?

    /// Per-window environment and tone mapping (not on `PreviewSession`, which cannot see PreviewUI
    /// types). Seeded from app defaults on `applySession`, then per-window.
    private(set) var environment: StudioEnvironment = .neutral
    private(set) var toneMapping: ToneMapping = .neutral

    init(
        sidebar: HostSidebarModel,
        previewSession: PreviewSession? = nil,
        saveScreenshot: ((CGImage) async -> Void)? = nil
    ) {
        self.sidebar = sidebar
        self.previewSession = previewSession ?? PreviewSession()
        self.saveScreenshot = saveScreenshot
    }

    /// Per-window lazy overlay (the session's `EngineSettingsStore`).
    var settings: EngineSettingsStore { previewSession.settings }

    /// A new document's lighting: environment and tone mapping from the app defaults, exposure
    /// and environment yaw back to zero.
    func applySession() {
        // Environment and tone mapping have no session override yet: they are app defaults, and
        // the extensions read the same two keys so all three surfaces agree.
        environment = defaultEnvironment
        toneMapping = defaultToneMapping
        previewSession.exposureEV = 0
        previewSession.environmentYaw = 0
    }

    /// Settings default for the bundled IBL, or Neutral when the stored name is unknown.
    private var defaultEnvironment: StudioEnvironment {
        StudioEnvironment(rawValue: settings.default(for: .environmentCatalog)) ?? .neutral
    }

    /// Settings default for the tone curve (`ToneMapping.khronosName`).
    private var defaultToneMapping: ToneMapping {
        ToneMapping.fromKhronosName(settings.default(for: .toneMapping))
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
    }

    func fit() {
        sidebar.selectedCameraNodeIndex = nil
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
                environment: defaultEnvironment,
                toneMapping: defaultToneMapping
            )
        )
        setFieldOfViewDegrees(RenderCamera.defaultFieldOfViewDegrees)
        sidebar.selectedCameraNodeIndex = nil
        activeCameraPreset = nil
        commands?.reset()
    }

    func applyCameraPreset(_ preset: PreviewUI.CameraPreset) {
        sidebar.selectedCameraNodeIndex = nil
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
    }

    func setFileCamera(_ id: NodeID?) {
        if let id {
            guard id.kind == .camera else { return }
            sidebar.selectedCameraNodeIndex = id.index
        } else {
            sidebar.selectedCameraNodeIndex = nil
        }
        activeCameraPreset = nil
    }

    var fieldOfViewDegrees: Float { previewSession.fieldOfViewDegrees }

    func setFieldOfViewDegrees(_ degrees: Float) {
        previewSession.fieldOfViewDegrees = RenderCamera.clampedFieldOfView(degrees)
    }
}

extension FocusedValues {
    /// Key-window engine viewport for the host View menu (cluster twin).
    @Entry var engineViewport: EngineViewportController?
}
