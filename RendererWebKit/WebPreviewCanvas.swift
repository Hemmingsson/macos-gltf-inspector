import AppKit
import GLTFCore
import Observation
import SwiftUI

/// Centered spinner + honest file facts while the live web view stays hidden.
private struct WebCanvasLoadingChrome: View {
    var title: String
    var detail: String?

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.regular)
                .progressViewStyle(.circular)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 12, weight: .medium))
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(.primary)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Cover the live view so a compiling/empty canvas cannot show through.
        .background(Color(nsColor: .windowBackgroundColor))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([title, detail].compactMap { $0 }.joined(separator: ". "))
    }
}

/// The model canvas of a WebKit document window and Quick Look preview: the shared web page,
/// mounted through an owner-held `WebCanvasController`.
public struct WebPreviewCanvas: NSViewRepresentable {
    let url: URL
    var look = Look()
    /// Icon Services thumbnail already on disk. Nil on the host window and on a cache miss.
    var placeholderImage: NSImage? = nil
    /// Live host already constructed (Quick Look `loadView` prestart). Nil in the document window.
    var host: WebRendererHost? = nil
    /// Owner-held controller: phase, camera commands, and a page that survives a remount of this
    /// view.
    let controller: WebCanvasController

    public init(
        url: URL,
        look: Look = Look(),
        placeholderImage: NSImage? = nil,
        host: WebRendererHost? = nil,
        controller: WebCanvasController
    ) {
        self.url = url
        self.look = look
        self.placeholderImage = placeholderImage
        self.host = host
        self.controller = controller
    }

    public func makeCoordinator() -> WebCanvasController {
        controller
    }

    public func makeNSView(context: Context) -> NSView {
        let container = ContainerView()
        context.coordinator.attach(
            to: container, url: url, look: look, placeholder: placeholderImage, existing: host
        )
        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.setPlaceholder(placeholderImage, in: nsView)
        context.coordinator.reload(url: url, look: look)
    }

    /// Plain container so the web view can be swapped without SwiftUI rebuilding the hierarchy.
    final class ContainerView: NSView {
        override var isFlipped: Bool { true }
    }
}

/// Drives one live web canvas: load, look, camera commands, and the load phase its owner routes on.
///
/// The owner (document window, Quick Look) keeps the controller and gets two things: `phase`
/// to end in its own `.failed(message)` state, and a page that survives a SwiftUI remount of
/// `WebPreviewCanvas` — the next mount adopts the running `WKWebView` instead of starting a new one.
@MainActor
@Observable
public final class WebCanvasController {
    public enum Phase: Equatable, Sendable {
        case loading
        /// The model is on screen.
        case ready
        /// Page start or model load failed. User-visible reason.
        case failed(String)
    }

    public private(set) var phase: Phase = .loading

    @ObservationIgnored private(set) var host: WebRendererHost?
    @ObservationIgnored private var loaded: URL?
    @ObservationIgnored private var appliedLook: WebPreviewCanvas.Look?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var placeholderView: NSImageView?
    @ObservationIgnored private var loadingHost: NSHostingView<WebCanvasLoadingChrome>?
    @ObservationIgnored private var didRevealLive = false
    /// The model the page was last restarted for. One restart per model: a file that kills the
    /// page twice (jetsam on a huge file) ends in `.failed`, not a restart loop.
    @ObservationIgnored private var restartedFor: URL?

    /// A controller the caller holds across mounts.
    public init() {}

    // MARK: - Camera commands (the mounted canvas's half of the host's canvas commands)

    /// Frames the model from the page's opening view (front). Also the canvas half of Reset:
    /// the owner restores Center and the other session values first.
    public func fit() async throws {
        try await readyHost().camera(.fit)
    }

    /// Canned orbit angle, framed from the page's measured scene box.
    public func apply(preset: CameraPreset) async throws {
        let host = try readyHost()
        let fitted = try await host.camera(.fit)
        let angles = preset.webOrbitAngles
        let distance = fitted.isMeasurable ? fitted.distance(framing: preset) : nil
        try await host.camera(.orbit(azimuth: angles.azimuth, elevation: angles.elevation, distance: distance))
    }

