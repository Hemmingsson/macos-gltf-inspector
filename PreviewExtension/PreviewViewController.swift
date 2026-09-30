import Cocoa
import GLTFCore
import QuickLookUI
import RendererRealityKit
import RendererWebKit
import SwiftUI

class PreviewViewController: NSViewController, QLPreviewingController {
    private let interaction = PreviewInteraction()
    private var hostingView: PreviewHostingView!
    private var loadTask: Task<Void, Never>?
    /// Live host kicked in `loadView` so the module compiles while QL builds chrome.
    /// `present` injects this same instance — no second `WKWebView`.
    private var prestartedHost: WebRendererHost?

    override func loadView() {
        prestartRenderer()
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
        loadTask?.cancel()
        await present(url: url, dark: dark)
    }

    private func prestartRenderer() {
        do {
            let host = try WebRendererHost(mode: .live)
            prestartedHost = host
            Task { @MainActor in
                do {
                    try await host.start()
                } catch {
                    AppLog.error(AppLog.webRenderer, "ql prestart failed: \(error.localizedDescription)")
                }
            }
        } catch {
            AppLog.error(AppLog.webRenderer, "ql prestart failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func present(url: URL, dark: Bool) {
        hostingView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        guard let host = prestartedHost else {
            hostingView.rootView = PreviewView(
                state: .failed("Couldn't start the web renderer"),
                interaction: interaction,
                isDark: dark
            )
            return
        }
        let defaults = AppGroupSettings.rendererLook()
        // Cache-only Icon Services read — does not start ThumbnailExtension.
        let placeholder = CachedQuickLookThumbnail.existingIcon(for: url)
        hostingView.rootView = PreviewView(
            state: .loading,
            interaction: interaction,
            isDark: dark,
            webCanvasURL: url,
            webCanvasLook: WebPreviewCanvas.Look(
                environment: defaults.environment,
                toneMapping: defaults.toneMapping
            ),
            placeholderImage: placeholder,
            webCanvasHost: host
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
