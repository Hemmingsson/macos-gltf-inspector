import AppKit
import RealityKit
import SwiftUI

struct PreviewView: View {
    enum State {
        case loading
        case ready(EntityLoader.LoadedModel)
        case failed

        /// File IO runs off the main actor (`EntityLoader.load`).
        static func loaded(from url: URL) async -> State {
            let look = await MainActor.run { AppLookStore.shared.look }
            async let ibl: Void = PreviewLighting.prefetchLook(look)
            do {
                let model = try await EntityLoader.load(from: url)
                await ibl
                return .ready(model)
            } catch {
                AppLog.error(AppLog.preview, "State.failed \(url.path) \(error)")
                return .failed
            }
        }
    }

    let state: State
    var interaction: PreviewInteraction
    var isDark: Bool
    var sidebar: (any PreviewOverlay)? = nil

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
                    stats: model.stats,
                    debugModes: model.debugModes,
                    studioIBLExponent: model.studioIBLExponent,
                    interaction: interaction,
                    isDark: isDark,
                    sidebar: sidebar
                )
            case .failed:
                ZStack {
                    PreviewBackground.window.color.ignoresSafeArea()
                    Text("Failed to load model")
                        .font(.system(size: 13))
                        .foregroundStyle(
                            PreviewBackground.iconColor(at: 0, systemDark: isDark, active: true).opacity(0.5)
                        )
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