    /// One frame at the live camera and canvas size. The owner writes the file.
    public func snapshot() async throws -> CGImage {
        try await readyHost().renderStill()
    }

    private func readyHost() throws -> WebRendererHost {
        guard phase == .ready, let host else { throw WebRendererError.notReady }
        return host
    }

    // MARK: - Mounting

    func attach(
        to container: NSView,
        url: URL,
        look: WebPreviewCanvas.Look,
        placeholder: NSImage?,
        existing: WebRendererHost?
    ) {
        if let host {
            // Remount of an owner-held controller: move the running page into the new view.
            for view in [placeholderView, host.view, loadingHost].compactMap({ $0 }) {
                view.removeFromSuperview()
                Self.pin(view, in: container)
            }
            AppLog.info(
                AppLog.webRenderer,
                "viewport adopt \(url.lastPathComponent) host=\(host.logID) uptimeMs=\(WebRendererHost.uptimeMs())"
            )
            reload(url: url, look: look)
            return
        }

        if let placeholder {
            installPlaceholder(placeholder, in: container, below: nil)
        }
        installLoadingChrome(in: container)

        do {
            let host = try existing ?? WebRendererHost(mode: .live)
            self.host = host
            host.onFailure = { [weak self] error in self?.pageDied(error) }
            AppLog.info(
                AppLog.webRenderer,
                "viewport attach \(url.lastPathComponent) host=\(host.logID) reused=\(existing != nil) uptimeMs=\(WebRendererHost.uptimeMs())"
            )

            let view = host.view
            view.removeFromSuperview()
            // Visible under the loading chrome so the canvas gets a real size.
            // Alpha 0 made the first `renderFrame` 1×1; revealing then resized
            // (cleared) and the GPU frame ran on an empty screen.
            view.alphaValue = 1
            Self.pin(view, in: container)
            if let loadingHost {
                container.addSubview(loadingHost, positioned: .above, relativeTo: view)
            }

            reload(url: url, look: look)
        } catch {
            fail(error, loading: url)
        }
    }

    /// `updateNSView` runs on every SwiftUI pass, so an unchanged model and look touch nothing.
    /// A changed look goes to the page whole; the page redoes only what changed.
    func reload(url: URL, look: WebPreviewCanvas.Look) {
        guard let host else { return }

        let modelChanged = loaded != url
        guard modelChanged || appliedLook != look else { return }
        loaded = url
        appliedLook = look

        work?.cancel()
        work = Task { [host] in
            do {
                var inventory: WebRendererAssetInventory?
                if modelChanged {
                    didRevealLive = false
                    phase = .loading
                    showLoading(
                        title: WebRendererLoadCopy.starting,
                        detail: nil
                    )
                    let peek = Task.detached(priority: .userInitiated) {
                        WebRendererAssetInventory.peek(from: url)
                    }
                    Task {
                        let peeked = await peek.value
                        await MainActor.run {
                            guard !self.didRevealLive, self.phase == .loading else { return }
                            self.showLoading(
                                title: WebRendererLoadCopy.message(for: peeked),
                                detail: WebRendererLoadCopy.detail(for: peeked)
                            )
                        }
                    }
                    try await host.start()
                    // The peek task above shows its copy; keep it for the "Drawing…" detail.
                    inventory = await peek.value
                    try Task.checkCancellation()
                } else {
                    try await host.start()
                }

                // Whole look, before the load on a new model: the page records the HDR and
                // starts it after the model, so first paint does not wait on IBL.
                try await host.apply(look)

                if modelChanged {
                    showLoading(
                        title: WebRendererLoadCopy.drawing,
                        detail: WebRendererLoadCopy.detail(for: inventory)
                    )
                    let info = try await host.load(model: url)
                    try Task.checkCancellation()
                    revealLive(host: host)
                    AppLog.info(
                        AppLog.webRenderer,
                        "viewport ready \(url.lastPathComponent) tris=\(info.triangles) canvas=\(info.width)x\(info.height) firstFrameMs=\(info.firstFrameMs) uptimeMs=\(WebRendererHost.uptimeMs())"
                    )
                }
            } catch is CancellationError {
                // Superseded by a newer look or model; nothing to report.
            } catch where Task.isCancelled {
                // Superseded while the page was failing (a restart already took over).
            } catch {
                // Before the model is on screen every error is a failed load (a page that never
                // started, a file the page rejected, a timeout). After it, a look command that
                // fails leaves the drawn model in place.
                if didRevealLive {
                    AppLog.error(AppLog.webRenderer, "viewport update failed \(url.lastPathComponent): \(error)")
                } else {
                    fail(error, loading: url)
                }
            }
        }
    }

