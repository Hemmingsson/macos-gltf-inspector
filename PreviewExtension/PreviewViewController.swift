import AppKit
import QuickLookUI
import Renderer
import SwiftUI

/// Quick Look principal class: the live model canvas with the stored Settings look and a floor.
class PreviewViewController: NSViewController, QLPreviewingController {
    private let hostingView = TransparentHostingView(rootView: AnyView(EmptyView()))

    override func loadView() {
        view = hostingView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let dark = Self.systemIsDark()
        hostingView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hostingView.rootView = AnyView(QuickLookCanvas(url: url, isDark: dark))
    }

    /// The extension's own appearance does not follow the system reliably, so read the setting.
    private static func systemIsDark() -> Bool {
        if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" { return true }
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private struct QuickLookCanvas: View {
    let url: URL
    let isDark: Bool
    @State private var canvas = ModelCanvasController()

    var body: some View {
        Group {
            if case .failed(let message) = canvas.phase {
                VStack(spacing: 8) {
                    Text("Failed to load model")
                        .font(.system(size: 13, weight: .semibold))
                    Text(message)
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .opacity(0.7)
                }
                .foregroundStyle(isDark ? .white : Color(white: 0.15))
                .padding()
            } else {
                ModelCanvas(
                    url: url,
                    options: .stored(showsFloor: true, autoRotates: true, isCentered: false, centerWhenFarFromOrigin: true),
                    controller: canvas
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Transparent, and never drives the Quick Look panel's size.
private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @MainActor required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
