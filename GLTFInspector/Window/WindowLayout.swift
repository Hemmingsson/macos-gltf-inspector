import SwiftUI

/// The window's layout: `NavigationSplitView` (sidebar + canvas detail) with a selection-driven
/// `.inspector`. The canvas is full-bleed under both glass panes. The inspector opens only when
/// something is selected, and closing it clears the selection.
struct WindowLayout<Canvas: View>: View {
    let window: DocumentWindowModel
    /// The canvas region's state, which can be ahead of the panels: the renderer may draw while
    /// the panels' JSON is still being read.
    let canvasState: DocumentState
    @ViewBuilder let canvas: () -> Canvas

    /// Sidebar shown or collapsed; `SidebarCommands()` (⌃⌘S) toggles it through the split view.
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let validation = window.validation
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar(document: window.document, fileName: window.fileName, validation: validation,
                        view: window.view, documentState: window.phase)
                .navigationSplitViewColumnWidth(
                    min: DS.Metrics.sidebarWidthRange.lowerBound,
                    ideal: DS.Metrics.sidebarWidth,
                    max: DS.Metrics.sidebarWidthRange.upperBound
                )
        } detail: {
            CanvasRegion(
                bounds: window.document.bounds,
                view: window.view,
                documentState: canvasState,
                isSidebarVisible: columnVisibility != .detailOnly,
                isInspectorVisible: showsInspector,
                content: canvas
            )
            .overlay(alignment: .topTrailing) {
                if window.phase.isReady, !showsInspector {
                    OpenInButton(documentURL: documentURL)
                        .ignoresSafeArea(.container, edges: .top)
                }
            }
            .inspector(isPresented: inspectorPresented) {
                Inspector(
                    document: window.document,
                    selection: window.view.selection,
                    documentState: window.phase,
                    validation: validation,
                    documentURL: documentURL
                )
                .inspectorColumnWidth(
                    min: DS.Metrics.inspectorWidthRange.lowerBound,
                    ideal: DS.Metrics.inspectorWidth,
                    max: DS.Metrics.inspectorWidthRange.upperBound
                )
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: showsInspector)
    }

    private var documentURL: URL? { window.loadingURL ?? window.documentURL }

    /// The setter (the user closed the inspector) clears the selection. Writes happen only in
    /// the setter, never during a view update (AGENTS.md pitfall 1).
    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { showsInspector },
            set: { isPresented in
                if !isPresented, window.view.selection != nil { window.view.selection = nil }
            }
        )
    }

    private var showsInspector: Bool {
        window.phase.isReady && window.view.selection != nil
    }
}
