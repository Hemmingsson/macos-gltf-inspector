import AppKit
import GLTFCore
import Observation
import SwiftUI

/// The live model canvas of the document window and the Quick Look preview.
///
/// Its owner keeps the `ModelCanvasController`, which outlives a SwiftUI remount of this view:
/// the next mount adopts the running `ModelView` instead of loading the file again.
public struct ModelCanvas: View {
    let url: URL
    let options: ViewOptions
    let controller: ModelCanvasController

    public init(url: URL, options: ViewOptions, controller: ModelCanvasController) {
        self.url = url
        self.options = options
        self.controller = controller
    }

    public var body: some View {
        CanvasRepresentable(url: url, options: options, controller: controller)
            .overlay {
                if controller.phase == .loading {
                    ProgressView("Loading model…")
                        .controlSize(.small)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Loads a file into one `ModelView`, keeps its options in sync and reports how that went.
@MainActor
@Observable
public final class ModelCanvasController {
    public enum Phase: Equatable, Sendable {
        case loading
        /// The model is on screen.
        case ready
        /// The renderer could not start or the file could not be drawn. User-visible reason.
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    /// Camera zoom against the last fit (100 = fitted). Nil before the first model is framed.
    public private(set) var zoomPercent: Int?

    @ObservationIgnored private(set) var view: ModelView?
    /// The file and options SwiftUI last asked for; `sync` brings the view there.
    @ObservationIgnored private var wanted: (url: URL, options: ViewOptions)?
    @ObservationIgnored private var loadedURL: URL?
    @ObservationIgnored private var isSyncing = false

    public init() {}

    // MARK: - Camera commands

    public func fit() { readyView?.fit() }
    public func show(_ preset: CameraPreset) { readyView?.show(preset) }
    public func zoom(by factor: Double) { readyView?.zoom(by: factor) }

    /// One frame at the canvas's pixel size. The caller writes the file.
    public func snapshot() throws -> CGImage {
        guard let view = readyView else { throw MetalRendererError.noScene }
        return try view.snapshot()
    }

    private var readyView: ModelView? { phase == .ready ? view : nil }

    // MARK: - Mounting

    /// Puts the model view in `container`, creating it on first use.
    func mount(in container: NSView, url: URL, options: ViewOptions) {
        if view == nil {
            do {
                let view = ModelView(renderer: try MetalRenderer())
                view.onZoom = { [weak self] in self?.zoomPercent = $0 }
                view.onFailure = { [weak self] in self?.fail($0) }
                self.view = view
            } catch {
                loadedURL = url
                fail(error)
                return
            }
        }
        guard let view else { return }
        view.removeFromSuperview()
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        update(url: url, options: options)
    }

    /// Runs on every SwiftUI update. Records what is wanted; one `sync` at a time does the work,
    /// so renderer calls never overlap and the latest request always wins.
    func update(url: URL, options: ViewOptions) {
        wanted = (url, options)
        guard !isSyncing else { return }
        isSyncing = true
        Task {
            await sync()
            isSyncing = false
        }
    }

    /// Loads the wanted file, then applies the wanted options, until the view matches both.
    /// A failed file stays failed until a different file is wanted.
    private func sync() async {
        while let view, let wanted {
            do {
                if wanted.url != loadedURL {
                    loadedURL = wanted.url
                    phase = .loading
                    let started = ContinuousClock.now
                    try await view.load(wanted.url, options: wanted.options)
                    guard self.wanted?.url == wanted.url else { continue }
                    phase = .ready
                    AppLog.info(AppLog.renderer, "canvas ready \(wanted.url.lastPathComponent) in \(started.duration(to: .now))")
                } else if case .failed = phase {
                    return
                } else if view.options != wanted.options {
                    try await view.apply(wanted.options)
                } else {
                    return
                }
            } catch {
                if self.wanted?.url != wanted.url { continue }
                if phase == .ready {
                    // An options change failed; the model drawn so far stays.
                    AppLog.error(AppLog.renderer, "canvas update failed \(wanted.url.lastPathComponent): \(error)")
                } else {
                    fail(error)
                }
                return
            }
        }
    }

    /// The owner routes on `phase` and swaps the canvas for its own failure view. The log keeps
    /// the raw error; the person sees a sentence.
    private func fail(_ error: Error) {
        AppLog.error(AppLog.renderer, "canvas failed \(loadedURL?.lastPathComponent ?? "-"): \(error)")
        phase = .failed(Self.message(for: error))
    }

    static func message(for error: Error) -> String {
        if case MetalRendererError.unavailable = error { return "This Mac can't run the Metal renderer." }
        return "The model couldn't be displayed. The file may be damaged or use features the renderer doesn't support."
    }
}

private struct CanvasRepresentable: NSViewRepresentable {
    let url: URL
    let options: ViewOptions
    let controller: ModelCanvasController

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        controller.mount(in: container, url: url, options: options)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        controller.update(url: url, options: options)
    }
}
