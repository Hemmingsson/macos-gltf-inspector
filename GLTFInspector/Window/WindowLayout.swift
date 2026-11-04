import AppKit
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
    /// Full screen shows the toolbar only on hover, so the sidebar keeps its band clear itself.
    @State private var isFullScreen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let validation = window.validation
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar(document: window.document, fileName: window.fileName, validation: validation,
                        view: window.view, documentState: window.phase)
                // The hover toolbar adds no safe area: keep its band clear for the traffic
                // lights and sidebar toggle, so the card sits where it does in a window.
                .safeAreaPadding(.top, isFullScreen ? DS.Metrics.toolbarBandHeight : 0)
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
        // Full screen: the toolbar (traffic lights, sidebar toggle) slides in with the menu bar,
        // at the same place as in a window; the canvas clusters stay put underneath.
        .windowToolbarFullScreenVisibility(.onHover)
        .background(FullScreenObserver { isFullScreen = $0 })
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

/// Reports full screen as the window enters or leaves it, and clears the full-screen toolbar's
/// background. Called from AppKit notifications, never during a view update.
private struct FullScreenObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView(onChange: onChange) }
    func updateNSView(_ view: ObserverView, context: Context) { view.onChange = onChange }

    final class ObserverView: NSView {
        var onChange: (Bool) -> Void
        private var tokens: [NSObjectProtocol] = []

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            guard let window else { return }
            let center = NotificationCenter.default
            tokens = [
                center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onChange(true) }
                },
                center.addObserver(forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onChange(false) }
                },
                center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { _ in
                    MainActor.assumeIsolated { Self.clearFullScreenTitleBars() }
                },
            ]
            // Only a window that is already full screen needs reporting: false is the default,
            // and a late `false` would undo a full-screen entry that started meanwhile.
            if window.styleMask.contains(.fullScreen) {
                DispatchQueue.main.async { [weak self] in self?.onChange(true) }
            }
        }

        /// In full screen the toolbar slides in from a separate `NSToolbarFullScreenWindow` whose
        /// background views paint an opaque strip over the canvas clusters. Hiding them leaves
        /// its traffic lights and sidebar toggle over the canvas, as in a window.
        private static func clearFullScreenTitleBars() {
            for window in NSApp.windows where String(describing: type(of: window)) == "NSToolbarFullScreenWindow" {
                guard let root = window.contentView else { continue }
                hideTitlebarBackgrounds(in: root)
            }
        }

        private static func hideTitlebarBackgrounds(in view: NSView) {
            if String(describing: type(of: view)) == "NSTitlebarBackgroundView" {
                view.isHidden = true
                return
            }
            view.subviews.forEach(hideTitlebarBackgrounds)
        }
    }
}
