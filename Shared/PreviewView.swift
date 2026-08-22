import RealityKit
import SwiftUI

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
    /// Host-owned session; nil in Quick Look (PreviewScene seeds local `@State`).
    var session: PreviewSessionBindings? = nil

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
            case .ready(let model):
                PreviewScene(
                    entity: model.entity,
                    document: model.document,
                    stats: model.stats,
                    debugModes: model.debugModes,
                    studioIBLExponent: model.studioIBLExponent,
                    interaction: interaction,
                    isDark: isDark,
                    sidebar: sidebar,
                    overlayRevision: overlayRevision,
                    session: session
                )
                .id("\(ObjectIdentifier(model.entity))-\(session?.centerModel.wrappedValue ?? true)")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
