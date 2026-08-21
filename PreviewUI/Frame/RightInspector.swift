import SwiftUI

/// Right column — the selected node, or the file summary when nothing is selected.
///
/// Never blank for a loaded model: clearing the selection returns to File + Validation + Pipeline.
/// Node sections bind to `selection.detail` and omit fields the node type does not have.
struct RightInspector<
    Model: SceneModel,
    Selection: SelectionModel
>: View {
    var model: Model
    var selection: Selection
    var documentState: ShellDocumentState = .ready
    /// Visual state of the trailing header toggle (accent while the column is open).
    var isInspectorVisible: Bool
    var onScreenshot: () -> Void
    var onOpenIn: () -> Void
    var onToggleInspector: () -> Void

    @Environment(\.previewHair) private var hair

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if documentState.isReady {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let detail = selection.detail {
                            nodeSections(detail)
                        }

                        FileSection(stats: model.stats, fileName: model.fileName)

                        ValidationSection(validation: model.validation)

                        if !model.pipelineReport.isEmpty {
                            PipelineSection(report: model.pipelineReport)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 14)
                }
                .focusSection()
            } else {
                InspectorStatusView(state: documentState)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.chrome)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector")
    }

    @ViewBuilder
    private var header: some View {
        if documentState.isReady, let detail = selection.detail {
            NodeHeader(
                name: detail.name,
                kindTitle: detail.kind.displayTitle,
                kind: detail.kind,
                isInspectorVisible: isInspectorVisible,
                onScreenshot: onScreenshot,
                onOpenIn: onOpenIn,
                onToggleInspector: onToggleInspector
            )
        } else {
            // File-level summary (or non-ready placeholder): same action row, document identity.
            NodeHeader(
                name: headerName,
                kindTitle: headerKind,
                kind: .scene,
                isInspectorVisible: isInspectorVisible,
                onScreenshot: onScreenshot,
                onOpenIn: onOpenIn,
                onToggleInspector: onToggleInspector
            )
        }
    }

    private var headerName: String {
        documentState.isReady ? model.fileName : documentState.panelDocumentTitle
    }

    private var headerKind: String {
        documentState.isReady ? "File" : "Inspector"
    }

    @ViewBuilder
    private func nodeSections(_ detail: NodeDetail) -> some View {
        if let transform = detail.transform {
            TransformSection(transform: transform, isAuthored: detail.isTransformAuthored)
        }
        if let geometry = detail.geometry {
            GeometrySection(geometry: geometry)
        }
        if let material = detail.material {
            MaterialSection(
                material: material,
                density: detail.kind == .material ? .full : .compact
            )
        }
        NodeExtrasSection(detail: detail)

        hair
            .frame(height: Theme.hairlineWidth)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }
}
