import CoreGraphics
import GLTFCore
import SwiftUI

/// Camera and still commands of the canvas that is on screen. The mounted canvas registers them
/// (`RealityKit/` and `WebKit/` window roots); `EngineViewportController` forwards the View menu, the Camera pill and
/// File ▸ Export PNG to whatever is registered, and the host owns the save panel.
@MainActor
struct FocusedPreviewCommands {
    let fit: () -> Void
    /// Opening view; the viewport restores Center and the session values first.
    let reset: () -> Void
    /// Session-only view preset; never persisted.
    let applyCameraPreset: (CameraPreset) -> Void
    /// One frame at the live camera pose (an offscreen re-render on RealityKit, the live canvas
    /// on WebKit). Pixels only — the caller presents the save panel and writes the PNG.
    let screenshot: () async throws -> CGImage
}

extension FocusedValues {
    @Entry var previewCommands: FocusedPreviewCommands?
}
