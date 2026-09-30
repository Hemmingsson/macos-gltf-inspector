import GLTFCore
import Observation
import PreviewUI

/// Host-owned per-window canvas state — the single source of truth the mounted canvas reads.
///
/// Renderer-neutral: the RealityKit window maps it onto `PreviewSessionBindings`
/// (`RealityKit/PreviewSession+RealityKit.swift`), the WebKit window onto the page `Look`.
/// Quick Look does not use this type.
@MainActor
@Observable
final class PreviewSession {
    var autoRotate = true
    var showFloor = true
    var backdrop = PreviewSession.storedBackdrop
    var centerModel = true
    var orthographic = false
    var exposureEV: Float = 0
    var dimStudioForFileLights = false
    var environmentYaw: Float = 0
    var doubleSided = false
    var showSkeleton = false
    var fieldOfViewDegrees = RenderCamera.defaultFieldOfViewDegrees
    var viewMode: RenderViewMode = .shaded
    /// Modes the open file offers (always starts with `.shaded`); `viewMode` is one of them.
    var viewModes: [RenderViewMode] = [.shaded]

    private static var storedBackdrop: BackdropStyle {
        let raw = AppGroupSettings.defaults.string(forKey: AppGroupSettings.Key.background)
        return raw.flatMap(BackdropStyle.init(rawValue:)) ?? .window
    }
}
