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
        let readiness = PreviewReadiness()
        try Task.checkCancellation()
        await MainActor.run {
            hostingView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            hostingView.rootView = AnyView(
                QuickLookCanvas(url: url, isDark: dark) { phase in
                    readiness.signal(phase)
                }
            )
        }

        let timeout = Task {
            do {
                try await Task.sleep(for: .seconds(15))
                readiness.resolve(.timedOut)
            } catch {
                // The model became ready or the host cancelled the request.
            }
        }
        let result = await readiness.wait()
        timeout.cancel()
        switch result {
        case .ready:
            return
        case .failed:
            throw PreviewError.failed
        case .timedOut:
            throw PreviewError.timedOut
        case .cancelled:
            throw CancellationError()
        }
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
    let onPhase: (ModelCanvasController.Phase) -> Void
    @State private var canvas = ModelCanvasController()

    var body: some View {
        Group {
            if case .failed = canvas.phase {
                VStack(spacing: 8) {
                    Text("Failed to load model")
                        .font(.system(size: 13, weight: .semibold))
                    Text("The model could not be loaded. Check the file and try again.")
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
        .onChange(of: canvas.phase, initial: true) { _, phase in
            onPhase(phase)
        }
    }
}

private enum PreviewReadinessResult: Sendable {
    case ready
    case failed
    case timedOut
    case cancelled
}

private final class PreviewReadiness: @unchecked Sendable {
    private let lock = NSLock()
    private var result: PreviewReadinessResult?
    private var continuation: CheckedContinuation<PreviewReadinessResult, Never>?

    func signal(_ phase: ModelCanvasController.Phase) {
        switch phase {
        case .loading:
            return
        case .ready:
            resolve(.ready)
        case .failed:
            resolve(.failed)
        }
    }

    func wait() async -> PreviewReadinessResult {
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(returning: result)
                } else {
                    self.continuation = continuation
                    lock.unlock()
                }
            }
        }, onCancel: {
            resolve(.cancelled)
        })
    }

    func resolve(_ result: PreviewReadinessResult) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

private enum PreviewError: Error {
    case failed
    case timedOut
}

/// Transparent, and never drives the Quick Look panel's size.
private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @MainActor required init?(coder: NSCoder) {
        preconditionFailure("TransparentHostingView cannot be decoded from a storyboard")
    }

    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
