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
    @State private var playback: MockPlayback
    /// Sidebar / inspector collapse — shared by chrome toggles and the View menu.
    @State private var panels: ShellPanelChrome
    private let initialSelection: NodeID?
    private let configureViewport: @MainActor (MockViewport) -> Void

    /// `configure` runs against a brand-new `MockScene` *before* SwiftUI is handed it, so this is
    /// object construction and not a state mutation during view update (AGENTS.md pitfall 1).
    /// Only the first call's object is kept; later ones are discarded by `@State`.
    ///
    /// Viewport harness overrides run in `seedSession` after the viewport reads live defaults.
    /// Do **not** copy every default into the session (that pins the window and kills P34).
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
        _playback = State(wrappedValue: MockPlayback(clips: scene.model.animations))
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
            playback: playback,
            panels: panels,
            seedSession: seedSession,
            onScreenshot: { viewport.screenshot() }
        ) {
            CanvasPlaceholder()
        }
        .onAppear {
            if viewport.activeSceneID == nil, let id = scene.model.defaultSceneID {
                viewport.setScene(id)
            }
            playback.replaceClips(scene.model.animations)
        }
        .onChange(of: scene.model.animations.map(\.id)) { _, _ in
            playback.replaceClips(scene.model.animations)
        }
        // Key-window fixtures for Debug + View menus (`FocusedValues`).
        .focusedSceneValue(\.mockScene, scene)
        .focusedSceneValue(\.mockViewport, viewport)
        .focusedSceneValue(\.shellPanelChrome, panels)
    }

    /// Read live defaults into the viewport, then apply optional harness overrides.
    /// Harness mutators (`setFloor`, …) write only the keys they touch.
    @MainActor
    private func seedSession(settings: MockSettings, viewport: MockViewport) {
        viewport.applySession(from: settings, log: false)
        configureViewport(viewport)
    }
}
