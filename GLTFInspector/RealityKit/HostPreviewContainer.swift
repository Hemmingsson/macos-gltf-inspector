import RendererRealityKit
import SwiftUI

/// Hosts the RealityKit `PreviewView` in a `PreviewHostingView`, which forwards trackpad
/// scroll / magnify and orbit drags into `PreviewInteraction`.
struct HostPreviewContainer: NSViewRepresentable {
    var state: PreviewView.State
    var interaction: PreviewInteraction
    var isDark: Bool
    var sidebar: HostSidebarModel?
    /// Mirrors `HostSidebarModel.overlayRevision` so selection/hide triggers `updateNSView`.
    var overlayRevision: Int
    var session: PreviewSessionBindings
    var commands: FocusedPreviewCommands?
    var registerCommands: (FocusedPreviewCommands?) -> Void

    private var rootView: PreviewView {
        PreviewView(
            state: state,
            interaction: interaction,
            isDark: isDark,
            sidebar: sidebar,
            overlayRevision: overlayRevision,
            session: session,
            commands: commands,
            registerCommands: registerCommands
        )
    }

    func makeNSView(context: Context) -> PreviewHostingView<PreviewView> {
        let view = PreviewHostingView(rootView: rootView)
        view.interaction = interaction
        return view
    }

    func updateNSView(_ nsView: PreviewHostingView<PreviewView>, context: Context) {
        nsView.interaction = interaction
        nsView.rootView = rootView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PreviewHostingView<PreviewView>, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.bounds.width,
            height: proposal.height ?? nsView.bounds.height
        )
    }
}
