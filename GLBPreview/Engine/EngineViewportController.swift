import Foundation
import Observation

/// Session + camera + still-path adapter for `ViewportController`.
///
/// Owns per-window view state (DESIGN.md this-window job). Fit / reset / presets / screenshot
/// forward to injected `FocusedPreviewCommands` (or a test `screenshotHandler`). Lighting maps
/// degrees↔radians and `usesFileLights`↔`dimStudioForFileLights`. `usesStudioEnvironment` mirrors
/// `AppLook.useEnvironmentMap` and is never written here — Settings owns that key.
@MainActor
@Observable
final class EngineViewportController: ViewportController {
    let sidebar: HostSidebarModel
    let lookStore: AppLookStore

    /// Host View-menu / pill command bag. Nil in unit tests that only exercise setters.
    var commands: FocusedPreviewCommands?

    /// Optional override so tests can assert `screenshot()` wires without presenting a panel.
    var screenshotHandler: (() -> Void)?

    private(set) var backdrop: BackdropStyle
    private(set) var showsFloor: Bool
    private(set) var autoRotates: Bool
    private(set) var isCentered: Bool
    private(set) var viewMode: ViewMode
    private(set) var projection: Projection
    private(set) var activeCameraPreset: CameraPreset?

    /// Session exposure (stops) — host `sessionExposureEV`.
    private var exposureEV: Float
    /// Host `sessionDimStudioForFileLights`.
    private var dimStudioForFileLights: Bool
    /// Host `sessionEnvironmentYaw` (radians).
    private var environmentYawRadians: Float

    init(
        sidebar: HostSidebarModel,
        lookStore: AppLookStore = .shared,
        backdrop: BackdropStyle = .window,
        showsFloor: Bool = true,
        autoRotates: Bool = true,
        isCentered: Bool = true,
        viewMode: ViewMode = .shaded,
        projection: Projection = .perspective,
        exposureEV: Float = 0,
        dimStudioForFileLights: Bool = false,
        environmentYawRadians: Float = 0,
        commands: FocusedPreviewCommands? = nil,
        screenshotHandler: (() -> Void)? = nil
    ) {
        self.sidebar = sidebar
        self.lookStore = lookStore
        self.backdrop = backdrop
        self.showsFloor = showsFloor
        self.autoRotates = autoRotates
        self.isCentered = isCentered
        self.viewMode = viewMode
        self.projection = projection
        self.exposureEV = exposureEV
        self.dimStudioForFileLights = dimStudioForFileLights
        self.environmentYawRadians = environmentYawRadians
        self.commands = commands
        self.screenshotHandler = screenshotHandler
    }

    var lighting: LightingSettings {
        LightingSettings(
            exposure: Double(exposureEV),
            environmentRotationDegrees: Double(environmentYawRadians) * 180 / .pi,
            usesFileLights: dimStudioForFileLights,
            usesStudioEnvironment: lookStore.look.useEnvironmentMap
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
        backdrop = style
    }

    func setFloor(_ isOn: Bool) {
        showsFloor = isOn
    }

    func setAutoRotate(_ isOn: Bool) {
        autoRotates = isOn
    }

    func setCenter(_ isOn: Bool) {
        isCentered = isOn
    }

    func setViewMode(_ mode: ViewMode) {
        viewMode = mode
    }

    func setProjection(_ projection: Projection) {
        self.projection = projection
    }

    func setLighting(_ lighting: LightingSettings) {
        exposureEV = Float(lighting.exposure)
        environmentYawRadians = Float(lighting.environmentRotationDegrees * .pi / 180)
        dimStudioForFileLights = lighting.usesFileLights
        // Intentionally ignore `usesStudioEnvironment` — do not fight `AppLook.useEnvironmentMap`.
    }

    func fit() {
        commands?.fit()
        activeCameraPreset = nil
    }

    func reset() {
        backdrop = .window
        showsFloor = true
        autoRotates = true
        isCentered = true
        viewMode = .shaded
        projection = .perspective
        exposureEV = 0
        dimStudioForFileLights = false
        environmentYawRadians = 0
        activeCameraPreset = nil
        commands?.reset()
    }

    func applyCameraPreset(_ preset: CameraPreset) {
        activeCameraPreset = preset
        commands?.applyCameraPreset(Self.hostPreset(preset))
    }

    func screenshot() {
        if let screenshotHandler {
            screenshotHandler()
            return
        }
        commands?.screenshot()
    }

    func setScene(_ id: NodeID) {
        guard id.kind == .scene else { return }
        sidebar.activeSceneIndex = id.index
    }

    func setMaterialVariant(_ index: Int?) {
        sidebar.selectedMaterialVariantIndex = index
        sidebar.overlayRevision += 1
    }

    /// Host backdrop index for `PreviewBackground.at`.
    var hostBackdropIndex: Int {
        PreviewBackground.allCases.firstIndex(of: hostBackdrop) ?? 0
    }

    var hostBackdrop: PreviewBackground {
        PreviewBackground(rawValue: backdrop.rawValue) ?? .window
    }

    var hostOrthographic: Bool { projection == .orthographic }

    var hostExposureEV: Float { exposureEV }
    var hostDimStudioForFileLights: Bool { dimStudioForFileLights }
    var hostEnvironmentYawRadians: Float { environmentYawRadians }

    private static func hostPreset(_ preset: CameraPreset) -> PreviewCamera.CameraPreset {
        switch preset {
        case .front: .front
        case .back: .back
        case .left: .left
        case .right: .right
        case .top: .top
        case .bottom: .bottom
        case .isometric: .iso
        }
    }
}
