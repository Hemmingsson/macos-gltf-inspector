import AppKit
import GLTFCore
import QuickLookUI
import RendererWebKit
import SwiftUI

/// Quick Look on the WebKit renderer: the page loads the file itself — no convert, since Quick
/// Look's process is cold on every spacebar press. The live host starts in `loadView` so the page
/// compiles while Quick Look builds its chrome; `present` hands that same host to the canvas.
final class WebQuickLookController: NSViewController, QLPreviewingController {
    private var hostingView: NSHostingView<QuickLookWebView>!
    private var prestartedHost: WebRendererHost?

    override func loadView() {
        prestartRenderer()
        let dark = PreviewViewController.systemIsDark()
        hostingView = QuickLookHostingView(rootView: QuickLookWebView(state: .loading, isDark: dark))
        hostingView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view = hostingView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        present(url: url, dark: PreviewViewController.systemIsDark())
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
            hostingView.rootView = QuickLookWebView(
                state: .failed("Couldn't start the web renderer"),
                isDark: dark
            )
            return
        }
        // App Group poster from the thumbnail extension, or a JSON bounding-box proxy.
        let placeholder = firstPixelNSImage(for: url, renderer: .webKit)
        hostingView.rootView = QuickLookWebView(
            state: .web(
                url: url,
                // The thumbnail's stored look, plus the floor the preview has always shown.
                look: .stored(showsFloor: true),
                placeholder: placeholder,
                host: host,
                canvas: WebCanvasController()
            ),
            isDark: dark
        )
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
        /// App Group poster or bounding-box proxy under the web view until `load` unhides it.
        case web(
            url: URL,
            look: WebPreviewCanvas.Look,
            placeholder: NSImage?,
            host: WebRendererHost,
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
        QuickLookFailureView(
            message: message,
            foreground: isDark ? .white : Color(red: 38.0 / 255, green: 38.0 / 255, blue: 38.0 / 255)
        )
    }
}

func firstPixelNSImage(for url: URL, renderer: RendererKind) -> NSImage {
    let image = FirstPixelPreview.image(for: url, renderer: renderer)
    return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
}
