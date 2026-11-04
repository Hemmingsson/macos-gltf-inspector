import AppKit
import GLTFCore
import PreviewUI
import RendererWebKit
import SwiftUI

/// Document window: the web page loads and draws the file itself, and the panels come from the
/// file's JSON (`DocumentWindowModel.openSummary`). Scene, variant, file camera and selection go
/// to the page through the `Look`.
struct DocumentWindow: View {
    let documentURL: URL?
    /// The launch window is itself the welcome scene, so it must not dismiss that scene.
    var closesWelcome = true

    @State private var window: DocumentWindowModel
    /// Outlives a canvas remount (`DocumentShell` ids the canvas by load generation) so the page
    /// started on open keeps drawing. Replaced only after it failed, for the next document.
    @State private var webCanvas = WebCanvasController()
    /// Cached Finder poster while the page starts. Nil shows the loading pill only.
    @State private var firstPixelImage: NSImage?

    init(documentURL: URL?, closesWelcome: Bool = true) {
        self.documentURL = documentURL
        self.closesWelcome = closesWelcome
        _window = State(wrappedValue: DocumentWindowModel(documentURL: documentURL))
    }

    var body: some View {
        DocumentShell(window: window, canvasState: canvasState, closesWelcome: closesWelcome) {
            canvas
        }
        .focusedSceneValue(\.documentFileURL, documentURL)
        .onAppear {
            if let documentURL {
                loadDocument(documentURL)
            }
        }
        .onChange(of: documentURL) { _, url in
            window.documentURL = url
            if let url {
                loadDocument(url)
            }
        }
    }

    /// The document the page draws. Nil while the window is empty, or when the open path rejected
    /// the file; the canvas then follows the panels.
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

    /// Mounted by `CanvasRegion` only while `canvasState` is `.ready`, i.e. with a page URL whose
    /// page has not failed; loading and failure are drawn by PreviewUI's status view.
    @ViewBuilder
    private var canvas: some View {
        if let webCanvasURL {
            WebPreviewCanvas(
                url: webCanvasURL,
                look: WebPreviewCanvas.Look(window.engineViewport, sidebar: window.sidebar),
                placeholderImage: firstPixelImage,
                controller: webCanvas
            )
            .canvasReadyMarker(isReady: webCanvas.phase == .ready)
            .onAppear {
                window.engineViewport.commands = .web(webCanvas)
                if webCanvas.phase == .ready { window.noteCanvasReady() }
            }
            .onChange(of: webCanvas.phase) { _, phase in
                if phase == .ready { window.noteCanvasReady() }
            }
        }
    }

    private func loadDocument(_ url: URL) {
        firstPixelImage = firstPixelNSImage(for: url)
        guard case .started(let generation) = window.beginOpen(url) else { return }
        if case .failed = webCanvas.phase {
            webCanvas = WebCanvasController()
        }
        Task {
            await window.openSummary(url, generation: generation)
        }
    }
}
