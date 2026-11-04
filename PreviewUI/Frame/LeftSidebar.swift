import DesignSystem
import SwiftUI

/// Left column — structure. The document card and its facts say which file this is; the outliner
/// says what is in it.
///
/// Generic over both seam types rather than taking existentials: `SceneModel` has `Self`
/// requirements through its default implementations.
struct LeftSidebar<Model: SceneModel, Selection: SelectionModel, Viewport: ViewportController>: View {
    var model: Model
    /// Injected, not owned — the window root owns it, and the inspector reads the same instance.
    var selection: Selection
    var viewport: Viewport
    var documentState: ShellDocumentState = .ready
    /// Visual state of the leading chrome toggle (accent while the column is open).
    var isSidebarVisible: Bool = true
    var onToggleSidebar: () -> Void = {}
    /// The whole model is selected (document inspector open).
    var isDocumentSelected = false
    /// Clicking the document card selects the whole model.
    var onSelectDocument: () -> Void = {}

    var body: some View {
        Group {
            if documentState.isReady {
                OutlinerList(
                    model: model,
                    selection: selection,
                    onActivate: activate
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        documentCard
                        FileSection(stats: model.stats, fileName: model.fileName)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    sidebarChrome
                    documentCard
                    if documentState != .empty {
                        ShellStatusView(state: documentState, placement: .sidebar)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.paneFill, ignoresSafeAreaEdges: .all)
    }

    /// Clears the toolbar band so the file card sits under the system sidebar toggle,
    /// which is the only sidebar button.
    private var sidebarChrome: some View {
        Color.clear
            .frame(height: DS.Metrics.toolbarBandHeight)
            .accessibilityHidden(true)
    }

    private var documentCard: some View {
        DocumentHeader(
            fileName: documentState.isReady ? model.fileName : documentState.panelDocumentTitle,
            subtitle: documentState.isReady ? DocumentIdentity.kind(model.fileName) : nil,
            variantNames: documentState.isReady ? model.materialVariantNames : [],
            selectedVariantIndex: viewport.selectedMaterialVariantIndex,
            onSelectVariant: { viewport.setMaterialVariant($0) },
            isSelected: documentState.isReady && isDocumentSelected,
            onSelect: documentState.isReady ? onSelectDocument : nil
        )
    }

    private func activate(_ item: OutlinerItem) {
        if item.id.kind == .scene {
            viewport.setScene(item.id)
        } else if item.id.kind == .camera {
            viewport.setFileCamera(item.id)
        }
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
