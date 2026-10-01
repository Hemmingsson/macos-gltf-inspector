import AppKit
import GLTFCore
import QuickLookUI
import RendererRealityKit
import SwiftUI

/// Quick Look on the RealityKit renderer (as `main` ships it): convert off the main actor, then
/// `RealityPreviewCanvas` with its own inline chrome (backdrop cycle, auto-rotate, facts).
/// `PreviewEventView` sits at the root so scroll / magnify reach `PreviewInteraction` before the
/// hosting view.
final class RealityQuickLookController: NSViewController, QLPreviewingController {
    private let interaction = PreviewInteraction()
    private var hostingView: PreviewHostingView<QuickLookRealityView>!
    private var loadTask: Task<Void, Never>?

    override func loadView() {
        let dark = PreviewViewController.systemIsDark()
        hostingView = PreviewHostingView(
            rootView: QuickLookRealityView(state: .loading, interaction: interaction, isDark: dark)
        )
        hostingView.interaction = interaction
        hostingView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hostingView.autoresizingMask = [.width, .height]

        let root = PreviewEventView(frame: .zero)
        root.interaction = interaction
        root.wantsLayer = true
        root.layer?.isOpaque = false
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.addSubview(hostingView)
        view = root
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        hostingView.frame = view.bounds
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        loadTask?.cancel()
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let dark = PreviewViewController.systemIsDark()
        present(
            .loading,
            poster: firstPixelNSImage(for: url, renderer: .realityKit),
            dark: dark
        )
        // Detached so Quick Look can present the poster on the main actor before GLTFKit2
        // convert occupies it.
        loadTask?.cancel()
        loadTask = Task.detached { [weak self] in
            await Task.yield()
            let state = await RealityLoadState.loaded(from: url)
            if case .failed(let message) = state {
                AppLog.error(AppLog.preview, "open failed \(url.lastPathComponent): \(message)")
            }
            guard !Task.isCancelled else { return }
            await self?.present(state, dark: dark)
        }
    }

    @MainActor
    private func present(_ state: RealityLoadState, poster: NSImage? = nil, dark: Bool) {
        hostingView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hostingView.rootView = QuickLookRealityView(
            state: state,
            poster: poster,
            interaction: interaction,
            isDark: dark
        )
    }
}

/// Poster / proxy, `RealityPreviewCanvas`, or the failure message.
struct QuickLookRealityView: View {
    let state: RealityLoadState
    var poster: NSImage? = nil
    var interaction: PreviewInteraction
    var isDark: Bool

    var body: some View {
        Group {
            switch state {
            case .loading:
                if let poster {
                    Image(nsImage: poster)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                        .controlSize(.regular)
                        .progressViewStyle(.circular)
                }
            case .ready(let model):
                RealityPreviewCanvas(model: model, interaction: interaction, isDark: isDark)
            case .failed(let message):
                QuickLookFailureView(
                    message: message,
                    foreground: PreviewBackground.iconColor(at: 0, systemDark: isDark, active: true)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
