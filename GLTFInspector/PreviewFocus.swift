import CoreGraphics
import GLTFCore
import RendererWebKit
import SwiftUI

/// Camera and still commands of the canvas that is on screen. The mounted canvas registers them
/// (`PreviewView`); `EngineViewportController` forwards the View menu, the Camera pill and
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

extension FocusedPreviewCommands {
    /// The web canvas's commands. Camera moves are fire-and-forget like the RealityKit ones; a
    /// failure only means the page was not ready, so it is logged, not surfaced.
    static func web(_ canvas: WebCanvasController) -> Self {
        func run(_ name: String, _ action: @escaping @MainActor () async throws -> Void) {
            Task { @MainActor in
                do {
                    try await action()
                } catch {
                    AppLog.error(AppLog.host, "web canvas \(name) failed: \(error.localizedDescription)")
                }
            }
        }
        return FocusedPreviewCommands(
            fit: { run("fit") { try await canvas.fit() } },
            reset: { run("reset") { try await canvas.reset() } },
            applyCameraPreset: { preset in
                run("preset \(preset.rawValue)") { try await canvas.apply(preset: preset) }
            },
            screenshot: { try await canvas.snapshot() }
        )
    }
}

extension FocusedValues {
    @Entry var previewCommands: FocusedPreviewCommands?
}
