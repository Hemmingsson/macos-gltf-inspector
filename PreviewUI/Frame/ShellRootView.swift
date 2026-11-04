import DesignSystem
import SwiftUI

/// The window root: `NavigationSplitView` (sidebar + canvas detail) with a selection-driven
/// `.inspector`. The canvas is full-bleed under both glass panes. Sidebar collapse is driven by
/// `ShellPanelChrome`; the inspector opens only when something is selected, and closing it
/// clears the selection.
///
/// Generic over the canvas so the host injects the web canvas without PreviewUI importing it.
public struct ShellRootView<
    Canvas: View,
    Model: SceneModel,
    Selection: SelectionModel,
    Viewport: ViewportController
>: View {
    /// A snapshot of the loaded file. A value, so a redraw can never see it half-updated.
    public var model: Model
    /// Which debug channels the file supports, passed in rather than derived here: only the host
    /// knows what its data actually carries.
    public var availability: Availability
    /// Empty / loading / failed — host open path.
    public var documentState: ShellDocumentState = .ready
    /// Canvas region state when the canvas loads on its own and can be ahead of the panels (a
    /// canvas that draws while the panels' document is still opening, or failed). Nil follows
    /// `documentState`.
    public var canvasState: ShellDocumentState? = nil
    /// The window's selection. Host-owned: the host rebuilds the adapter in `loadDocument` so this
    /// view must not capture it in `@State` (that would pin the first instance across loads).
    public var selection: Selection
    /// The window's view state — backdrop, floor, view mode, camera. Owned here for the same
    /// reason as DESIGN.md's three-job rule: canvas controls are *per window and live*, and they
    /// never write app defaults.
    @State private var viewport: Viewport
    /// Sidebar visibility — owned by the window host, shared with `SidebarCommands()`.
    public var panels: ShellPanelChrome
    private let canvas: () -> Canvas
    /// Open in menu content shared with inspector/floating chrome.
    private let openInMenu: AnyView

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        model: Model,
        availability: Availability,
        documentState: ShellDocumentState = .ready,
        canvasState: ShellDocumentState? = nil,
        selection: Selection,
        viewport: @autoclosure () -> Viewport,
        panels: ShellPanelChrome,
        openInMenu: AnyView = AnyView(EmptyView()),
        @ViewBuilder canvas: @escaping () -> Canvas
    ) {
        self.model = model
        self.availability = availability
        self.documentState = documentState
        self.canvasState = canvasState
        self.selection = selection
        _viewport = State(wrappedValue: viewport())
        self.panels = panels
        self.openInMenu = openInMenu
        self.canvas = canvas
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            LeftSidebar(
                model: model,
                selection: selection,
                viewport: viewport,
                documentState: documentState,
                isSidebarVisible: panels.isSidebarVisible,
                onToggleSidebar: { panels.toggleSidebar() }
            )
            .navigationSplitViewColumnWidth(
                min: DS.Metrics.sidebarWidthRange.lowerBound,
                ideal: DS.Metrics.sidebarWidth,
                max: DS.Metrics.sidebarWidthRange.upperBound
            )
        } detail: {
            canvasColumn
                .inspector(isPresented: inspectorPresented) {
                    RightInspector(
                        selection: selection,
                        documentState: documentState,
                        openInMenu: openInMenu
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

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { panels.columnVisibility },
            set: { panels.columnVisibility = $0 }
        )
    }

    /// Reads selection; the setter (user closed the inspector) clears it. Writes happen only in
    /// the setter — never during a view update (AGENTS.md pitfall 1).
    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { showsInspector },
            set: { isPresented in
                if !isPresented, selection.selected != nil {
                    selection.select(nil)
                }
            }
        )
    }

    private var showsInspector: Bool {
        documentState.isReady && selection.selected != nil
    }

    /// Canvas plus the floating Open-in action when the inspector is closed.
    private var canvasColumn: some View {
        CanvasRegion(
            model: model,
            availability: availability,
            viewport: viewport,
            documentState: canvasState ?? documentState,
            isSidebarVisible: panels.isSidebarVisible,
            isInspectorVisible: showsInspector,
            onToggleSidebar: { panels.toggleSidebar() },
            content: canvas
        )
        .overlay(alignment: .topTrailing) {
            if !showsInspector {
                ActionRow(openInMenu: openInMenu)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
    }
}

// MARK: - Previews

@MainActor
private struct ShellRootViewPreviewHost: View {
    enum Mode {
        case fullChrome
        case sidebarCollapsed
    }

    @State private var selection: MockSelectionModel
    @State private var viewport: MockViewportController
    @State private var panels: ShellPanelChrome

    init(mode: Mode) {
        _selection = State(initialValue: MockSelectionModel())
        _viewport = State(initialValue: MockViewportController())
        _panels = State(
            initialValue: ShellPanelChrome(isSidebarVisible: mode == .fullChrome)
        )
    }

    var body: some View {
        ShellRootView(
            model: FixtureSceneModel.cube,
            availability: Availability.preview,
            selection: selection,
            viewport: viewport,
            panels: panels,
            openInMenu: AnyView(PreviewOpenInItems())
        ) {
            PreviewCanvasPlaceholder()
        }
    }
}

#Preview("full chrome", traits: .fixedLayout(width: 1_188, height: 640)) {
    ShellRootViewPreviewHost(mode: .fullChrome)
}

#Preview("sidebar collapsed", traits: .fixedLayout(width: 940, height: 640)) {
    ShellRootViewPreviewHost(mode: .sidebarCollapsed)
}
