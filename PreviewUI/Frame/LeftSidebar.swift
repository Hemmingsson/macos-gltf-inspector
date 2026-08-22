import SwiftUI

/// Left column — structure. The document says which file this is; the outliner says what is in it.
///
/// Generic over both seam types rather than taking existentials: `SceneModel` has `Self`
/// requirements through its default implementations, and the point of the seam is that the shell's
/// fixtures and the app's engine adapter are interchangeable *at compile time*.
struct LeftSidebar<Model: SceneModel, Selection: SelectionModel>: View {
    var model: Model
    /// Injected, not owned — the window root owns it, and the inspector reads the same instance.
    var selection: Selection
    var documentState: ShellDocumentState = .ready
    /// Visual state of the leading chrome toggle (accent while the column is open).
    var isSidebarVisible: Bool
    var onToggleSidebar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarChromeRow(
                isSidebarVisible: isSidebarVisible,
                onToggleSidebar: onToggleSidebar
            )

            DocumentHeader(
                fileName: documentState.isReady ? model.fileName : documentState.panelDocumentTitle,
                sceneName: documentState.isReady ? currentSceneName : nil
            )

            if documentState.isReady {
                // Scrolls independently of the document header, which stays put: on a file with forty
                // meshes the one line that says *which file* must not scroll away.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(OutlinerSection.sections(of: model)) { section in
                            OutlinerSectionView(section: section, selection: selection)
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

    /// Subtitle under the file name. The default scene, since that is what the canvas is showing.
    private var currentSceneName: String? {
        guard let id = model.defaultSceneID else { return nil }
        return model.scenes.first { $0.id == id }?.name
    }
}

/// Traffic-light clearance + `sidebar.leading` toggle on the unified chrome band.
struct SidebarChromeRow: View {
    var isSidebarVisible: Bool
    var onToggleSidebar: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: Theme.trafficLightLeadingClearance, height: ChromeMetrics.buttonSize)

            ChromeIconButton(
                symbol: "sidebar.leading",
                title: isSidebarVisible ? "Hide Sidebar" : "Show Sidebar",
                prominent: isSidebarVisible,
                action: onToggleSidebar
            )

            Spacer(minLength: 0)
        }
        .frame(height: ChromeMetrics.buttonSize, alignment: .leading)
        .padding(.trailing, 10)
        .chromeBandAligned()
        .accessibilityElement(children: .contain)
    }
}
