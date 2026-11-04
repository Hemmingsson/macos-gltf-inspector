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

    @Environment(\.openFilePanel) private var openFilePanel
    @Environment(\.openRecentMenu) private var openRecentMenu

    var body: some View {
        switch placement {
        case .sidebar, .inspector:
            status
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .canvas:
            Group {
                if case .empty = state {
                    canvasEmpty
                } else {
                    status
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(canvasAccessibilityLabel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if case .empty = state {
                    DS.Color.windowBackground.ignoresSafeArea()
                } else {
                    DS.Color.Canvas.gradient.ignoresSafeArea()
                }
            }
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
            .empty(ShellStatusCopy.emptyTitle, systemImage: "cube", message: ShellStatusCopy.emptySidebarDetail)
        case .inspector:
            .empty(
                "Nothing to inspect",
                systemImage: "sidebar.right",
                message: state == .empty ? "Open a file to see node and file details." : nil
            )
        case .canvas:
            .empty(ShellStatusCopy.emptyCanvasTitle, systemImage: "cube", message: nil)
        }
    }

    /// System empty state: symbol, short title, one sentence, then actions.
    /// The default button is trailing, matching macOS button order.
    private var canvasEmpty: some View {
        ContentUnavailableView {
            Label(ShellStatusCopy.emptyCanvasTitle, systemImage: "cube")
        } description: {
            Text(ShellStatusCopy.emptyOpenHint)
        } actions: {
            HStack(spacing: DS.Spacing.m) {
                Button("Open Recent", action: openRecentMenu.call)
                Button("Open…", action: openFilePanel.call)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var canvasAccessibilityLabel: String {
        switch state {
        case .empty:
            ShellStatusCopy.emptyOpenHint
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
