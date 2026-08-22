import RealityKit
import SwiftUI

/// Host RealityKit canvas for `HostShellRootView` (`ShellRootView` canvas).
struct HostPreviewContainer: NSViewRepresentable {
    var state: PreviewView.State
    var interaction: PreviewInteraction
    var isDark: Bool
    var sidebar: HostSidebarModel?
    /// Mirrors `HostSidebarModel.overlayRevision` so selection/hide triggers `updateNSView`.
    var overlayRevision: Int
    var session: PreviewSessionBindings

    func makeNSView(context: Context) -> PreviewHostingView {
        let view = PreviewHostingView(
            rootView: PreviewView(
                state: state,
                interaction: interaction,
                isDark: isDark,
                sidebar: sidebar,
                overlayRevision: overlayRevision,
                session: session
            )
        )
        view.interaction = interaction
        return view
    }

    func updateNSView(_ nsView: PreviewHostingView, context: Context) {
        nsView.interaction = interaction
        nsView.rootView = PreviewView(
            state: state,
            interaction: interaction,
            isDark: isDark,
            sidebar: sidebar,
            overlayRevision: overlayRevision,
            session: session
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PreviewHostingView, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.bounds.width,
            height: proposal.height ?? nsView.bounds.height
        )
    }
}
