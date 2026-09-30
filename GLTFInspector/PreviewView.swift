import GLTFCore
import PreviewUI
import RendererRealityKit
import RendererWebKit
import SwiftUI

/// Document-window canvas router: the web canvas when `webCanvasURL` is set, else the RealityKit
/// fallback. Quick Look has its own router (`PreviewExtension/QuickLookPreviewView.swift`).
struct PreviewView: View {
    enum State {
        case loading
        case ready(EntityLoader.LoadedModel)
        /// User-visible reason. Open never waits on IBL — lighting is applied later by `PreviewScene`.
        case failed(String)

        var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }

        /// Model bytes → RealityKit only. No HDR / EnvironmentResource on this path.
        static func loaded(from url: URL) async -> State {
            do {
                let model = try await EntityLoader.load(from: url)
                return .ready(model)
            } catch {
                let message = error.localizedDescription
                AppLog.error(AppLog.preview, "open failed \(url.lastPathComponent): \(message)")
                return .failed(message)
            }
        }
    }

    let state: State
    var interaction: PreviewInteraction
    var isDark: Bool
    var sidebar: (any PreviewOverlay)? = nil
    /// Host passes `HostSidebarModel.overlayRevision` so RealityView updates on select/hide.
    /// Reading it through `any PreviewOverlay` alone is not a reliable SwiftUI dependency.
    var overlayRevision: Int = 0
    /// Host-owned session; nil lets `PreviewScene` seed local `@State`.
    var session: PreviewSessionBindings? = nil
    /// When set, the model canvas is drawn by the shared web renderer instead of RealityKit.
    /// Migration step: overlays and camera chrome still belong to `PreviewScene` and are not
    /// drawn on this path yet.
    var webCanvasURL: URL? = nil
    /// Look applied to the web canvas.
    var webCanvasLook = WebPreviewCanvas.Look()
    /// Host-held web canvas: its load phase, its camera commands, and a page that survives the
    /// shell remount. Nil gives the canvas a private controller (no failure routing).
    var webCanvas: WebCanvasController? = nil
    /// RealityKit camera commands, registered while the RealityKit canvas is mounted.
    var realityCommands: FocusedPreviewCommands? = nil
    /// Called by whichever branch is on screen with that canvas's commands (nil when no canvas
    /// can take them). Runs in `onAppear`, never during a view update.
    var registerCommands: (FocusedPreviewCommands?) -> Void = { _ in }

    var body: some View {
        Group {
            if let webCanvasURL {
                // The web canvas loads the file itself. A convert failure (`state`) only affects
                // RealityKit-backed chrome; only the canvas's own failure replaces it.
                if case .failed(let message) = webCanvas?.phase {
                    failedView(message)
                        .onAppear { registerCommands(nil) }
                } else {
                    WebPreviewCanvas(url: webCanvasURL, look: webCanvasLook, controller: webCanvas)
                        .onAppear { registerCommands(webCanvas.map(FocusedPreviewCommands.web)) }
                }
            } else {
                switch state {
                case .loading:
                    ZStack {
                        PreviewBackground.window.color.ignoresSafeArea()
                        ProgressView()
                            .controlSize(.regular)
                            .progressViewStyle(.circular)
                    }
                    .onAppear { registerCommands(nil) }
                case .ready(let model):
                    RealityPreviewCanvas(
                        model: model,
                        interaction: interaction,
                        isDark: isDark,
                        sidebar: sidebar,
                        overlayRevision: overlayRevision,
                        session: session
                    )
                    .onAppear { registerCommands(realityCommands) }
                case .failed(let message):
                    failedView(message)
                        .onAppear { registerCommands(nil) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(_ message: String) -> some View {
        ZStack {
            PreviewBackground.window.color.ignoresSafeArea()
            VStack(spacing: 8) {
                Text("Failed to load model")
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .opacity(0.7)
            }
            .foregroundStyle(
                PreviewBackground.iconColor(at: 0, systemDark: isDark, active: true)
            )
            .padding()
        }
    }

    /// What the canvas region shows for this window. With the web canvas mounted, only the
    /// canvas's own failure fails it — convert may still be running, or may have failed, while
    /// the page draws. The RealityKit fallback follows convert.
    static func canvasState(
        webCanvasURL: URL?,
        webPhase: WebCanvasController.Phase?,
        convert: State
    ) -> ShellDocumentState {
        if webCanvasURL != nil {
            if case .failed(let message) = webPhase { return .failed(message) }
            return .ready
        }
        switch convert {
        case .loading: return .loading
        case .ready: return .ready
        case .failed(let message): return .failed(message)
        }
    }
}
