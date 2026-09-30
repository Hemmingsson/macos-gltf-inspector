import GLTFCore
import RendererRealityKit
import SwiftUI

/// RealityKit document-window canvas: spinner while convert runs, `RealityPreviewCanvas` once it
/// lands, the failure message when it fails. Quick Look has its own RealityKit root
/// (`PreviewExtension/QuickLookRealityKit.swift`).
struct PreviewView: View {
    enum State {
        case loading
        case ready(EntityLoader.LoadedModel)
        /// User-visible reason. Open never waits on IBL — lighting is applied later by `PreviewScene`.
        case failed(String)

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
    /// RealityKit camera commands, registered while the canvas is mounted.
    var commands: FocusedPreviewCommands? = nil
    /// Called with the mounted canvas's commands (nil while there is no canvas). Runs in
    /// `onAppear`, never during a view update.
    var registerCommands: (FocusedPreviewCommands?) -> Void = { _ in }

    var body: some View {
        Group {
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
                .onAppear { registerCommands(commands) }
            case .failed(let message):
                failedView(message)
                    .onAppear { registerCommands(nil) }
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
}
