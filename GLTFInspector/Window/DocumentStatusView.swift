import AppKit
import SwiftUI

/// Quiet filler for a non-ready document. Copy and chrome stay per placement.
struct DocumentStatusView: View {
    enum Placement {
        case sidebar
        case inspector
        case canvas
    }

    var state: DocumentState
    var placement: Placement

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
            VStack(spacing: DS.Spacing.m) {
                ProgressView()
                    .accessibilityHidden(true)
                Text(Copy.loadingTitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case .failed(let message):
            ContentUnavailableView(Copy.failedTitle, systemImage: "exclamationmark.triangle", description: Text(message))
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

    @ViewBuilder
    private var emptyStatus: some View {
        if placement == .inspector {
            ContentUnavailableView {
                Label("Nothing to inspect", systemImage: "sidebar.right")
            } description: {
                if state == .empty { Text("Open a file to see node and file details.") }
            }
        } else {
            ContentUnavailableView(Copy.emptyTitle, systemImage: "cube", description: Text(Copy.emptySidebarDetail))
        }
    }

    /// System empty state: symbol, short title, one sentence, then actions.
    /// The default button is trailing, matching macOS button order.
    private var canvasEmpty: some View {
        ContentUnavailableView {
            Label(Copy.emptyCanvasTitle, systemImage: "cube")
        } description: {
            Text(Copy.emptyOpenHint)
        } actions: {
            HStack(spacing: DS.Spacing.m) {
                Button("Open Recent") { RecentGLTFFiles.popUpMenu() }
                Button("Open…") { NSDocumentController.shared.openDocument(nil) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var canvasAccessibilityLabel: String {
        switch state {
        case .empty:
            Copy.emptyOpenHint
        case .loading:
            Copy.loadingTitle
        case .failed(let message):
            "\(Copy.failedTitle). \(message)"
        case .ready:
            "Canvas"
        }
    }

    private enum Copy {
        static let emptyTitle = "Open a glTF file"
        static let emptySidebarDetail = "No file open"
        static let emptyCanvasTitle = "No File"
        static let emptyOpenHint = "Drop a .glb or .gltf file here."
        static let loadingTitle = "Loading model…"
        static let failedTitle = "Couldn’t load model"
    }
}
