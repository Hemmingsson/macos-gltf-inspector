import SwiftUI

/// Left column — structure. The document says which file this is; the outliner says what is in it.
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
    var isSidebarVisible: Bool
    var onToggleSidebar: () -> Void

    var body: some View {
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
                // Scrolls independently of the document header, which stays put: on a file with forty
                // meshes the one line that says *which file* must not scroll away.
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
            } else {
                SidebarStatusView(state: documentState)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.chrome)
    }

    /// Subtitle under the file name — the active scene, falling back to the file default.
    private var currentSceneName: String? {
        let id = viewport.activeSceneID ?? model.defaultSceneID
        guard let id else { return nil }
        return model.scenes.first { $0.id == id }?.name
    }
}

/// `sidebar.leading` toggle on the unified chrome band.
///
/// Two placements: **in-sidebar** (`trailingAligned`) sits at the pane's inner (right) edge, by the
/// canvas divider — the traffic lights own the pane's outer/left side; **floating restore** (sidebar
/// collapsed, over the canvas) sits at the leading edge, clearing the three system lights.
struct SidebarChromeRow: View {
    var isSidebarVisible: Bool
    var trailingAligned: Bool = false
    var onToggleSidebar: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if trailingAligned {
                Spacer(minLength: 0)
                toggle
            } else {
                Color.clear
                    .frame(width: Theme.trafficLightLeadingClearance, height: ChromeMetrics.buttonSize)
                toggle
                Spacer(minLength: 0)
            }
        }
        .frame(height: ChromeMetrics.buttonSize, alignment: trailingAligned ? .trailing : .leading)
        .padding(.trailing, trailingAligned ? 12 : 10)
        .chromeBandAligned()
        .accessibilityElement(children: .contain)
    }

    private var toggle: some View {
        ChromeIconButton(
            symbol: "sidebar.leading",
            title: isSidebarVisible ? "Hide Sidebar" : "Show Sidebar",
            prominent: isSidebarVisible,
            action: onToggleSidebar
        )
    }
}
