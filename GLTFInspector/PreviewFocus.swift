import CoreGraphics
import GLTFCore

/// Camera and still commands of the web canvas that is on screen. `DocumentWindow` registers them
/// (`FocusedPreviewCommands.web`); `EngineViewportController` forwards the View menu, the Camera
/// cluster and File ▸ Export PNG to whatever is registered, and the host owns the save panel.
@MainActor
struct FocusedPreviewCommands {
    let fit: () -> Void
    /// Opening view; the viewport restores Center and the session values first.
    let reset: () -> Void
    /// Session-only view preset; never persisted.
    let applyCameraPreset: (CameraPreset) -> Void
    /// One frame of the live canvas at its current camera pose. Pixels only — the caller presents
    /// the save panel and writes the PNG.
    let screenshot: () async throws -> CGImage
}
