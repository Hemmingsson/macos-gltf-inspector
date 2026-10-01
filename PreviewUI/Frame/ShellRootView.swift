import DesignSystem
import SwiftUI

/// The window root: `NavigationSplitView` (sidebar + canvas detail) with a selection-driven
/// `.inspector`. The canvas is full-bleed under both glass panes. Sidebar collapse is driven by
/// `ShellPanelChrome`; the inspector opens only when something is selected, and closing it
/// clears the selection.
///
/// Generic over the canvas so the host injects the renderer canvas without PreviewUI importing a renderer.
public struct ShellRootView<
    Canvas: View,
    Model: SceneModel,
    Capabilities: Availability,
    Selection: SelectionModel,
    Viewport: ViewportController,
    Settings: SettingsStore,
    Playback: ClipPlaybackController
>: View {
    /// A snapshot of the loaded file. A value, so a redraw can never see it half-updated.
    public var model: Model
    /// What the file can do, passed in rather than derived here: only the host knows which debug
    /// channels its data actually supports.
    public var availability: Capabilities
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
    /// Defaults + this window's session overrides. Seeded in `.onAppear`, never in `init`.
    @State private var settings: Settings
    /// Sidebar visibility — owned by the window host, shared with `SidebarCommands()`.
    public var panels: ShellPanelChrome
    /// Clip transport for the playback bar. Host-owned and rebuilt per load — not `@State` here.
    public var playback: Playback
    /// Guards the one-shot defaults → session → viewport seed (AGENTS.md: sync in onAppear).
    @State private var didSeedSession = false
    /// Host hook: seed session from defaults. Must not run in `init`.
    private let seedSession: (@MainActor (Settings) -> Void)?
    private let canvas: () -> Canvas
    /// Open in menu content shared with inspector/floating chrome.
    private let openInMenu: AnyView
    /// Host maps `PreviewMorph` → inspector sliders.
    private let morphTargets: [MorphTargetControl]
    private let onSetMorphWeight: (String, Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        model: Model,
        availability: Capabilities,
        documentState: ShellDocumentState = .ready,
        canvasState: ShellDocumentState? = nil,
        selection: Selection,
        viewport: @autoclosure () -> Viewport,
        settings: @autoclosure () -> Settings,
        playback: Playback,
        panels: ShellPanelChrome,
        morphTargets: [MorphTargetControl] = [],
        onSetMorphWeight: @escaping (String, Double) -> Void = { _, _ in },
        seedSession: (@MainActor (Settings) -> Void)? = nil,
        openInMenu: AnyView = AnyView(EmptyView()),
        @ViewBuilder canvas: @escaping () -> Canvas
    ) {
        self.model = model
        self.availability = availability
        self.documentState = documentState
        self.canvasState = canvasState
        self.selection = selection
        _viewport = State(wrappedValue: viewport())
        _settings = State(wrappedValue: settings())
        self.playback = playback
        self.panels = panels
        self.morphTargets = morphTargets
        self.onSetMorphWeight = onSetMorphWeight
        self.seedSession = seedSession
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
            .navigationSplitViewColumnWidth(min: 220, ideal: DS.Metrics.sidebarWidth, max: 520)
        } detail: {
            canvasColumn
                .inspector(isPresented: inspectorPresented) {
                    RightInspector(
                        model: model,
                        selection: selection,
                        documentState: documentState,
                        openInMenu: openInMenu,
                        morphTargets: morphTargets,
                        onSetMorphWeight: onSetMorphWeight
                    )
                    .inspectorColumnWidth(min: 260, ideal: DS.Metrics.inspectorWidth, max: 560)
                }
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: showsInspector)
        .onAppear(perform: seedSessionIfNeeded)
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
            playback: playback,
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

    /// Never called from `init` — mutating `@Observable` / `@State` there re-enters SwiftUI
    /// (AGENTS.md pitfall 1).
    private func seedSessionIfNeeded() {
        guard !didSeedSession else { return }
        didSeedSession = true
        seedSession?(settings)
    }
}

// MARK: - Previews

/// Stand-in for the host-injected `RealityView` — flat gray viewport only.
private struct ShellCanvasPlaceholder: View {
    var body: some View {
        DS.Color.Canvas.gradient
    }
}

private struct PreviewOpenInItems: View {
    var body: some View {
        Button("Finder") {}
        Button("Blender") {}
    }
}

@MainActor
private struct ShellRootViewPreviewHost: View {
    enum Mode {
        case fullChrome
        case sidebarCollapsed
    }

    var mode: Mode
    @State private var selection: MockSelectionModel
    @State private var viewport: MockViewportController
    @State private var settings: MockSettingsStore
    @State private var playback: MockPlaybackController
    @State private var panels: ShellPanelChrome

    init(mode: Mode) {
        self.mode = mode
        _selection = State(initialValue: MockSelectionModel())
        _viewport = State(initialValue: MockViewportController())
        _settings = State(initialValue: MockSettingsStore())
        _playback = State(initialValue: MockPlaybackController())
        _panels = State(
            initialValue: ShellPanelChrome(isSidebarVisible: mode == .fullChrome)
        )
    }

    var body: some View {
        ShellRootView(
            model: FixtureSceneModel.cube,
            availability: MockAvailability(),
            selection: selection,
            viewport: viewport,
            settings: settings,
            playback: playback,
            panels: panels,
            openInMenu: AnyView(PreviewOpenInItems())
        ) {
            ShellCanvasPlaceholder()
        }
    }
}

#Preview("full chrome", traits: .fixedLayout(width: 1_188, height: 640)) {
    ShellRootViewPreviewHost(mode: .fullChrome)
}

#Preview("sidebar collapsed", traits: .fixedLayout(width: 940, height: 640)) {
    ShellRootViewPreviewHost(mode: .sidebarCollapsed)
}
