import AppKit
import SwiftUI

/// Quiet filler for a non-ready document. Copy and chrome stay per placement.
struct DocumentStatusView: View {
    enum Placement {
        case inspector
        case canvas
    }

    var state: DocumentState
    var placement: Placement

    var body: some View {
        switch placement {
        case .inspector:
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
    /// document leaves the canvas blank, while the inspector keeps its empty state.
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
            ContentUnavailableView(Copy.failedTitle, systemImage: "exclamationmark.triangle",
                                   description: Text(Copy.failureDescription(for: message)))
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

    /// Only the inspector asks for this: the canvas draws its own empty state, the sidebar none.
    private var emptyStatus: some View {
        ContentUnavailableView {
            DSLabel("Nothing to inspect", DSGlyphs.inspector)
        } description: {
            if state == .empty { Text("Open a file to see node and file details.") }
        }
    }

    /// System empty state: symbol, short title, one sentence, then actions.
    /// The default button is trailing, matching macOS button order.
    private var canvasEmpty: some View {
        ContentUnavailableView {
            DSLabel(Copy.emptyCanvasTitle, NodeKind.mesh.glyph)
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
            "\(Copy.failedTitle). \(Copy.failureDescription(for: message))"
        case .ready:
            "Canvas"
        }
    }

    private enum Copy {
        static let emptyCanvasTitle = "No File"
        static let emptyOpenHint = "Drop a .glb or .gltf file here."
        static let loadingTitle = "Loading model…"
        static let failedTitle = "Couldn’t load model"

        static func failureDescription(for message: String) -> String {
            if message == "Not a .glb / .gltf file" {
                return "Choose a .glb or .gltf file."
            }
            return "The model could not be loaded. Check the file and try again."
        }
    }
}
