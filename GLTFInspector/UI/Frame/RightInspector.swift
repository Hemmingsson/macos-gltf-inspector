import SwiftUI

/// Right column — the selected outliner row. Closed when nothing is selected.
///
/// Sections omit fields the selected row's type does not have.
struct RightInspector: View {
    var detail: NodeDetail?
    var documentState: ShellDocumentState
    /// File-wide validator report. The inspector shows the issues about the selection.
    var validation: ValidationResult
    var documentURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if documentState.isReady, let detail {
                header(detail)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        IssuesSection(issues: validation.issues(for: detail.id))
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
                OpenInButton(documentURL: documentURL)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inspector")
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
