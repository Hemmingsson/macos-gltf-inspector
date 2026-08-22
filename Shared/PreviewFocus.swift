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

extension FocusedValues {
    @Entry var previewCommands: FocusedPreviewCommands?
}
