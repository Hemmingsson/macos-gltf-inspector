import SwiftUI

/// Left column — structure. The document says which file this is; the outliner says what is in it.
///
/// Generic over both seam types rather than taking existentials: `SceneModel` has `Self`
/// requirements through its default implementations.
public struct LeftSidebar<Model: SceneModel, Selection: SelectionModel, Viewport: ViewportController>: View {
    public var model: Model
    /// Injected, not owned — the window root owns it, and the inspector reads the same instance.
    public var selection: Selection
    public var viewport: Viewport
    public var documentState: ShellDocumentState = .ready
    /// Visual state of the leading chrome toggle (accent while the column is open).
    public var isSidebarVisible: Bool
    public var onToggleSidebar: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarChromeRow(
                isSidebarVisible: isSidebarVisible,
                trailingAligned: true,
                onToggleSidebar: onToggleSidebar
            )

            DocumentHeader(
                fileName: documentState.isReady ? model.fileName : documentState.panelDocumentTitle,
                sceneName: documentState.isReady ? currentSceneName : nil,
                variantNames: documentState.isReady ? model.materialVariantNames : [],
                selectedVariantIndex: viewport.selectedMaterialVariantIndex,
                onSelectVariant: { viewport.setMaterialVariant($0) }
            )

            if documentState.isReady {
                // Scrolls independently of the document header and the pinned file footer.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(OutlinerSection.sections(of: model)) { section in
                            OutlinerSectionView(
                                section: section,
                                selection: selection,
                                onSelect: { item in
                                    if item.id.kind == .scene {
                                        viewport.setScene(item.id)
                                    } else if item.id.kind == .camera {
                                        viewport.setFileCamera(item.id)
                                    }
                                    selection.select(selection.selected == item.id ? nil : item.id)
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
                }
                .focusSection()

                fileFooter
            } else {
                SidebarStatusView(state: documentState)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.chrome)
    }

    /// File facts + honesty — pinned under the outliner scroll.
    @ViewBuilder
    private var fileFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FileSection(stats: model.stats, fileName: model.fileName)
                    ValidationSection(validation: model.validation)
                    ConvertProblemsSection(problems: model.convertProblems)
                    if !model.pipelineReport.isEmpty {
                        PipelineSection(report: model.pipelineReport)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
            }
            .frame(maxHeight: 280)
        }
    }

    /// Subtitle under the file name — the active scene, falling back to the file default.
    private var currentSceneName: String? {
        let id = viewport.activeSceneID ?? model.defaultSceneID
        guard let id else { return nil }
        return model.scenes.first { $0.id == id }?.name
    }
}

// MARK: - Previews

private struct LeftSidebarPreviewHost: View {
    enum Mode {
        case ready
        case empty
        case loading
        case failed
    }

    var mode: Mode
    @State private var selection: MockSelectionModel
    @State private var viewport: MockViewportController

    init(mode: Mode) {
        self.mode = mode
        _selection = State(initialValue: MockSelectionModel(selected: nil))
        _viewport = State(initialValue: MockViewportController())
    }

    private var documentState: ShellDocumentState {
        switch mode {
        case .ready: .ready
        case .empty: .empty
        case .loading: .loading
        case .failed: .failed(ShellStatusCopy.invalidFileDetail)
        }
    }

    private var height: CGFloat {
        switch mode {
        case .ready: 520
        case .empty, .loading, .failed: 320
        }
    }

    var body: some View {
        PreviewCanvas(width: Theme.sidebarWidth, height: height) {
            LeftSidebar(
                model: FixtureSceneModel.cube,
                selection: selection,
                viewport: viewport,
                documentState: documentState,
                isSidebarVisible: true,
                onToggleSidebar: {}
            )
        }
    }
}

#Preview("ready", traits: .fixedLayout(width: Theme.sidebarWidth, height: 520)) {
    LeftSidebarPreviewHost(mode: .ready)
}

#Preview("empty", traits: .fixedLayout(width: Theme.sidebarWidth, height: 320)) {
    LeftSidebarPreviewHost(mode: .empty)
}

#Preview("loading", traits: .fixedLayout(width: Theme.sidebarWidth, height: 320)) {
    LeftSidebarPreviewHost(mode: .loading)
}

#Preview("failed", traits: .fixedLayout(width: Theme.sidebarWidth, height: 320)) {
    LeftSidebarPreviewHost(mode: .failed)
}
