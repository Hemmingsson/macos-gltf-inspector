import SwiftUI

/// One shell window: a `MockScene` plus the `ShellRootView` reading it.
///
/// This is the shell's stand-in for a document. `GLBPreview` will hand `ShellRootView` a real
/// `SceneModel` from the same place — the view itself does not change at cutover, which is the
/// whole point of the seam.
struct ShellWindow: View {
    /// Per window, so Slice 6's Debug menu can flip one window's file without touching another.
    @State private var scene: MockScene
    /// Owned here so `.focusedSceneValue` can hand the same instance to the View menu that the
    /// pills drive inside `ShellRootView`.
    @State private var viewport: MockViewport
    /// Sidebar / inspector collapse — shared by chrome toggles and the View menu.
    @State private var panels: ShellPanelChrome
    private let initialSelection: NodeID?
    private let configureViewport: @MainActor (MockViewport) -> Void

    /// `configure` runs against a brand-new `MockScene` *before* SwiftUI is handed it, so this is
    /// object construction and not a state mutation during view update (AGENTS.md pitfall 1).
    /// Only the first call's object is kept; later ones are discarded by `@State`.
    ///
    /// Viewport harness overrides run in `seedSession` *after* defaults are applied, so a
    /// Debug fixture's `viewport:` block is not clobbered by seeding.
    @MainActor
    init(
        select initialSelection: NodeID? = nil,
        sidebarVisible: Bool = true,
        inspectorVisible: Bool = true,
        configure: @MainActor (MockScene) -> Void = { $0.apply(.riggedAnimated) },
        viewport configureViewport: @escaping @MainActor (MockViewport) -> Void = { _ in }
    ) {
        let scene = MockScene()
        configure(scene)
        _scene = State(wrappedValue: scene)
        _viewport = State(wrappedValue: MockViewport())
        _panels = State(wrappedValue: ShellPanelChrome(
            isSidebarVisible: sidebarVisible,
            isInspectorVisible: inspectorVisible
        ))
        self.initialSelection = initialSelection
        self.configureViewport = configureViewport
    }

    var body: some View {
        ShellRootView(
            model: scene.model,
            availability: scene.availability,
            documentState: scene.documentState,
            selection: MockSelection(scene: scene, selected: initialSelection),
            viewport: viewport,
            settings: MockSettings(),
            panels: panels,
            seedSession: seedSession
        ) {
            CanvasPlaceholder()
        }
        // Key-window fixtures for Debug + View menus (`FocusedValues`).
        .focusedSceneValue(\.mockScene, scene)
        .focusedSceneValue(\.mockViewport, viewport)
        .focusedSceneValue(\.shellPanelChrome, panels)
    }

    /// Defaults → session → viewport, then optional harness override, then session mirror.
    @MainActor
    private func seedSession(settings: MockSettings, viewport: MockViewport) {
        settings.seedSessionFromDefaultsIfNeeded()
        viewport.applySession(from: settings, log: false)
        configureViewport(viewport)
        viewport.syncSessionFromViewport()
    }
}
