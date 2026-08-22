import SwiftUI

/// Right column — the selected outliner row. Closed when nothing is selected.
///
/// Node sections bind to `selection.detail` and omit fields the node type does not have.
struct RightInspector<
    Model: SceneModel,
    Selection: SelectionModel
>: View {
    var model: Model
    var selection: Selection
    var documentState: ShellDocumentState = .ready
    var onScreenshot: () -> Void
    var onOpenIn: () -> Void
    /// Live morph weights from the host (`PreviewMorph`); shown when a morph is selected.
    var morphTargets: [MorphTargetControl] = []
    var onSetMorphWeight: (String, Double) -> Void = { _, _ in }

    @Environment(\.previewHair) private var hair

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if documentState.isReady, let detail = selection.detail {
                header(detail)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        nodeSections(detail)

                        if detail.kind == .morph, !morphTargets.isEmpty {
                            MorphWeightsSection(targets: morphTargets, onSetWeight: onSetMorphWeight)
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

    private func header(_ detail: NodeDetail) -> some View {
        NodeHeader(
            name: detail.name,
            kindTitle: detail.kind.displayTitle,
            kind: detail.kind,
            onScreenshot: onScreenshot,
            onOpenIn: onOpenIn
        )
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
        if detail.kind == .scene, let roots = detail.sceneRootCount {
            VStack(alignment: .leading, spacing: 0) {
                InspectorSectionHeader(title: "Scene")
                InspectorFactRow(label: "Roots", value: "\(roots)")
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
        }
        NodeExtrasSection(detail: detail)

        if detail.skin != nil || detail.morph != nil || detail.camera != nil
            || detail.light != nil || detail.animation != nil || detail.material != nil
            || detail.transform != nil || detail.geometry != nil || detail.sceneRootCount != nil
        {
            hair
                .frame(height: Theme.hairlineWidth)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
    }
}
