import GLTFCore
import RendererRealityKit
import SwiftUI

/// RealityKit document-window canvas: `RealityPreviewCanvas` over a converted model. Mounted only
/// once convert lands (loading and failure are drawn by PreviewUI's `CanvasRegion`); `State` is the
/// window's convert state. Quick Look has its own RealityKit root
/// (`PreviewExtension/QuickLookRealityKit.swift`).
struct PreviewView: View {
    enum State {
        case loading
        case ready(EntityLoader.LoadedModel)
        /// User-visible reason. Open never waits on IBL — lighting is applied later by `PreviewScene`.
        case failed(String)

        /// Model bytes → RealityKit only. No HDR / EnvironmentResource on this path.
        static func loaded(from url: URL) async -> State {
            do {
                let model = try await EntityLoader.load(from: url)
                return .ready(model)
            } catch {
                let message = error.localizedDescription
                AppLog.error(AppLog.preview, "open failed \(url.lastPathComponent): \(message)")
                return .failed(message)
            }
        }
    }

    let model: EntityLoader.LoadedModel
    var interaction: PreviewInteraction
    var isDark: Bool
    var sidebar: (any PreviewOverlay)? = nil
    /// Host passes `HostSidebarModel.overlayRevision` so RealityView updates on select/hide.
    /// Reading it through `any PreviewOverlay` alone is not a reliable SwiftUI dependency.
    var overlayRevision: Int = 0
    /// Host-owned session; nil lets `PreviewScene` seed local `@State`.
    var session: PreviewSessionBindings? = nil
    /// RealityKit camera commands, registered while the canvas is mounted.
    var commands: FocusedPreviewCommands? = nil
    /// Called with the mounted canvas's commands. Runs in `onAppear`, never during a view update.
    var registerCommands: (FocusedPreviewCommands?) -> Void = { _ in }

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
