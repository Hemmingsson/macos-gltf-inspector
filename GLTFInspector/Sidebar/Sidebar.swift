import GLTFCore
import SwiftUI

/// Left column — structure. The document says which file this is; the outliner says what is in it.
struct Sidebar: View {
    var document: GLTFDocument
    var fileName: String
    var validation: ValidationResult
    @Bindable var view: ViewState
    var documentState: DocumentState
    /// Measured height of the validation footer's content; the footer shows up to 280 pt of it.
    @State private var validationHeight: CGFloat = 0

    var body: some View {
        Group {
            if documentState.isReady {
                OutlinerList(
                    document: document,
                    validation: validation,
                    selection: $view.selection,
                    selectedIDs: $view.selectedIDs,
                    onActivate: activate,
                    hiddenNodes: view.hiddenNodes,
                    soloNodes: view.soloNodes,
                    onToggleHidden: { view.toggleHidden($0) },
                    onToggleSolo: { view.toggleSolo($0) },
                    onShowAll: { view.showAll() },
                    onFrame: { index in
                        if let id = document.id(ofNode: index), !view.selectedIDs.contains(id) { view.selection = id }
                        view.frameSelection()
                    },
                    pointedNode: view.canvas.hoveredNode,
                    showsTreeGuides: view.settings.showsTreeGuides
                )
                .documentReadyMarker()
                .safeAreaInset(edge: .top, spacing: 0) {
                    documentCard
                }
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    validationFooter
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    sidebarChrome
                    documentCard
                    if documentState != .empty {
                        DocumentStatusView(state: documentState, placement: .sidebar)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Color.paneFill, ignoresSafeAreaEdges: .all)
    }

    /// Clears the toolbar band so the file card sits under the traffic lights.
    private var sidebarChrome: some View {
        Color.clear
            .frame(height: DS.Metrics.toolbarBandHeight)
            .accessibilityHidden(true)
    }

    private var documentCard: some View {
        DocumentHeader(
            fileName: documentState.isReady ? fileName : documentState.panelDocumentTitle,
            variantNames: documentState.isReady ? document.materialVariantNames : [],
            selectedVariantIndex: $view.materialVariantIndex
        )
    }

    /// glTF-validator result, pinned under the outliner. A long issue list scrolls inside a capped
    /// footer rather than pushing the outliner off screen.
    private var validationFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            ScrollView {
                ValidationSection(validation: validation)
                    .padding(.bottom, DS.Spacing.s)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { validationHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(validationHeight, 280))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func activate(_ item: OutlinerItem) {
        switch item.id.kind {
        case .scene: view.sceneIndex = item.id.index
        case .camera: view.fileCameraNodeIndex = item.id.index
        default: break
        }
    }
}
