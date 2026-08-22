import Foundation
import Observation
import RealityKit
import SwiftUI

/// Session + camera + still-path adapter for `ViewportController`.
///
/// Owns per-window view state (DESIGN.md this-window job). Fit / reset / presets / screenshot
/// forward to injected `FocusedPreviewCommands` (or a test `screenshotHandler`). Lighting maps
/// degrees↔radians and `usesFileLights`↔`dimStudioForFileLights`. `usesStudioEnvironment` mirrors
/// `AppLook.useEnvironmentMap` and is never written here — Settings owns that key.
///
/// Settings-backed keys (backdrop / floor / auto-rotate / center / projection) read through
/// `EngineSettingsStore` when set — untouched keys track app defaults live (P34). Mutators
/// pin only the key they touch. `hostSession` keeps the RealityKit canvas in sync.
@MainActor
@Observable
final class EngineViewportController: ViewportController {
    var sidebar: HostSidebarModel
    let lookStore: AppLookStore

    /// Per-window lazy overlay. Weak to avoid a cycle with the store held by the window.
    weak var settings: EngineSettingsStore?

    /// Host View-menu / pill command bag. Nil in unit tests that only exercise setters.
    var commands: FocusedPreviewCommands?

    /// Optional override so tests can assert `screenshot()` wires without presenting a panel.
    var screenshotHandler: (() -> Void)?

    /// Live host canvas session. Nil in unit tests.
    var hostSession: PreviewSessionBindings?

    private var storedBackdrop: BackdropStyle
    private var storedShowsFloor: Bool
    private var storedAutoRotates: Bool
    private var storedIsCentered: Bool
    private var storedViewMode: ViewMode
    private var storedProjection: Projection
    private(set) var activeCameraPreset: CameraPreset?

    /// Session exposure (stops) — host `sessionExposureEV`.
    private var storedExposureEV: Float
    /// Host `sessionDimStudioForFileLights`.
    private var storedDimStudioForFileLights: Bool
    /// Host `sessionEnvironmentYaw` (radians).
    private var storedEnvironmentYawRadians: Float
    /// Host-only extras (not on `ViewportController`).
    private var storedDoubleSided: Bool
    private var storedShowSkeleton: Bool
    private var storedFieldOfViewDegrees: Float

    init(
        sidebar: HostSidebarModel,
        lookStore: AppLookStore? = nil,
        backdrop: BackdropStyle = .window,
        showsFloor: Bool = true,
        autoRotates: Bool = true,
        isCentered: Bool = true,
        viewMode: ViewMode = .shaded,
        projection: Projection = .perspective,
        exposureEV: Float = 0,
        dimStudioForFileLights: Bool = false,
        environmentYawRadians: Float = 0,
        doubleSided: Bool = false,
        showSkeleton: Bool = false,
        fieldOfViewDegrees: Float = PreviewCamera.defaultFieldOfViewDegrees,
        settings: EngineSettingsStore? = nil,
        hostSession: PreviewSessionBindings? = nil,
        commands: FocusedPreviewCommands? = nil,
        screenshotHandler: (() -> Void)? = nil
    ) {
        self.sidebar = sidebar
        self.lookStore = lookStore ?? .shared
        self.storedBackdrop = backdrop
        self.storedShowsFloor = showsFloor
        self.storedAutoRotates = autoRotates
        self.storedIsCentered = isCentered
        self.storedViewMode = viewMode
        self.storedProjection = projection
        self.storedExposureEV = exposureEV
        self.storedDimStudioForFileLights = dimStudioForFileLights
        self.storedEnvironmentYawRadians = environmentYawRadians
        self.storedDoubleSided = doubleSided
        self.storedShowSkeleton = showSkeleton
        self.storedFieldOfViewDegrees = PreviewCamera.clampedFieldOfView(fieldOfViewDegrees)
        self.settings = settings
        self.hostSession = hostSession
        self.commands = commands
        self.screenshotHandler = screenshotHandler
    }

    /// Bind the lazy overlay and push effective session values without pinning untouched keys.
    func applySession(from settings: EngineSettingsStore) {
        self.settings = settings
        storedBackdrop = settings.sessionValue(for: .backdrop)
        storedShowsFloor = settings.sessionValue(for: .showFloor)
        storedAutoRotates = settings.sessionValue(for: .autoRotate)
        storedIsCentered = settings.sessionValue(for: .center)
        storedProjection = settings.sessionValue(for: .projection)
        syncHostCanvasFromStored()
    }

    var backdrop: BackdropStyle {
        settings?.sessionValue(for: .backdrop) ?? storedBackdrop
    }

    var showsFloor: Bool {
        settings?.sessionValue(for: .showFloor) ?? storedShowsFloor
    }

    var autoRotates: Bool {
        settings?.sessionValue(for: .autoRotate) ?? storedAutoRotates
    }

    var isCentered: Bool {
        settings?.sessionValue(for: .center) ?? storedIsCentered
    }

    var viewMode: ViewMode { storedViewMode }

    var projection: Projection {
        settings?.sessionValue(for: .projection) ?? storedProjection
    }

