import DesignSystem
import SwiftUI

/// Right column — the selected outliner row. Closed when nothing is selected.
///
/// Node sections bind to `selection.detail` and omit fields the node type does not have.
/// `openInMenu` is menu items (Finder, Blender, …); the header wraps them in `DSGlassMenuButton`.
public struct RightInspector<Selection: SelectionModel>: View {
    public var selection: Selection
    public var documentState: ShellDocumentState = .ready
    public var openInMenu: AnyView
    /// Live morph weights from the host (`PreviewMorph`); shown when a morph is selected.
    public var morphTargets: [MorphTargetControl] = []
    public var onSetMorphWeight: (String, Double) -> Void = { _, _ in }

    public init(
        selection: Selection,
        documentState: ShellDocumentState = .ready,
        openInMenu: AnyView,
        morphTargets: [MorphTargetControl] = [],
        onSetMorphWeight: @escaping (String, Double) -> Void = { _, _ in }
    ) {
        self.selection = selection
        self.documentState = documentState
        self.openInMenu = openInMenu
        self.morphTargets = morphTargets
        self.onSetMorphWeight = onSetMorphWeight
    }

    public var body: some View {
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
                    .padding(.bottom, DS.Spacing.xl)
                }
                .focusSection()
            } else {
                InspectorStatusView(state: documentState)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector")
    }

    private func header(_ detail: NodeDetail) -> some View {
        NodeHeader(
            name: detail.name,
            kindTitle: detail.kind.displayTitle,
            kind: detail.kind,
            openInMenu: openInMenu
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
                InspectorSectionHeader("Scene")
                DSFactRow("Roots", value: "\(roots)")
                    .padding(.horizontal, DS.Spacing.l)
                    .padding(.bottom, DS.Spacing.m)
            }
        }
        NodeExtrasSection(detail: detail)

        if detail.skin != nil || detail.morph != nil || detail.camera != nil
            || detail.light != nil || detail.animation != nil || detail.material != nil
            || detail.transform != nil || detail.geometry != nil || detail.sceneRootCount != nil
        {
            DS.Color.separator
                .frame(height: DS.Metrics.hairline)
                .padding(.horizontal, DS.Spacing.l)
                .padding(.vertical, DS.Spacing.m)
        }
    }
}

// MARK: - Previews

private struct RightInspectorPreviewHost: View {
    enum Mode {
        case mesh
        case material
        case morph
        case empty
        case loading
        case failed
    }

    var mode: Mode
    @State private var selection: MockSelectionModel

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .mesh:
            _selection = State(initialValue: MockSelectionModel())
        case .material:
            _selection = State(
                initialValue: MockSelectionModel(
                    selected: NodeDetailFixtures.material.id,
                    details: [NodeDetailFixtures.mesh, NodeDetailFixtures.material]
                )
            )
        case .morph:
            _selection = State(
                initialValue: MockSelectionModel(
                    selected: NodeDetailFixtures.morph.id,
                    details: [NodeDetailFixtures.morph]
                )
            )
        case .empty:
            _selection = State(initialValue: MockSelectionModel(selected: nil))
        case .loading, .failed:
            _selection = State(initialValue: MockSelectionModel())
        }
    }

    private var documentState: ShellDocumentState {
        switch mode {
        case .mesh, .material, .morph, .empty: .ready
        case .loading: .loading
        case .failed: .failed(ShellStatusCopy.invalidFileDetail)
        }
    }

    private var height: CGFloat {
        switch mode {
        case .mesh, .material, .morph: 520
        case .empty, .loading, .failed: 240
        }
    }

    var body: some View {
        PreviewCanvas(width: DS.Metrics.inspectorWidth, height: height) {
            RightInspector(
                selection: selection,
                documentState: documentState,
                openInMenu: AnyView(PreviewOpenInItems()),
                morphTargets: mode == .morph ? MorphFixtures.faceControls : [],
                onSetMorphWeight: { _, _ in }
            )
        }
    }
}

#Preview("mesh", traits: .fixedLayout(width: DS.Metrics.inspectorWidth, height: 520)) {
    RightInspectorPreviewHost(mode: .mesh)
}

#Preview("material", traits: .fixedLayout(width: DS.Metrics.inspectorWidth, height: 520)) {
    RightInspectorPreviewHost(mode: .material)
}

#Preview("morph", traits: .fixedLayout(width: DS.Metrics.inspectorWidth, height: 520)) {
    RightInspectorPreviewHost(mode: .morph)
}

#Preview("empty", traits: .fixedLayout(width: DS.Metrics.inspectorWidth, height: 240)) {
    RightInspectorPreviewHost(mode: .empty)
}

#Preview("loading", traits: .fixedLayout(width: DS.Metrics.inspectorWidth, height: 240)) {
    RightInspectorPreviewHost(mode: .loading)
}

#Preview("failed", traits: .fixedLayout(width: DS.Metrics.inspectorWidth, height: 240)) {
    RightInspectorPreviewHost(mode: .failed)
}
