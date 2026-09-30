import AppKit
import RendererRealityKit
import RendererWebKit
import SwiftUI

/// Quick Look canvas router: the web canvas once a file is presented, else a spinner or the
/// failure message. No RealityKit convert — Quick Look's process is cold on every spacebar press.
/// The document window's router is `GLTFInspector/PreviewView.swift`.
struct QuickLookPreviewView: View {
    enum State {
        case loading
        case failed(String)
        /// Cached Finder icon shows under the web view until `load` unhides it.
        case web(url: URL, look: WebPreviewCanvas.Look, placeholder: NSImage?, host: WebRendererHost)
    }

    let state: State
    var isDark: Bool

    var body: some View {
        Group {
            switch state {
            case .web(let url, let look, let placeholder, let host):
                WebPreviewCanvas(url: url, look: look, placeholderImage: placeholder, host: host)
            case .loading:
                ZStack {
                    PreviewBackground.window.color.ignoresSafeArea()
                    ProgressView()
                        .controlSize(.regular)
                        .progressViewStyle(.circular)
                }
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
