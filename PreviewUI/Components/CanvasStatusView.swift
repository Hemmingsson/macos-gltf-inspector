import DesignSystem
import SwiftUI

/// Centered status over the canvas (empty / loading / failed).
public struct CanvasStatusView: View {
    public var state: ShellDocumentState

    public var body: some View {
        status
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Color.Canvas.gradient)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .empty:
            DSStatusView.empty(
                ShellStatusCopy.emptyTitle,
                systemImage: "cube",
                message: ShellStatusCopy.emptyDetail
            )
        case .loading:
            DSStatusView.loading(ShellStatusCopy.loadingTitle)
        case .failed(let message):
            DSStatusView.failed(ShellStatusCopy.failedTitle, message: message)
        case .ready:
            EmptyView()
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .empty:
            "\(ShellStatusCopy.emptyTitle). \(ShellStatusCopy.emptyDetail)"
        case .loading:
            ShellStatusCopy.loadingTitle
        case .failed(let message):
            "\(ShellStatusCopy.failedTitle). \(message)"
        case .ready:
            "Canvas"
        }
    }
}

// MARK: - Previews

#Preview("empty", traits: .fixedLayout(width: 480, height: 320)) {
    PreviewCanvas(width: 480, height: 320, background: .canvas) {
        CanvasStatusView(state: .empty)
    }
}

#Preview("loading", traits: .fixedLayout(width: 480, height: 320)) {
    PreviewCanvas(width: 480, height: 320, background: .canvas) {
        CanvasStatusView(state: .loading)
    }
}

#Preview("failed", traits: .fixedLayout(width: 480, height: 320)) {
    PreviewCanvas(width: 480, height: 320, background: .canvas) {
        CanvasStatusView(state: .failed(ShellStatusCopy.invalidFileDetail))
    }
}
