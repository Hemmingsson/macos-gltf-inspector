import SwiftUI

/// Host View-menu Fit / Reset / camera presets / Screenshot for the focused document window.
@MainActor
struct FocusedPreviewCommands {
    let fit: () -> Void
    /// Opening front-3/4 fit; restores Center when it was off.
    let reset: () -> Void
    /// Session-only view preset; never persisted.
    let applyCameraPreset: (PreviewCamera.CameraPreset) -> Void
    /// Offscreen re-render at the live camera pose + save panel (not a framebuffer grab).
    let screenshot: () -> Void
}

/// Per-window View-menu focus mirror of `PreviewSessionBindings` (same fields, no backdrop —
/// backdrop cycles from the canvas chrome). Seeded from Settings where applicable;
/// never persisted for center/ortho/lighting/FOV/double-sided.
@MainActor
struct FocusedPreviewSession {
    var autoRotate: Binding<Bool>
    var showFloor: Binding<Bool>
    var centerModel: Binding<Bool>
    var orthographic: Binding<Bool>
    /// ±EV on top of file-vs-studio base (0 or −2).
    var exposureEV: Binding<Float>
    /// True → dim studio IBL (−2) so file punctual lights read; false → studio full (0).
    var dimStudioForFileLights: Binding<Bool>
    /// IBL probe yaw (radians); re-applied after every `applyLook` rebuild.
    var environmentYaw: Binding<Float>
    /// Force `faceCulling = .none` on materials; session-only.
    var doubleSided: Binding<Bool>
    /// Skeleton joint/bone overlay; session-only; hide when no skins.
    var showSkeleton: Binding<Bool>
    /// Perspective FOV degrees; session-only; no-op while ortho.
    var fieldOfViewDegrees: Binding<Float>
}

extension PreviewSessionBindings {
    /// View-menu FocusedValues surface — backdrop stays on the canvas chrome.
    /// Lives here (not on `PreviewSessionBindings`) so ThumbnailExtension can compile
    /// the bindings bag without host focus types.
    @MainActor
    var focusedMenu: FocusedPreviewSession {
        FocusedPreviewSession(
            autoRotate: autoRotate,
            showFloor: showFloor,
            centerModel: centerModel,
            orthographic: orthographic,
            exposureEV: exposureEV,
            dimStudioForFileLights: dimStudioForFileLights,
            environmentYaw: environmentYaw,
            doubleSided: doubleSided,
            showSkeleton: showSkeleton,
            fieldOfViewDegrees: fieldOfViewDegrees
        )
    }
}

extension FocusedValues {
    @Entry var previewCommands: FocusedPreviewCommands?
    @Entry var previewSession: FocusedPreviewSession?
}
