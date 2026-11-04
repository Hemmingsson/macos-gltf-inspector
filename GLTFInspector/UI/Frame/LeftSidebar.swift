import SwiftUI

/// Left column — structure. The document says which file this is; the outliner says what is in it.
struct LeftSidebar: View {
    var model: EngineSceneModel
    @Bindable var view: ViewState
    var documentState: ShellDocumentState
    /// Measured height of the validation footer's content; the footer shows up to 280 pt of it.
    @State private var validationHeight: CGFloat = 0

    var body: some View {
        Group {
            if documentState.isReady {
                OutlinerList(model: model, selection: $view.selection, onActivate: activate)
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
            variantNames: documentState.isReady ? model.materialVariantNames : [],
            selectedVariantIndex: $view.materialVariantIndex
        )
    }

    /// glTF-validator result, pinned under the outliner. A long issue list scrolls inside a capped
    /// footer rather than pushing the outliner off screen.
    private var validationFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            ScrollView {
                ValidationSection(validation: model.validation)
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
