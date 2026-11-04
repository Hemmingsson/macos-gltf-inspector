import GLTFCore
import Renderer

extension FocusedPreviewCommands {
    /// The mounted canvas's commands.
    static func canvas(_ canvas: ModelCanvasController) -> Self {
        FocusedPreviewCommands(
            fit: { canvas.fit() },
            reset: { canvas.fit() },
            applyCameraPreset: { canvas.show($0) },
            zoom: { canvas.zoom(by: $0) },
            screenshot: { try canvas.snapshot() },
            zoomPercent: { canvas.zoomPercent }
        )
    }
}