    /// The running page died (WebContent crash, WebGL context loss). Load a fresh page into the
    /// same web view and redraw the model once; a second death for the same model fails.
    private func pageDied(_ error: WebRendererError) {
        guard let url = loaded, let look = appliedLook else { return }
        guard restartedFor != url else {
            work?.cancel()
            fail(error, loading: url)
            return
        }
        restartedFor = url
        AppLog.info(AppLog.webRenderer, "viewport restart \(url.lastPathComponent) after \(error)")
        loaded = nil
        appliedLook = nil
        reload(url: url, look: look)
    }

    func setPlaceholder(_ image: NSImage?, in container: NSView) {
        guard !didRevealLive, let image else { return }
        if let placeholderView {
            placeholderView.image = image
            placeholderView.isHidden = false
            return
        }
        installPlaceholder(image, in: container, below: host?.view)
    }

    /// Terminal load failure. The owner routes on `phase` and swaps this canvas for its own
    /// failure view, so a failure never shows a spinner. The log keeps the raw error; the person
    /// sees `WebRendererError.userMessage`.
    private func fail(_ error: Error, loading url: URL) {
        AppLog.error(AppLog.webRenderer, "viewport failed \(url.lastPathComponent): \(error)")
        phase = .failed(WebRendererError.userMessage(for: error))
    }

    private func revealLive(host: WebRendererHost) {
        didRevealLive = true
        phase = .ready
        host.view.alphaValue = 1
        placeholderView?.isHidden = true
        loadingHost?.isHidden = true
    }

    private func showLoading(title: String, detail: String?) {
        guard !didRevealLive else { return }
        let chrome = WebCanvasLoadingChrome(title: title, detail: detail)
        if let loadingHost {
            loadingHost.rootView = chrome
            loadingHost.isHidden = false
        }
    }

    private func installLoadingChrome(in container: NSView) {
        let host = NSHostingView(
            rootView: WebCanvasLoadingChrome(title: WebRendererLoadCopy.starting, detail: nil)
        )
        host.wantsLayer = true
        host.layer?.isOpaque = false
        host.layer?.backgroundColor = NSColor.clear.cgColor
        Self.pin(host, in: container)
        loadingHost = host
    }

    private func installPlaceholder(_ image: NSImage, in container: NSView, below sibling: NSView?) {
        let view = NSImageView()
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.wantsLayer = true
        view.layer?.isOpaque = false
        Self.pin(view, in: container, below: sibling)
        placeholderView = view
    }

    /// Adds `view` edge-to-edge in `container` (on top, or below `sibling`).
    private static func pin(_ view: NSView, in container: NSView, below sibling: NSView? = nil) {
        view.translatesAutoresizingMaskIntoConstraints = false
        if let sibling, sibling.superview === container {
            container.addSubview(view, positioned: .below, relativeTo: sibling)
        } else {
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}

extension WebPreviewCanvas {
    /// What the page can do today (`Look` fields and page commands). No clip playback, morph
    /// weights, hide/solo, skeleton overlay or file-light toggle: the page renders the file as
    /// authored. Host availability hides the matching chrome.
    public static let features: Set<RendererFeature> = [
        .wireframe,
        .debugChannels,
        .orthographicProjection,
        .environmentRotation,
        .toneMapping,
        .materialVariants,
        .nodeSelection,
    ]
}
