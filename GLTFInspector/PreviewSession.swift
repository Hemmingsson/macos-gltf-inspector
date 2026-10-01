import GLTFCore
import Observation
import PreviewUI

/// Host-owned per-window canvas state — the single source of truth the mounted canvas reads.
///
/// Renderer-neutral: the RealityKit window maps it onto `PreviewSessionBindings`
/// (`RealityKit/PreviewSession+RealityKit.swift`), the WebKit window onto the page `Look`.
/// Quick Look does not use this type.
///
/// The settings-backed keys (backdrop / floor / auto-rotate / center / projection) are not stored
/// here: they read and pin the window's `EngineSettingsStore`, so an untouched key tracks the app
/// default live.
@MainActor
@Observable
final class PreviewSession {
    let settings: EngineSettingsStore
    var exposureEV: Float = 0
    var dimStudioForFileLights = false
    var environmentYaw: Float = 0
    var doubleSided = false
    var showSkeleton = false
    var fieldOfViewDegrees = RenderCamera.defaultFieldOfViewDegrees
    var viewMode: RenderViewMode = .shaded
    /// Modes the open file offers (always starts with `.shaded`); `viewMode` is one of them.
    var viewModes: [RenderViewMode] = [.shaded]

    init(settings: EngineSettingsStore? = nil) {
        self.settings = settings ?? EngineSettingsStore()
    }

    var autoRotate: Bool {
        get { settings.sessionValue(for: .autoRotate) }
        set { settings.setSession(newValue, for: .autoRotate) }
    }

    var showFloor: Bool {
        get { settings.sessionValue(for: .showFloor) }
        set { settings.setSession(newValue, for: .showFloor) }
    }

    var backdrop: BackdropStyle {
        get { settings.sessionValue(for: .backdrop) }
        set { settings.setSession(newValue, for: .backdrop) }
    }

    var centerModel: Bool {
        get { settings.sessionValue(for: .center) }
        set { settings.setSession(newValue, for: .center) }
    }

    var orthographic: Bool {
        get { settings.sessionValue(for: .projection) == .orthographic }
        set { settings.setSession(newValue ? .orthographic : .perspective, for: .projection) }
    }
}
