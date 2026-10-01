import DesignSystem
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
    public var isSidebarVisible: Bool = true
    public var onToggleSidebar: () -> Void = {}

    public var body: some View {
        Group {
            if documentState.isReady {
                OutlinerList(
                    model: model,
                    selection: selection,
                    onActivate: activate
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        sidebarChrome
                        documentCard
                    }
                }
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    ViewThatFits(in: .vertical) {
                        fileFooter(showsFile: true, showsPipeline: true)
                        fileFooter(showsFile: true, showsPipeline: false)
                        fileFooter(showsFile: false, showsPipeline: false)
                    }
                    .frame(maxHeight: 280, alignment: .top)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    sidebarChrome
                    documentCard
                    SidebarStatusView(state: documentState)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebarChrome: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            DSGlassIconButton(
                isSidebarVisible ? "Hide Sidebar" : "Show Sidebar",
                systemImage: "sidebar.leading",
                isEngaged: isSidebarVisible,
                action: onToggleSidebar
            )
            .dsGlassPlacement(.inIsland)
        }
        .padding(.trailing, DS.Spacing.l)
        .dsChromeBandAligned()
        .accessibilityElement(children: .contain)
    }

    private var documentCard: some View {
        DocumentHeader(
            fileName: documentState.isReady ? model.fileName : documentState.panelDocumentTitle,
            sceneName: documentState.isReady ? currentSceneName : nil,
            variantNames: documentState.isReady ? model.materialVariantNames : [],
            selectedVariantIndex: viewport.selectedMaterialVariantIndex,
            onSelectVariant: { viewport.setMaterialVariant($0) }
        )
    }

    /// File facts + honesty — pinned under the outliner. `ViewThatFits` drops pipeline, then
    /// file stats, rather than nesting a `ScrollView`.
    @ViewBuilder
    private func fileFooter(showsFile: Bool, showsPipeline: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            if showsFile {
                FileSection(stats: model.stats, fileName: model.fileName)
            }
            ValidationSection(validation: model.validation)
            ConvertProblemsSection(problems: model.convertProblems)
            if showsPipeline, !model.pipelineReport.isEmpty {
                PipelineSection(report: model.pipelineReport)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func activate(_ item: OutlinerItem) {
        if item.id.kind == .scene {
            viewport.setScene(item.id)
        } else if item.id.kind == .camera {
            viewport.setFileCamera(item.id)
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
        PreviewCanvas(width: DS.Metrics.sidebarWidth, height: height) {
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

#Preview("ready", traits: .fixedLayout(width: 248, height: 520)) {
    LeftSidebarPreviewHost(mode: .ready)
}

#Preview("empty", traits: .fixedLayout(width: 248, height: 320)) {
    LeftSidebarPreviewHost(mode: .empty)
}

#Preview("loading", traits: .fixedLayout(width: 248, height: 320)) {
    LeftSidebarPreviewHost(mode: .loading)
}

#Preview("failed", traits: .fixedLayout(width: 248, height: 320)) {
    LeftSidebarPreviewHost(mode: .failed)
}
