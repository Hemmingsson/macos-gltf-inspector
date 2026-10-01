import DesignSystem
import SwiftUI

/// Quiet sidebar filler when there is no ready document — `DSStatusView` /
/// `ContentUnavailableView`.
public struct SidebarStatusView: View {
    public var state: ShellDocumentState

    public var body: some View {
        Group {
            switch state {
            case .empty:
                DSStatusView.empty(
                    ShellStatusCopy.emptyTitle,
                    systemImage: "cube",
                    message: "No file open"
                )
            case .loading:
                DSStatusView.loading(ShellStatusCopy.loadingTitle)
            case .failed(let message):
                DSStatusView.failed(ShellStatusCopy.failedTitle, message: message)
            case .ready:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

#Preview("empty", traits: .fixedLayout(width: 248, height: 200)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 200) {
        SidebarStatusView(state: .empty)
    }
}

#Preview("loading", traits: .fixedLayout(width: 248, height: 200)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 200) {
        SidebarStatusView(state: .loading)
    }
}

#Preview("failed", traits: .fixedLayout(width: 248, height: 200)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 200) {
        SidebarStatusView(state: .failed(ShellStatusCopy.invalidFileDetail))
    }
}
