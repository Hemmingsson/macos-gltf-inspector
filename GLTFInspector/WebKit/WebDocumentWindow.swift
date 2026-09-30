import GLTFCore
import PreviewUI
import RendererWebKit
import SwiftUI

/// Document window on the WebKit renderer: the page loads and draws the file itself, and the
/// panels come from the file's JSON (`DocumentWindowModel.openSummary`). No RealityKit convert
/// runs, so RealityKit-only chrome (clips, morph sliders, hide/solo, convert report) is absent
/// (`WebPreviewCanvas.features`). Scene and variant switches go to the page through the `Look`.
struct WebDocumentWindow: View {
    let documentURL: URL?

    @Environment(\.colorScheme) private var colorScheme

    @State private var window: DocumentWindowModel
    /// Outlives the shell's `.id` remount so the page started on open keeps drawing when the
    /// panels land. Replaced only after it failed, for the next document.
    @State private var webCanvas = WebCanvasController()

    init(documentURL: URL?) {
        self.documentURL = documentURL
        _window = State(wrappedValue: DocumentWindowModel(documentURL: documentURL))
    }

    var body: some View {
        DocumentShell(
            window: window,
            canvasState: canvasState,
            features: WebPreviewCanvas.features,
            playback: NoClipPlayback()
        ) {
            canvas
        }
        .onAppear {
            if let documentURL {
                loadDocument(documentURL)
            } else {
                window.failMissingURL()
            }
        }
        .onChange(of: documentURL) { _, url in
            window.documentURL = url
            if let url {
                loadDocument(url)
            }
        }
    }

    /// The document the page draws; nil for a rejected file or a missing URL, whose failure then
    /// comes from the open path.
    private var webCanvasURL: URL? {
        guard let url = window.loadingURL ?? documentURL, DocumentOpening.isGLTFFile(url) else { return nil }
        return url
    }

    private var canvasState: ShellDocumentState {
        Self.canvasState(webCanvasURL: webCanvasURL, webPhase: webCanvas.phase, panels: window.phase)
    }

    /// Only the page's own failure fails the canvas region; the panels may still be loading, or
    /// have failed, while the page draws. Without a page (rejected file, missing URL) the canvas
    /// follows the panels.
    static func canvasState(
        webCanvasURL: URL?,
        webPhase: WebCanvasController.Phase,
        panels: ShellDocumentState
    ) -> ShellDocumentState {
        guard webCanvasURL != nil else { return panels }
        if case .failed(let message) = webPhase { return .failed(message) }
        return .ready
    }

    @ViewBuilder
    private var canvas: some View {
        let register = { window.engineViewport.commands = $0 }
        if let webCanvasURL {
            if case .failed(let message) = webCanvas.phase {
                CanvasStatusView(status: .failed(message), isDark: colorScheme == .dark)
                    .onAppear { register(nil) }
            } else {
                WebPreviewCanvas(
                    url: webCanvasURL,
                    look: WebPreviewCanvas.Look(
                        window.engineViewport,
                        sceneIndex: window.sidebar?.activeSceneIndex ?? 0,
                        selectedNodeIndex: window.sidebar?.selectedNodeIndex
                    ),
                    controller: webCanvas
                )
                .onAppear { register(.web(webCanvas)) }
            }
        } else if case .failed(let message) = window.phase {
            CanvasStatusView(status: .failed(message), isDark: colorScheme == .dark)
                .onAppear { register(nil) }
        } else {
            CanvasStatusView(status: .loading, isDark: colorScheme == .dark)
                .onAppear { register(nil) }
        }
    }

    private func loadDocument(_ url: URL) {
        guard case .started(let generation) = window.beginOpen(url) else { return }
        if case .failed = webCanvas.phase {
            webCanvas = WebCanvasController()
        }
        Task {
            await window.openSummary(url, generation: generation, renderer: .webKit)
        }
    }
}