    var lighting: LightingSettings {
        LightingSettings(
            exposure: Double(storedExposureEV),
            environmentRotationDegrees: Double(storedEnvironmentYawRadians) * 180 / .pi,
            usesFileLights: storedDimStudioForFileLights,
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
        storedBackdrop = style
        settings?.setSession(style, for: .backdrop)
        if let hostSession {
            hostSession.backdropIndex.wrappedValue =
                PreviewBackground.index(matchingRawValue: style.rawValue)
        }
    }

    func setFloor(_ isOn: Bool) {
        storedShowsFloor = isOn
        settings?.setSession(isOn, for: .showFloor)
        hostSession?.showFloor.wrappedValue = isOn
    }

    func setAutoRotate(_ isOn: Bool) {
        storedAutoRotates = isOn
        settings?.setSession(isOn, for: .autoRotate)
        hostSession?.autoRotate.wrappedValue = isOn
    }

    func setCenter(_ isOn: Bool) {
        storedIsCentered = isOn
        settings?.setSession(isOn, for: .center)
        hostSession?.centerModel.wrappedValue = isOn
    }

    func setViewMode(_ mode: ViewMode) {
        storedViewMode = mode
        if let hostSession {
            hostSession.debugModeIndex.wrappedValue = Self.debugModeIndex(
                for: mode,
                in: hostSession.debugModes
            )
        }
    }

    func setProjection(_ projection: Projection) {
        storedProjection = projection
        settings?.setSession(projection, for: .projection)
        hostSession?.orthographic.wrappedValue = projection == .orthographic
    }

    func setLighting(_ lighting: LightingSettings) {
        storedExposureEV = Float(lighting.exposure)
        storedEnvironmentYawRadians = Float(lighting.environmentRotationDegrees * .pi / 180)
        storedDimStudioForFileLights = lighting.usesFileLights
        if let hostSession {
            hostSession.exposureEV.wrappedValue = storedExposureEV
            hostSession.environmentYaw.wrappedValue = storedEnvironmentYawRadians
            hostSession.dimStudioForFileLights.wrappedValue = storedDimStudioForFileLights
        }
        // Intentionally ignore `usesStudioEnvironment` — do not fight `AppLook.useEnvironmentMap`.
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

    func applyCameraPreset(_ preset: CameraPreset) {
        sidebar.selectedCameraIndex = nil
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

    var doubleSided: Bool { storedDoubleSided }

    var showSkeleton: Bool { storedShowSkeleton }

    var fieldOfViewDegrees: Float { storedFieldOfViewDegrees }

    func setDoubleSided(_ isOn: Bool) {
        storedDoubleSided = isOn
        hostSession?.doubleSided.wrappedValue = isOn
    }

    func setShowSkeleton(_ isOn: Bool) {
        storedShowSkeleton = isOn
        hostSession?.showSkeleton.wrappedValue = isOn
    }

    func setFieldOfViewDegrees(_ degrees: Float) {
        storedFieldOfViewDegrees = PreviewCamera.clampedFieldOfView(degrees)
        hostSession?.fieldOfViewDegrees.wrappedValue = storedFieldOfViewDegrees
    }

    /// Push stored settings-backed values into the RealityKit session bindings (open / clearSession).
    func syncHostCanvasFromStored() {
        guard let hostSession else { return }
        hostSession.backdropIndex.wrappedValue =
            PreviewBackground.index(matchingRawValue: backdrop.rawValue)
        hostSession.showFloor.wrappedValue = showsFloor
        hostSession.autoRotate.wrappedValue = autoRotates
        hostSession.centerModel.wrappedValue = isCentered
        hostSession.orthographic.wrappedValue = projection == .orthographic
        hostSession.exposureEV.wrappedValue = storedExposureEV
        hostSession.dimStudioForFileLights.wrappedValue = storedDimStudioForFileLights
        hostSession.environmentYaw.wrappedValue = storedEnvironmentYawRadians
        hostSession.doubleSided.wrappedValue = storedDoubleSided
        hostSession.showSkeleton.wrappedValue = storedShowSkeleton
        hostSession.fieldOfViewDegrees.wrappedValue = storedFieldOfViewDegrees
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

    private static func matches(_ mode: PreviewDebugMode, _ channel: DebugChannel) -> Bool {
        guard case .visualization(let visualization) = mode,
              let mapped = debugChannel(from: visualization)
        else { return false }
        return mapped == channel
    }

    private static func debugChannel(
        from visualization: ModelDebugOptionsComponent.VisualizationMode
    ) -> DebugChannel? {
        switch visualization {
        case .baseColor: .baseColor
        case .metallic: .metallic
        case .roughness: .roughness
        case .normal: .normals
        case .tangent: .tangents
        case .textureCoordinates: .textureCoordinates
        case .ambientOcclusion: .ambientOcclusion
        case .emissive: .emissive
        case .finalAlpha: .alpha
        case .specular: .specular
        case .clearcoat: .clearcoat
        case .clearcoatRoughness: .clearcoatRoughness
        case .clearcoatNormal: .clearcoatNormal
        default: nil
        }
    }

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

extension FocusedValues {
    /// Key-window engine viewport for the host View menu (pill twin).
    @Entry var engineViewport: EngineViewportController?
}
