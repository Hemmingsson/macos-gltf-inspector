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
        // Detached so Quick Look can present the loading view on the main actor
        // before GLTFKit2 convert occupies it.
        loadTask?.cancel()
        loadTask = Task.detached { [weak self] in
            await Task.yield()
            let state = await PreviewView.State.loaded(from: url)
            guard !Task.isCancelled else { return }
            await self?.present(state, dark: dark)
        }
    }

    @MainActor
    private func present(_ state: PreviewView.State, dark: Bool) {
        hostingView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hostingView.rootView = PreviewView(state: state, interaction: interaction, isDark: dark)
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
