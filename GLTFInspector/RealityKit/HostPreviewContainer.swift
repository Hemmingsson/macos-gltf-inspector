import RendererRealityKit
import SwiftUI

/// Hosts the RealityKit `RealityCanvasView` in a `PreviewHostingView`, which forwards trackpad
/// scroll / magnify and orbit drags into `PreviewInteraction`.
struct HostPreviewContainer: NSViewRepresentable {
    var model: EntityLoader.LoadedModel
    var interaction: PreviewInteraction
    var isDark: Bool
    var sidebar: HostSidebarModel?
    /// Mirrors `HostSidebarModel.overlayRevision` so selection/hide triggers `updateNSView`.
    var overlayRevision: Int
    var session: PreviewSessionBindings
    var commands: FocusedPreviewCommands?
    var registerCommands: (FocusedPreviewCommands?) -> Void

    private var rootView: RealityCanvasView {
        RealityCanvasView(
            model: model,
            interaction: interaction,
            isDark: isDark,
            sidebar: sidebar,
            overlayRevision: overlayRevision,
            session: session,
            commands: commands,
            registerCommands: registerCommands
        )
    }

    func makeNSView(context: Context) -> PreviewHostingView<RealityCanvasView> {
        let view = PreviewHostingView(rootView: rootView)
        view.interaction = interaction
        return view
    }

    func updateNSView(_ nsView: PreviewHostingView<RealityCanvasView>, context: Context) {
        nsView.interaction = interaction
        nsView.rootView = rootView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PreviewHostingView<RealityCanvasView>, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.bounds.width,
            height: proposal.height ?? nsView.bounds.height
        )
    }
}
