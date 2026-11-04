import DesignSystem
import SwiftUI

/// Quiet filler for a non-ready document. Copy and chrome stay per placement.
struct ShellStatusView: View {
    enum Placement {
        case sidebar
        case inspector
        case canvas
    }

    var state: ShellDocumentState
    var placement: Placement

    var body: some View {
        switch placement {
        case .sidebar, .inspector:
            status
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .canvas:
            status
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Color.Canvas.gradient)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(canvasAccessibilityLabel)
        }
    }

    /// Loading and failure copy is shared; only the empty state differs per placement. A ready
    /// document leaves the sidebar and canvas blank, while the inspector keeps its empty state.
    @ViewBuilder
    private var status: some View {
        switch state {
        case .loading:
            DSStatusView.loading(ShellStatusCopy.loadingTitle)
        case .failed(let message):
            DSStatusView.failed(ShellStatusCopy.failedTitle, message: message)
        case .empty:
            emptyStatus
        case .ready:
            if placement == .inspector {
                emptyStatus
            } else {
                EmptyView()
            }
        }
    }

    private var emptyStatus: DSStatusView {
        switch placement {
        case .sidebar:
            .empty(ShellStatusCopy.emptyTitle, systemImage: "cube", message: "No file open")
        case .inspector:
            .empty(
                "Nothing to inspect",
                systemImage: "sidebar.right",
                message: state == .empty ? "Open a file to see node and file details." : nil
            )
        case .canvas:
            .empty(ShellStatusCopy.emptyTitle, systemImage: "cube", message: ShellStatusCopy.emptyDetail)
        }
    }

    private var canvasAccessibilityLabel: String {
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

#Preview("sidebar empty", traits: .fixedLayout(width: 248, height: 200)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 200) {
        ShellStatusView(state: .empty, placement: .sidebar)
    }
}

#Preview("sidebar loading", traits: .fixedLayout(width: 248, height: 200)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 200) {
        ShellStatusView(state: .loading, placement: .sidebar)
    }
}

#Preview("sidebar failed", traits: .fixedLayout(width: 248, height: 200)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 200) {
        ShellStatusView(state: .failed(ShellStatusCopy.invalidFileDetail), placement: .sidebar)
    }
}

#Preview("inspector empty", traits: .fixedLayout(width: DS.Metrics.inspectorWidth, height: 200)) {
    PreviewCanvas(width: DS.Metrics.inspectorWidth, height: 200) {
        ShellStatusView(state: .empty, placement: .inspector)
    }
}

#Preview("inspector loading", traits: .fixedLayout(width: DS.Metrics.inspectorWidth, height: 200)) {
    PreviewCanvas(width: DS.Metrics.inspectorWidth, height: 200) {
        ShellStatusView(state: .loading, placement: .inspector)
    }
}

#Preview("inspector failed", traits: .fixedLayout(width: DS.Metrics.inspectorWidth, height: 200)) {
    PreviewCanvas(width: DS.Metrics.inspectorWidth, height: 200) {
        ShellStatusView(state: .failed(ShellStatusCopy.invalidFileDetail), placement: .inspector)
    }
}

#Preview("canvas empty", traits: .fixedLayout(width: 480, height: 320)) {
    PreviewCanvas(width: 480, height: 320, background: .canvas) {
        ShellStatusView(state: .empty, placement: .canvas)
    }
}

#Preview("canvas loading", traits: .fixedLayout(width: 480, height: 320)) {
    PreviewCanvas(width: 480, height: 320, background: .canvas) {
        ShellStatusView(state: .loading, placement: .canvas)
    }
}

#Preview("canvas failed", traits: .fixedLayout(width: 480, height: 320)) {
    PreviewCanvas(width: 480, height: 320, background: .canvas) {
        ShellStatusView(state: .failed(ShellStatusCopy.invalidFileDetail), placement: .canvas)
    }
}
