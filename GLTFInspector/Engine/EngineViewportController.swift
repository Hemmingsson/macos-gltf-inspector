import CoreGraphics
import Foundation
import GLTFCore
import Observation
import PreviewUI
import RendererRealityKit
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
/// `EngineSettingsStore` on mutate. `previewSession` is the canvas source of truth; `applySession`
/// and `syncFromSettings` refresh untouched keys from the lazy overlay.
@MainActor
@Observable
final class EngineViewportController: ViewportController {
    var sidebar: HostSidebarModel
    let lookStore: AppLookStore

    /// Per-window lazy overlay. Weak to avoid a cycle with the store held by the window.
    weak var settings: EngineSettingsStore?

    /// Host-owned canvas session. Nil only in isolated unit tests.
    var previewSession: PreviewSession?

    /// Commands of the mounted canvas (`PreviewView` registers them). Nil while no canvas can
    /// take them, and in unit tests that only exercise setters.
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
        lookStore: AppLookStore? = nil,
        previewSession: PreviewSession? = nil,
        settings: EngineSettingsStore? = nil,
        commands: FocusedPreviewCommands? = nil,
        saveScreenshot: ((CGImage) async -> Void)? = nil
    ) {
        self.sidebar = sidebar
        self.lookStore = lookStore ?? .shared
        self.previewSession = previewSession ?? PreviewSession()
        self.settings = settings
        self.commands = commands
        self.saveScreenshot = saveScreenshot
    }

    /// Bind the lazy overlay and push effective session values without pinning untouched keys.
    func applySession(from settings: EngineSettingsStore) {
        self.settings = settings
        // Environment and tone mapping have no session override yet: they are app defaults, and
        // the extensions read the same two keys so all three surfaces agree.
        environment = StudioEnvironment(rawValue: settings.default(for: .environmentCatalog)) ?? .neutral
        toneMapping = ToneMapping.fromKhronosName(settings.default(for: .toneMapping))
        syncFromSettings()
    }

    /// Refresh settings-backed session fields when app defaults change (untouched keys only).
    func syncFromSettings() {
        guard let settings, let previewSession else { return }
        let backdrop: BackdropStyle = settings.sessionValue(for: .backdrop)
        previewSession.backdropIndex = PreviewBackground.index(matchingRawValue: backdrop.rawValue)
        previewSession.showFloor = settings.sessionValue(for: .showFloor)
        previewSession.autoRotate = settings.sessionValue(for: .autoRotate)
        previewSession.centerModel = settings.sessionValue(for: .center)
        let projection: Projection = settings.sessionValue(for: .projection)
        previewSession.orthographic = projection == .orthographic
    }

    var backdrop: BackdropStyle {
        if let settings {
            return settings.sessionValue(for: .backdrop)
        }
        guard let previewSession else { return .window }
        let raw = PreviewBackground.at(previewSession.backdropIndex).rawValue
        return BackdropStyle(rawValue: raw) ?? .window
    }

    var showsFloor: Bool {
        settings?.sessionValue(for: .showFloor) ?? previewSession?.showFloor ?? true
    }

    var autoRotates: Bool {
        settings?.sessionValue(for: .autoRotate) ?? previewSession?.autoRotate ?? true
    }

    var isCentered: Bool {
        settings?.sessionValue(for: .center) ?? previewSession?.centerModel ?? true
    }

    var viewMode: ViewMode {
        guard let previewSession else { return .shaded }
        let modes = previewSession.debugModes
        let index = previewSession.debugModeIndex
        guard modes.indices.contains(index) else { return .shaded }
        return Self.viewMode(for: modes[index])
    }

    var projection: Projection {
        if let settings {
            return settings.sessionValue(for: .projection)
        }
        return previewSession?.orthographic == true ? .orthographic : .perspective
    }

    var lighting: LightingSettings {
        LightingSettings(
            exposure: Double(previewSession?.exposureEV ?? 0),
            environmentRotationDegrees: Double(previewSession?.environmentYaw ?? 0) * 180 / .pi,
            usesFileLights: previewSession?.dimStudioForFileLights ?? false,
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
        settings?.setSession(style, for: .backdrop)
        previewSession?.backdropIndex = PreviewBackground.index(matchingRawValue: style.rawValue)
    }

    func setFloor(_ isOn: Bool) {
        settings?.setSession(isOn, for: .showFloor)
        previewSession?.showFloor = isOn
    }

    func setAutoRotate(_ isOn: Bool) {
        settings?.setSession(isOn, for: .autoRotate)
        previewSession?.autoRotate = isOn
    }

    func setCenter(_ isOn: Bool) {
        settings?.setSession(isOn, for: .center)
        previewSession?.centerModel = isOn
    }

    func setViewMode(_ mode: ViewMode) {
        guard let previewSession else { return }
        previewSession.debugModeIndex = Self.debugModeIndex(
            for: mode,
            in: previewSession.debugModes
        )
    }

    func setProjection(_ projection: Projection) {
        settings?.setSession(projection, for: .projection)
        previewSession?.orthographic = projection == .orthographic
    }

    func setLighting(_ lighting: LightingSettings) {
        // Per-window override; deliberately does not write the app default back.
        environment = lighting.environment
        toneMapping = lighting.toneMapping
        guard let previewSession else { return }
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
        setBackdrop(settings?.default(for: .backdrop) ?? .window)
        setFloor(settings?.default(for: .showFloor) ?? true)
        setAutoRotate(settings?.default(for: .autoRotate) ?? true)
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
        setFieldOfViewDegrees(PreviewCamera.defaultFieldOfViewDegrees)
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

    var doubleSided: Bool { previewSession?.doubleSided ?? false }

    var showSkeleton: Bool { previewSession?.showSkeleton ?? false }

    var fieldOfViewDegrees: Float {
        previewSession?.fieldOfViewDegrees ?? PreviewCamera.defaultFieldOfViewDegrees
    }

    func setDoubleSided(_ isOn: Bool) {
        previewSession?.doubleSided = isOn
    }

    func setShowSkeleton(_ isOn: Bool) {
        previewSession?.showSkeleton = isOn
    }

    func setFieldOfViewDegrees(_ degrees: Float) {
        previewSession?.fieldOfViewDegrees = PreviewCamera.clampedFieldOfView(degrees)
    }

    // MARK: - ViewMode ↔ PreviewDebugMode

    static func debugModeIndex(for mode: ViewMode, in modes: [PreviewDebugMode]) -> Int {
        switch mode {
        case .shaded:
            return modes.firstIndex(of: .none) ?? 0
        case .wireframe:
            return modes.firstIndex(of: .wire) ?? 0
        case .channel(let channel):
            if let index = modes.firstIndex(where: { matches($0, channel) }) {
                return index
            }
            return modes.firstIndex(of: .none) ?? 0
        }
    }

    static func viewMode(for mode: PreviewDebugMode) -> ViewMode {
        ViewMode(mode.renderViewMode)
    }

    private static func matches(_ mode: PreviewDebugMode, _ channel: DebugChannel) -> Bool {
        mode.renderViewMode == .channel(RenderViewMode.Channel(channel))
    }

    /// Maps the PreviewUI seam preset to `PreviewCamera.CameraPreset` (menu symbols).
    /// Shared with `HostViewMenuCommands`.
    static func previewCameraPreset(from preset: PreviewUI.CameraPreset) -> PreviewCamera.CameraPreset {
        PreviewCamera.CameraPreset(rawValue: preset.rawValue)!
    }
}

extension FocusedValues {
    /// Key-window engine viewport for the host View menu (pill twin).
    @Entry var engineViewport: EngineViewportController?
}
