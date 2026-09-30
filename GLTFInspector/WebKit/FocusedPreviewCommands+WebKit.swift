import GLTFCore
import RendererWebKit

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
