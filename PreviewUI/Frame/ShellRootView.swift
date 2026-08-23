import SwiftUI

/// The window root: three fixed-relationship columns and nothing else.
///
/// Deliberately **not** a `NavigationSplitView`. The wireframe needs fixed-width panels, a custom
/// inspector, and toolbar pills that float *over* the canvas; `NavigationSplitView` fights all
/// three and imposes its own titlebar behaviour. Sidebar collapse is driven by
/// `ShellPanelChrome`; the inspector opens only when something is selected.
///
/// Generic over the canvas so the host injects `PreviewView` without PreviewUI importing Shared.
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
    /// Sidebar visibility — owned by the window host, shared with the View menu.
    public var panels: ShellPanelChrome
    /// Clip transport for the playback bar. Owned by the window host.
    @State private var playback: Playback
    /// Guards the one-shot defaults → session → viewport seed (AGENTS.md: sync in onAppear).
    @State private var didSeedSession = false
    @State private var sidebarWidth: CGFloat = Theme.sidebarWidth
    @State private var inspectorWidth: CGFloat = Theme.inspectorWidth
    /// Host hook: seed session from defaults. Must not run in `init`.
    private let seedSession: (@MainActor (Settings) -> Void)?
    private let canvas: () -> Canvas
    /// Open in menu content shared with inspector/floating chrome.
    private let openInMenu: AnyView
    /// Host maps `PreviewMorph` → inspector sliders.
    private let morphTargets: [MorphTargetControl]
    private let onSetMorphWeight: (String, Double) -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        model: Model,
        availability: Capabilities,
        documentState: ShellDocumentState = .ready,
        selection: @autoclosure () -> Selection,
        viewport: @autoclosure () -> Viewport,
        settings: @autoclosure () -> Settings,
        playback: @autoclosure () -> Playback,
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
        _selection = State(wrappedValue: selection())
        _viewport = State(wrappedValue: viewport())
        _settings = State(wrappedValue: settings())
        _playback = State(wrappedValue: playback())
        self.panels = panels
        self.morphTargets = morphTargets
        self.onSetMorphWeight = onSetMorphWeight
        self.seedSession = seedSession
        self.openInMenu = openInMenu
        self.canvas = canvas
    }

    public var body: some View {
        HStack(spacing: 0) {
            if panels.isSidebarVisible {
                LeftSidebar(
                    model: model,
                    selection: selection,
                    viewport: viewport,
                    documentState: documentState,
                    isSidebarVisible: panels.isSidebarVisible,
                    onToggleSidebar: { panels.toggleSidebar() }
                )
                .frame(width: sidebarWidth)
                .transition(.opacity)

                ResizeHandle(cursor: .resizeLeftRight) { delta in
                    sidebarWidth = clampSidebarWidth(sidebarWidth + delta)
                }

                hairline
                    .transition(.opacity)
            }

            canvasColumn
                .frame(maxWidth: .infinity)

            if showsInspector {
                hairline
                    .transition(.opacity)

                RightInspector(
                    model: model,
                    selection: selection,
                    documentState: documentState,
                    openInMenu: openInMenu,
                    morphTargets: morphTargets,
                    onSetMorphWeight: onSetMorphWeight
                )
                .frame(width: inspectorWidth)
                .transition(.opacity)

                ResizeHandle(cursor: .resizeLeftRight) { delta in
                    inspectorWidth = clampInspectorWidth(inspectorWidth - delta)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Theme.chrome)
        // Drop the system traffic lights onto the shared chrome centerline so they line up with the
        // pane toggles / pills and the band gets breathing space above it (zero-size helper).
        .background { TrafficLightConfigurator(centerY: Theme.trafficLightCenterY) }
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
        .animation(Animation.previewChrome(reduceMotion), value: showsInspector)
        .onAppear(perform: seedSessionIfNeeded)
    }

    private var showsInspector: Bool {
        documentState.isReady && selection.selected != nil
    }

    /// Canvas plus floating chrome when a side column is collapsed (toggle stays reachable).
    private var canvasColumn: some View {
        CanvasRegion(
            model: model,
            availability: availability,
            viewport: viewport,
            playback: playback,
            documentState: documentState,
            isSidebarVisible: panels.isSidebarVisible,
            isInspectorVisible: showsInspector,
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
            if !showsInspector {
                ActionRow(
                    openInMenu: openInMenu
                )
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

    /// A 1 pt contrast-aware rule. `Divider()` renders noticeably heavier than the wireframe's
    /// `1px solid var(--border)`.
    private var hairline: some View {
        Theme.border(contrast: contrast).frame(width: Theme.hairlineWidth)
    }

    private func clampSidebarWidth(_ value: CGFloat) -> CGFloat {
        min(max(value, 220), 520)
    }

    private func clampInspectorWidth(_ value: CGFloat) -> CGFloat {
        min(max(value, 260), 560)
    }
}

private struct ResizeHandle: View {
    var cursor: NSCursor
    var onChanged: (CGFloat) -> Void
    @State private var startX: CGFloat?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if startX == nil { startX = value.startLocation.x }
                        guard let startX else { return }
                        onChanged(value.location.x - startX)
                    }
                    .onEnded { _ in
                        startX = nil
                    }
            )
            .onHover { hovering in
                if hovering {
                    cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
