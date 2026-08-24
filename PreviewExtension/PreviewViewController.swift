import Cocoa
import QuickLookUI
import SwiftUI

class PreviewViewController: NSViewController, QLPreviewingController {
    private let interaction = PreviewInteraction()
    private var hostingView: PreviewHostingView!
    private var loadTask: Task<Void, Never>?

    override func loadView() {
        let dark = Self.systemIsDark()

        hostingView = PreviewHostingView(
            rootView: PreviewView(state: .loading, interaction: interaction, isDark: dark)
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
        let dark = Self.systemIsDark()
        // No RealityKit convert on this path: the web canvas loads the file itself. That
        // matters more here than anywhere — the extension process is cold on every spacebar
        // press, so the convert was pure latency before the first frame.
        loadTask?.cancel()
        await present(url: url, dark: dark)
    }

    @MainActor
    private func present(url: URL, dark: Bool) {
        hostingView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        // Same app default the thumbnail uses, so preview and Finder icon agree.
        let defaults = RendererLookDefaults.current()
        hostingView.rootView = PreviewView(
            state: .loading,
            interaction: interaction,
            isDark: dark,
            webCanvasURL: url,
            webCanvasLook: WebPreviewCanvas.Look(
                environment: defaults.environment,
                toneMapping: defaults.toneMapping
            )
        )
    }

    private static func systemIsDark() -> Bool {
        if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" {
            return true
        }
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return true
        }
        return false
    }
}
