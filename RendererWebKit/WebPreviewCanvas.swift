import AppKit
import GLTFCore
import Observation
import SwiftUI

/// Centered spinner + honest file facts while the live web view stays hidden.
private struct WebCanvasLoadingChrome: View {
    var title: String
    var detail: String?
    /// False once the load has failed — a failure must never look like it is still working.
    var showsSpinner = true

    var body: some View {
        VStack(spacing: 8) {
            if showsSpinner {
                ProgressView()
                    .controlSize(.regular)
                    .progressViewStyle(.circular)
                    .accessibilityHidden(true)
            }
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

/// The document window's model canvas, rendered by the shared web renderer.
///
/// First step of the viewport migration: this replaces `PreviewScene`'s `RealityView` as the
/// thing that draws the model. Sidebar, inspector and overlays still read the RealityKit
/// document — decoupling those is `SceneModel from glTF JSON`, a separate task.
public struct WebPreviewCanvas: NSViewRepresentable {
    /// Look settings as plain values.
    ///
    /// Deliberately not `LightingSettings`: that type lives in `PreviewUI`, which the Quick Look
    /// and thumbnail extensions do not link. Keeping this primitive is what lets one canvas serve
    /// all three surfaces.
    public struct Look: Equatable {
        /// Bundled `.hdr` stem — `neutral`, `field`, `Colorful_Studio`.
        var environment: String
        /// Khronos `GltfState.ToneMaps` value.
        var toneMapping: String
        /// Exposure compensation in stops.
        var exposure: Double
        /// Environment yaw in degrees.
        var environmentRotation: Double
        /// Backdrop as `[r, g, b, a]` in 0-1. Alpha 0 shows the host window through.
        var backdrop: [Double]
        var autoRotates: Bool
        /// `perspective` or `orthographic`.
        var projection: String
        /// Vertical field of view in degrees.
        var fieldOfView: Double
        /// Khronos `GltfState.DebugOutput` value; `None` for normal shading.
        var debugChannel: String
        /// Camera authored in the file, or nil for the user camera.
        var fileCameraIndex: Int?
        /// `KHR_materials_variants` index, or nil for the file default.
        var materialVariantIndex: Int?
        /// Scene index.
        var sceneIndex: Int
        var showsFloor: Bool
        /// False shows the authored-origin gizmo and frames so the origin is visible.
        var isCentered: Bool
        var wireframe: Bool
        /// glTF node index highlighted on the canvas.
        var selectedNodeIndex: Int?

        public init(
            environment: String = AppGroupSettings.defaultEnvironment,
            toneMapping: String = AppGroupSettings.defaultToneMapping,
            exposure: Double = 0,
            environmentRotation: Double = 0,
            backdrop: [Double] = [0, 0, 0, 0],
            autoRotates: Bool = false,
            projection: String = "perspective",
            fieldOfView: Double = 45,
            debugChannel: String = "None",
            fileCameraIndex: Int? = nil,
            materialVariantIndex: Int? = nil,
            sceneIndex: Int = 0,
            showsFloor: Bool = true,
            isCentered: Bool = true,
            wireframe: Bool = false,
            selectedNodeIndex: Int? = nil
        ) {
            self.environment = environment
            self.toneMapping = toneMapping
            self.exposure = exposure
            self.environmentRotation = environmentRotation
            self.backdrop = backdrop
            self.autoRotates = autoRotates
            self.projection = projection
            self.fieldOfView = fieldOfView
            self.debugChannel = debugChannel
            self.fileCameraIndex = fileCameraIndex
            self.materialVariantIndex = materialVariantIndex
            self.sceneIndex = sceneIndex
            self.showsFloor = showsFloor
            self.isCentered = isCentered
            self.wireframe = wireframe
            self.selectedNodeIndex = selectedNodeIndex
        }
    }

    let url: URL
    var look = Look()
    /// Icon Services thumbnail already on disk. Nil on the host window and on a cache miss.
    var placeholderImage: NSImage? = nil
    /// Live host already constructed (Quick Look `loadView` prestart). Nil in the document window.
    var host: WebRendererHost? = nil
    /// Owner-held controller: phase, camera commands, and a page that survives a remount of this
    /// view. Nil gives the canvas a private controller that dies with the view.
    var controller: WebCanvasController? = nil

    public init(
        url: URL,
        look: Look = Look(),
        placeholderImage: NSImage? = nil,
        host: WebRendererHost? = nil,
        controller: WebCanvasController? = nil
    ) {
        self.url = url
        self.look = look
        self.placeholderImage = placeholderImage
        self.host = host
        self.controller = controller
    }

    public func makeCoordinator() -> WebCanvasController {
        controller ?? WebCanvasController(outlivesMount: false)
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

    public static func dismantleNSView(_ nsView: NSView, coordinator: WebCanvasController) {
        coordinator.detach(from: nsView)
    }

    /// Plain container so the web view can be swapped without SwiftUI rebuilding the hierarchy.
    final class ContainerView: NSView {
        override var isFlipped: Bool { true }
    }
}

/// Drives one live web canvas: load, look, camera commands, and the load phase its owner routes on.
///
/// An owner that keeps the controller (document window, Quick Look) gets two things: `phase`
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

    @ObservationIgnored private let outlivesMount: Bool
    @ObservationIgnored private var host: WebRendererHost?
    @ObservationIgnored private weak var container: NSView?
    @ObservationIgnored private var loaded: URL?
    @ObservationIgnored private var appliedLook: WebPreviewCanvas.Look?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var placeholderView: NSImageView?
    @ObservationIgnored private var loadingHost: NSHostingView<WebCanvasLoadingChrome>?
    @ObservationIgnored private var didRevealLive = false

    /// A controller the caller holds across mounts.
    public convenience init() {
        self.init(outlivesMount: true)
    }

    init(outlivesMount: Bool) {
        self.outlivesMount = outlivesMount
    }

    // MARK: - Camera commands (the mounted canvas's half of the host's canvas commands)

    /// Frames the model from the page's opening view (front).
    public func fit() async throws {
        let host = try readyHost()
        try await host.send { .fit(id: $0) }
        // `fit` resets the camera transform but not the orbit angles; re-state them so the next
        // drag continues from the front view instead of snapping back.
        try await host.send { .setCamera(id: $0, azimuth: 0, elevation: 0, distance: nil) }
        try await reapplyProjection(on: host)
    }

    /// The opening view. The owner restores Center and the other session values first.
    public func reset() async throws {
        try await fit()
    }

    /// Canned orbit angle, framed from the page's measured scene box.
    public func apply(preset: CameraPreset) async throws {
        let host = try readyHost()
        try await host.send { .fit(id: $0) }
        let angles = preset.webOrbitAngles
        let distance = try? await host.cameraState().distance(framing: preset)
        try await host.send {
            .setCamera(id: $0, azimuth: angles.azimuth, elevation: angles.elevation, distance: distance)
        }
        try await reapplyProjection(on: host)
    }

    /// One frame at the live camera and canvas size. The owner writes the file.
    public func snapshot() async throws -> CGImage {
        try await readyHost().renderStill()
    }

    private func readyHost() throws -> WebRendererHost {
        guard phase == .ready, let host else { throw WebRendererError.notReady }
        return host
    }

    /// The page derives the orthographic size from the camera distance when projection is set,
    /// so a camera move has to restate it.
    private func reapplyProjection(on host: WebRendererHost) async throws {
        guard let projection = appliedLook?.projection, projection == "orthographic" else { return }
        try await host.send { .setProjection(id: $0, name: projection) }
    }

    // MARK: - Mounting

    func attach(
        to container: NSView,
        url: URL,
        look: WebPreviewCanvas.Look,
        placeholder: NSImage?,
        existing: WebRendererHost?
    ) {
        self.container = container
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
            fail(error.localizedDescription, loading: url)
        }
    }

    /// `dismantleNSView`. A controller its owner keeps stays running for the next mount; a
    /// private one tears down with its view.
    func detach(from container: NSView) {
        guard !outlivesMount, self.container === container else { return }
        if let host {
            AppLog.info(
                AppLog.webRenderer,
                "viewport dismantle \(loaded?.lastPathComponent ?? "-") host=\(host.logID) revealed=\(didRevealLive) uptimeMs=\(WebRendererHost.uptimeMs())"
            )
        }
        work?.cancel()
        work = nil
        host = nil
        appliedLook = nil
        placeholderView = nil
        loadingHost?.removeFromSuperview()
        loadingHost = nil
        didRevealLive = false
    }

    /// `updateNSView` runs on every SwiftUI pass, so both the model and the look are
    /// diffed before touching the renderer — re-parsing a 13 MB GLB on each pass, or
    /// re-sampling an IBL on every slider tick, would be ruinous.
    func reload(url: URL, look: WebPreviewCanvas.Look) {
        guard let host else { return }

        let modelChanged = loaded != url
        let previous = appliedLook
        guard modelChanged || previous != look else { return }
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
                    inventory = await peek.value
                    try Task.checkCancellation()
                    if !didRevealLive {
                        showLoading(
                            title: WebRendererLoadCopy.message(for: inventory),
                            detail: WebRendererLoadCopy.detail(for: inventory)
                        )
                    }
                } else {
                    try await host.start()
                }

                // First call only records the stem — HDR is applied after `load` so
                // unhide is not gated on IBL. Later look changes apply immediately.
                if previous?.environment != look.environment {
                    try await host.setEnvironment(named: look.environment)
                }
                if previous?.toneMapping != look.toneMapping {
                    try await host.send { .setToneMapping(id: $0, name: look.toneMapping) }
                }
                if previous?.exposure != look.exposure {
                    try await host.send { .setExposure(id: $0, stops: look.exposure) }
                }
                if previous?.environmentRotation != look.environmentRotation {
                    try await host.send {
                        .setEnvironmentRotation(id: $0, degrees: look.environmentRotation)
                    }
                }
                if previous?.backdrop != look.backdrop {
                    try await host.send { .setBackdrop(id: $0, color: look.backdrop) }
                }
                if previous?.autoRotates != look.autoRotates {
                    try await host.send { .setAutoRotate(id: $0, enabled: look.autoRotates) }
                }
                if previous?.projection != look.projection {
                    try await host.send { .setProjection(id: $0, name: look.projection) }
                }
                if previous?.fieldOfView != look.fieldOfView {
                    try await host.send { .setFieldOfView(id: $0, degrees: look.fieldOfView) }
                }
                if previous?.debugChannel != look.debugChannel {
                    try await host.send { .setDebugChannel(id: $0, name: look.debugChannel) }
                }
                if previous?.fileCameraIndex != look.fileCameraIndex {
                    try await host.send { .setFileCamera(id: $0, index: look.fileCameraIndex) }
                }
                if previous?.materialVariantIndex != look.materialVariantIndex {
                    try await host.send {
                        .setMaterialVariant(id: $0, index: look.materialVariantIndex)
                    }
                }
                if previous?.showsFloor != look.showsFloor {
                    try await host.send { .setFloor(id: $0, enabled: look.showsFloor) }
                }
                if previous?.isCentered != look.isCentered {
                    try await host.send { .setCenter(id: $0, enabled: look.isCentered) }
                }
                if previous?.wireframe != look.wireframe {
                    try await host.send { .setWireframe(id: $0, enabled: look.wireframe) }
                }
                if previous?.selectedNodeIndex != look.selectedNodeIndex {
                    try await host.send { .setSelectedNode(id: $0, index: look.selectedNodeIndex) }
                }

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

                // After the load: `load` resets the scene to the file default, so applying
                // it earlier would be silently undone.
                if modelChanged || previous?.sceneIndex != look.sceneIndex, look.sceneIndex != 0 {
                    try await host.send { .setScene(id: $0, index: look.sceneIndex) }
                }
            } catch is CancellationError {
                // Superseded by a newer look or model; nothing to report.
            } catch {
                // Before the model is on screen every error is a failed load (a page that never
                // started, a file the page rejected, a timeout). After it, a look command that
                // fails leaves the drawn model in place.
                if didRevealLive {
                    AppLog.error(
                        AppLog.webRenderer,
                        "viewport update failed \(url.lastPathComponent): \(error.localizedDescription)"
                    )
                } else {
                    fail(error.localizedDescription, loading: url)
                }
            }
        }
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

    /// Terminal load failure: stop the spinner here too, so an owner that does not route on
    /// `phase` still never shows an endless spinner.
    private func fail(_ message: String, loading url: URL) {
        AppLog.error(AppLog.webRenderer, "viewport failed \(url.lastPathComponent): \(message)")
        phase = .failed(message)
        guard let loadingHost else { return }
        loadingHost.rootView = WebCanvasLoadingChrome(
            title: WebRendererLoadCopy.failed,
            detail: message,
            showsSpinner: false
        )
        loadingHost.isHidden = false
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
