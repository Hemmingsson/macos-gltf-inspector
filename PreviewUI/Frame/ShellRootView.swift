import SwiftUI

/// The window root: three fixed-relationship columns and nothing else.
///
/// Deliberately **not** a `NavigationSplitView`. The wireframe needs fixed-width panels, a custom
/// inspector, and toolbar pills that float *over* the canvas; `NavigationSplitView` fights all
/// three and imposes its own titlebar behaviour. Sidebar / inspector collapse is driven by
/// `ShellPanelChrome` (chrome toggles + View-menu twins).
///
/// Generic over the canvas so the shell can inject the gradient placeholder while `GLBPreview`
/// later injects a `RealityView` — the same view code, no `AnyView`, no engine import.
struct ShellRootView<
    Canvas: View,
    Model: SceneModel,
    Capabilities: Availability,
    Selection: SelectionModel,
    Viewport: ViewportController,
    Settings: SettingsStore
>: View {
    /// A snapshot of the loaded file. A value, so a redraw can never see it half-updated.
    var model: Model
    /// What the file can do, passed in rather than derived here: only the host knows which debug
    /// channels its data actually supports.
    var availability: Capabilities
    /// Empty / loading / failed — shell Debug fixtures today; host open path at cutover.
    var documentState: ShellDocumentState = .ready
    /// The window's selection, owned here.
    ///
    /// `@State` because ownership is per *window*: two windows onto two files must not share a
    /// selected node, and putting this on `App` would give them exactly that. The initial value is
    /// assigned through `_selection` in `init` — never mutated there (AGENTS.md pitfall 1).
    @State private var selection: Selection
    /// The window's view state — backdrop, floor, view mode, camera. Owned here for the same
    /// reason as `selection`, and DESIGN.md's three-job rule makes it explicit: canvas controls
    /// are *per window and live*, and they never write app defaults.
    @State private var viewport: Viewport
    /// Defaults + this window's session overrides. Seeded in `.onAppear`, never in `init`.
    @State private var settings: Settings
    /// Sidebar / inspector visibility — owned by the window host, shared with the View menu.
    var panels: ShellPanelChrome
    /// Guards the one-shot defaults → session → viewport seed (AGENTS.md: sync in onAppear).
    @State private var didSeedSession = false
    /// Host/shell hook: seed session from defaults and optionally apply Debug viewport overrides.
    /// Must not run in `init` — see `seedSessionIfNeeded`.
    private let seedSession: (@MainActor (Settings, Viewport) -> Void)?
    private let canvas: () -> Canvas
    /// Host binds screenshot / Open in… later; shell keeps a shared no-op so collapse overlays
    /// and the inspector header stay in sync without duplicated stub closures.
    private let onScreenshot: () -> Void
    private let onOpenIn: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        model: Model,
        availability: Capabilities,
        documentState: ShellDocumentState = .ready,
        selection: @autoclosure () -> Selection,
        viewport: @autoclosure () -> Viewport,
        settings: @autoclosure () -> Settings,
        panels: ShellPanelChrome,
        seedSession: (@MainActor (Settings, Viewport) -> Void)? = nil,
        onScreenshot: @escaping () -> Void = {},
        onOpenIn: @escaping () -> Void = {},
        @ViewBuilder canvas: @escaping () -> Canvas
    ) {
        self.model = model
        self.availability = availability
        self.documentState = documentState
        _selection = State(wrappedValue: selection())
        _viewport = State(wrappedValue: viewport())
        _settings = State(wrappedValue: settings())
        self.panels = panels
        self.seedSession = seedSession
        self.onScreenshot = onScreenshot
        self.onOpenIn = onOpenIn
        self.canvas = canvas
    }

    var body: some View {
        HStack(spacing: 0) {
            if panels.isSidebarVisible {
                LeftSidebar(
                    model: model,
                    selection: selection,
                    documentState: documentState,
                    isSidebarVisible: panels.isSidebarVisible,
                    onToggleSidebar: { panels.toggleSidebar() }
                )
                .frame(width: Theme.sidebarWidth)
                .transition(.opacity)

                hairline
                    .transition(.opacity)
            }

            canvasColumn
                .frame(maxWidth: .infinity)

            if panels.isInspectorVisible {
                hairline
                    .transition(.opacity)

                RightInspector(
                    model: model,
                    selection: selection,
                    documentState: documentState,
                    isInspectorVisible: panels.isInspectorVisible,
                    onScreenshot: onScreenshot,
                    onOpenIn: onOpenIn,
                    onToggleInspector: { panels.toggleInspector() }
                )
                .frame(width: Theme.inspectorWidth)
                .transition(.opacity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Theme.chrome)
        // A `.hiddenTitleBar` window still hands its content a ~32 pt top safe area, which would
        // push all three columns down: the canvas and the inspector would wear a band of
        // `Theme.chrome` across the top instead of running under the traffic lights, and the
        // sidebar's chrome band would stack on top of it. Opt out and let each column own the
        // unified `topChromeHeight` band.
        .ignoresSafeArea(.container, edges: .top)
        // Keeps the traffic lights but drops the title string, which would otherwise sit over
        // the sidebar content in a `.hiddenTitleBar` window.
        .toolbar(removing: .title)
        .themeContrastEnvironment()
        .animation(Animation.previewChrome(reduceMotion), value: panels.isSidebarVisible)
        .animation(Animation.previewChrome(reduceMotion), value: panels.isInspectorVisible)
        .onAppear(perform: seedSessionIfNeeded)
    }

    /// Canvas plus floating chrome when a side column is collapsed (toggle stays reachable).
    private var canvasColumn: some View {
        CanvasRegion(
            model: model,
            availability: availability,
            viewport: viewport,
            documentState: documentState,
            isSidebarVisible: panels.isSidebarVisible,
            isInspectorVisible: panels.isInspectorVisible,
            content: canvas
        )
        .overlay(alignment: .topLeading) {
            if !panels.isSidebarVisible {
                SidebarChromeRow(
                    isSidebarVisible: false,
                    onToggleSidebar: { panels.toggleSidebar() }
                )
            }
        }
        .overlay(alignment: .topTrailing) {
            if !panels.isInspectorVisible {
                ActionRow(
                    isInspectorVisible: false,
                    onScreenshot: onScreenshot,
                    onOpenIn: onOpenIn,
                    onToggleInspector: { panels.toggleInspector() }
                )
            }
        }
    }

    /// Never called from `init` — mutating `@Observable` / `@State` there re-enters SwiftUI
    /// (AGENTS.md pitfall 1).
    private func seedSessionIfNeeded() {
        guard !didSeedSession else { return }
        didSeedSession = true
        seedSession?(settings, viewport)
    }

    /// A 1 pt contrast-aware rule. `Divider()` renders noticeably heavier than the wireframe's
    /// `1px solid var(--border)`.
    private var hairline: some View {
        Theme.border(contrast: contrast).frame(width: Theme.hairlineWidth)
    }
}
