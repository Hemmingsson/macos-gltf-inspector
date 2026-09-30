import AppKit
import RendererRealityKit
import RendererWebKit
import SwiftUI

/// Quick Look canvas router: the web canvas once a file is presented, else a spinner or the
/// failure message — including the web canvas's own load failure (`WebCanvasController.phase`).
/// No RealityKit convert — Quick Look's process is cold on every spacebar press.
/// The document window's router is `GLTFInspector/PreviewView.swift`.
struct QuickLookPreviewView: View {
    enum State {
        case loading
        case failed(String)
        /// Cached Finder icon shows under the web view until `load` unhides it.
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
                ZStack {
                    PreviewBackground.window.color.ignoresSafeArea()
                    ProgressView()
                        .controlSize(.regular)
                        .progressViewStyle(.circular)
                }
            case .failed(let message):
                failedView(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(_ message: String) -> some View {
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
