import AppKit
import GLTFCore
import Renderer
import SwiftUI

/// Document window root. The renderer loads and draws the file itself while the panels read its
/// JSON (`DocumentWindowModel.openSummary`); both start on open.
struct DocumentWindow: View {
    let documentURL: URL?
    /// The launch window is itself the welcome scene, so it must not dismiss that scene.
    var closesWelcome = true

    @State private var window: DocumentWindowModel
    @Environment(\.dismissWindow) private var dismissWindow

    init(documentURL: URL?, closesWelcome: Bool = true) {
        self.documentURL = documentURL
        self.closesWelcome = closesWelcome
        _window = State(wrappedValue: DocumentWindowModel(documentURL: documentURL))
    }

    var body: some View {
        ShellRootView(window: window, canvasState: canvasState) {
            canvas
                // A new document remounts the canvas only; the split view keeps its identity.
                .id(window.loadGeneration)
        }
        .focusedSceneValue(\.documentWindow, window.phase.isReady || window.view.canvas.phase == .ready ? window : nil)
        .focusedSceneValue(\.documentFileURL, documentURL)
        .onAppear {
            if closesWelcome { dismissWindow(id: WelcomeWindow.id) }
            if let documentURL { loadDocument(documentURL) }
        }
        .onChange(of: documentURL) { _, url in
            window.documentURL = url
            if let url { loadDocument(url) }
        }
    }

    /// The file the canvas draws. Nil while the window is empty or the open path rejected the
    /// file; the canvas region then follows the panels.
    private var canvasURL: URL? {
        guard let url = window.loadingURL ?? documentURL, DocumentOpening.isGLTFFile(url) else { return nil }
        return url
    }

    private var canvasState: ShellDocumentState {
        Self.canvasState(canvasURL: canvasURL, canvasPhase: window.view.canvas.phase, panels: window.phase)
    }

    /// Only the renderer's own failure fails the canvas region: the panels may still be loading,
    /// or have failed, while the model draws. Without a file the canvas follows the panels.
    static func canvasState(
        canvasURL: URL?,
        canvasPhase: ModelCanvasController.Phase,
        panels: ShellDocumentState
    ) -> ShellDocumentState {
        guard canvasURL != nil else { return panels }
        if case .failed(let message) = canvasPhase { return .failed(message) }
        return .ready
    }

    /// Mounted by `CanvasRegion` only while `canvasState` is `.ready`; loading and failure are
    /// drawn by `ShellStatusView`.
    @ViewBuilder
    private var canvas: some View {
        if let canvasURL {
            ModelCanvas(url: canvasURL, options: window.view.options, controller: window.view.canvas)
                .canvasReadyMarker(isReady: window.view.canvas.phase == .ready)
                .onChange(of: window.view.canvas.phase, initial: true) { _, phase in
                    if phase == .ready { window.noteCanvasReady() }
                }
        }
    }

    private func loadDocument(_ url: URL) {
        guard case .started(let generation) = window.beginOpen(url) else { return }
        Task { await window.openSummary(url, generation: generation) }
    }
}

extension FocusedValues {
    /// The key document window, for the View and File menus. Nil until it has a document.
    @Entry var documentWindow: DocumentWindowModel?
    /// The focused document window's file, for Share. Nil in an empty window.
    @Entry var documentFileURL: URL?
}
