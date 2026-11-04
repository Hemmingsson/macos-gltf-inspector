import RendererRealityKit
import SwiftUI

/// RealityKit document-window canvas: `RealityPreviewCanvas` over a converted model. Mounted only
/// once convert lands (loading and failure are drawn by PreviewUI's `CanvasRegion`). Quick Look
/// has its own RealityKit root (`PreviewExtension/QuickLookRealityKit.swift`).
struct RealityCanvasView: View {
    let model: EntityLoader.LoadedModel
    var interaction: PreviewInteraction
    var isDark: Bool
    var sidebar: (any PreviewOverlay)?
    /// Host passes `HostSidebarModel.overlayRevision` so RealityView updates on select/hide.
    /// Reading it through `any PreviewOverlay` alone is not a reliable SwiftUI dependency.
    var overlayRevision: Int
    /// Host-owned session; nil lets `PreviewScene` seed local `@State`.
    var session: PreviewSessionBindings?
    /// RealityKit camera commands, registered while the canvas is mounted.
    var commands: FocusedPreviewCommands?
    /// Called with the mounted canvas's commands. Runs in `onAppear`, never during a view update.
    var registerCommands: (FocusedPreviewCommands?) -> Void

    var body: some View {
        RealityPreviewCanvas(
            model: model,
            interaction: interaction,
            isDark: isDark,
            sidebar: sidebar,
            overlayRevision: overlayRevision,
            session: session
        )
        .onAppear { registerCommands(commands) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
