import DesignSystem
import SwiftUI

/// Right column — the selected outliner row, or the whole model when the document card is
/// selected (name, file kind, validation). Closed when nothing is selected.
///
/// Node sections bind to `selection.detail` and omit fields the node type does not have.
/// `openInMenu` is menu items (Finder, Blender, …); the header wraps them in `DSGlassMenuButton`.
struct RightInspector<Selection: SelectionModel>: View {
    var selection: Selection
    var documentState: ShellDocumentState = .ready
    /// Set while the whole model is selected; wins over `selection.detail`.
    var document: DocumentSummary? = nil
    var openInMenu: AnyView

    /// What the inspector shows for the whole model.
    struct DocumentSummary {
        var fileName: String
        var validation: ValidationResult
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if documentState.isReady, let document {
                documentInspector(document)
            } else if documentState.isReady, let detail = selection.detail {
                header(detail)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        nodeSections(detail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, DS.Spacing.xl)
                }
                .focusSection()
            } else {
                ShellStatusView(state: documentState, placement: .inspector)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.paneFill, ignoresSafeAreaEdges: .all)
        // Same spot as the canvas's floating Open-in while the inspector is closed: on the
        // traffic-light line with the toolbar clusters.
        .overlay(alignment: .topTrailing) {
            if documentState.isReady {
                ActionRow(openInMenu: openInMenu)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector")
    }

    private func documentInspector(_ document: DocumentSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            IdentityRow(
                documentName: DocumentIdentity.title(document.fileName),
                kind: DocumentIdentity.kind(document.fileName) ?? "glTF"
            )
            ScrollView {
                ValidationSection(validation: document.validation)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, DS.Spacing.xl)
            }
            .focusSection()
        }
        .accessibilityElement(children: .contain)
    }

    private func header(_ detail: NodeDetail) -> some View {
        NodeHeader(name: detail.name, kind: detail.kind)
    }

    @ViewBuilder
    private func nodeSections(_ detail: NodeDetail) -> some View {
        if let transform = detail.transform {
            TransformSection(transform: transform)
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

        if detail.hasBody {
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
                openInMenu: AnyView(PreviewOpenInItems())
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
