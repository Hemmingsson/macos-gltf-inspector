import AppKit
import GLTFCore
import QuickLookUI
import RendererWebKit
import SwiftUI

/// Quick Look principal class: the page loads the file itself, since Quick Look's process is cold
/// on every spacebar press. The live host starts in `loadView` so the page compiles while Quick
/// Look builds its chrome; `present` hands that same host to the canvas.
class PreviewViewController: NSViewController, QLPreviewingController {
    private var hostingView: NSHostingView<QuickLookWebView>!
    private var prestartedHost: (any CanvasRendererHost)?

    override func loadView() {
        prestartRenderer()
        let dark = Self.systemIsDark()
        hostingView = QuickLookHostingView(rootView: QuickLookWebView(state: .loading, isDark: dark))
        hostingView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view = hostingView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        present(url: url, dark: Self.systemIsDark())
    }

    private func prestartRenderer() {
        do {
            let host = try CanvasRenderer.makeHost(mode: .live)
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
            hostingView.rootView = QuickLookWebView(
                state: .failed("Couldn't start the web renderer"),
                isDark: dark
            )
            return
        }
        hostingView.rootView = QuickLookWebView(
            state: .web(
                url: url,
                // The thumbnail's stored look, plus the floor the preview has always shown.
                look: .stored(showsFloor: true),
                // Cached Finder poster when the thumbnail extension has written one.
                placeholder: firstPixelNSImage(for: url),
                host: host,
                canvas: WebCanvasController()
            ),
            isDark: dark
        )
    }

    private static func systemIsDark() -> Bool {
        if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" {
            return true
        }
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

/// Transparent hosting view that never drives the Quick Look panel's size.
private final class QuickLookHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

/// The web canvas once a file is presented, else a spinner or the failure message — including
/// the page's own load failure (`WebCanvasController.phase`).
struct QuickLookWebView: View {
    enum State {
        case loading
        case failed(String)
        /// Cached Finder poster under the web view until `load` unhides it.
        case web(
            url: URL,
            look: WebPreviewCanvas.Look,
            placeholder: NSImage?,
            host: any CanvasRendererHost,
            canvas: WebCanvasController
        )
    }

    let state: State
    var isDark: Bool

    var body: some View {
        Group {
            switch state {
            case .web(let url, let look, let placeholder, let host, let canvas):
                if case .failed(let message) = canvas.phase {
                    failedView(message)
                } else {
                    WebPreviewCanvas(
                        url: url, look: look, placeholderImage: placeholder, host: host, controller: canvas
                    )
                }
            case .loading:
                ProgressView()
                    .controlSize(.regular)
                    .progressViewStyle(.circular)
            case .failed(let message):
                failedView(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Failed to load model")
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .opacity(0.7)
        }
        .foregroundStyle(isDark ? .white : Color(red: 38.0 / 255, green: 38.0 / 255, blue: 38.0 / 255))
        .padding()
    }
}

private func firstPixelNSImage(for url: URL) -> NSImage? {
    guard let image = FirstPixelPreview.image(for: url) else { return nil }
    return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
}
