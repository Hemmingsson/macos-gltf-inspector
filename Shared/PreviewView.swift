import AppKit
import GLTFCore
import RendererRealityKit
import SwiftUI

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
    /// Host-owned session; nil in Quick Look (PreviewScene seeds local `@State`).
    var session: PreviewSessionBindings? = nil
    /// When set, the model canvas is drawn by the shared web renderer instead of RealityKit.
    /// Migration step: overlays and camera chrome still belong to `PreviewScene` and are not
    /// drawn on this path yet.
    var webCanvasURL: URL? = nil
    /// Look applied to the web canvas.
    var webCanvasLook = WebPreviewCanvas.Look()
    /// Cached Finder icon shown under the web view until `load` unhides it. Quick Look only.
    var placeholderImage: NSImage? = nil
    /// Optional live host already constructed (Quick Look `loadView` prestart).
    var webCanvasHost: WebRendererHost? = nil

    var body: some View {
        Group {
            // The web canvas shows its own spinner + file facts while WKWebView stays hidden.
            // Quick Look takes this path with no RealityKit convert, which is where the
            // wait is — its process is cold on every spacebar press.
            if let webCanvasURL, !state.isFailed {
                WebPreviewCanvas(
                    url: webCanvasURL,
                    look: webCanvasLook,
                    placeholderImage: placeholderImage,
                    host: webCanvasHost
                )
            } else {
                switch state {
                case .loading:
                    ZStack {
                        PreviewBackground.window.color.ignoresSafeArea()
                        ProgressView()
                            .controlSize(.regular)
                            .progressViewStyle(.circular)
                    }
                case .ready(let model):
                    RealityPreviewCanvas(
                        model: model,
                        interaction: interaction,
                        isDark: isDark,
                        sidebar: sidebar,
                        overlayRevision: overlayRevision,
                        session: session
                    )
                case .failed(let message):
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
