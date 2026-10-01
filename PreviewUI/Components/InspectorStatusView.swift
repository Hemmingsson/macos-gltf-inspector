import DesignSystem
import SwiftUI

/// Quiet inspector filler when there is no ready selection or document.
public struct InspectorStatusView: View {
    public var state: ShellDocumentState

    public var body: some View {
        status
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .empty, .ready:
            DSStatusView.empty(
                "Nothing to inspect",
                systemImage: "sidebar.right",
                message: state == .empty
                    ? "Open a file to see node and file details."
                    : nil
            )
        case .loading:
            DSStatusView.loading(ShellStatusCopy.loadingTitle)
        case .failed(let message):
            DSStatusView.failed(ShellStatusCopy.failedTitle, message: message)
        }
    }
}

// MARK: - Previews

#Preview("empty", traits: .fixedLayout(width: DS.Metrics.inspectorWidth, height: 200)) {
    PreviewCanvas(width: DS.Metrics.inspectorWidth, height: 200) {
        InspectorStatusView(state: .empty)
    }
}

#Preview("loading", traits: .fixedLayout(width: DS.Metrics.inspectorWidth, height: 200)) {
    PreviewCanvas(width: DS.Metrics.inspectorWidth, height: 200) {
        InspectorStatusView(state: .loading)
    }
}

#Preview("failed", traits: .fixedLayout(width: DS.Metrics.inspectorWidth, height: 200)) {
    PreviewCanvas(width: DS.Metrics.inspectorWidth, height: 200) {
        InspectorStatusView(state: .failed(ShellStatusCopy.invalidFileDetail))
    }
}
