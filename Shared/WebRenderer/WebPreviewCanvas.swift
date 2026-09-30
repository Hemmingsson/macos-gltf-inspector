import AppKit
import GLTFCore
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

/// The document window's model canvas, rendered by the shared web renderer.
///
/// First step of the viewport migration: this replaces `PreviewScene`'s `RealityView` as the
/// thing that draws the model. Sidebar, inspector and overlays still read the RealityKit
/// document — decoupling those is `SceneModel from glTF JSON`, a separate task.
struct WebPreviewCanvas: NSViewRepresentable {
    /// Look settings as plain values.
    ///
    /// Deliberately not `LightingSettings`: that type lives in `PreviewUI`, which the Quick Look
    /// and thumbnail extensions do not link. Keeping this primitive is what lets one canvas serve
    /// all three surfaces.
    struct Look: Equatable {
        /// Bundled `.hdr` stem — `neutral`, `field`, `Colorful_Studio`.
        var environment: String = AppGroupSettings.defaultEnvironment
        /// Khronos `GltfState.ToneMaps` value.
        var toneMapping: String = AppGroupSettings.defaultToneMapping
        /// Exposure compensation in stops.
        var exposure: Double = 0
        /// Environment yaw in degrees.
        var environmentRotation: Double = 0
        /// Backdrop as `[r, g, b, a]` in 0-1. Alpha 0 shows the host window through.
        var backdrop: [Double] = [0, 0, 0, 0]
        var autoRotates = false
        /// `perspective` or `orthographic`.
        var projection = "perspective"
        /// Vertical field of view in degrees.
        var fieldOfView: Double = 45
        /// Khronos `GltfState.DebugOutput` value; `None` for normal shading.
        var debugChannel = "None"
        /// Camera authored in the file, or nil for the user camera.
        var fileCameraIndex: Int?
        /// `KHR_materials_variants` index, or nil for the file default.
        var materialVariantIndex: Int?
        /// Scene index.
        var sceneIndex: Int = 0
        var showsFloor = true
        /// False shows the authored-origin gizmo and frames so the origin is visible.
        var isCentered = true
        var wireframe = false
        /// glTF node index highlighted on the canvas.
        var selectedNodeIndex: Int?
    }

    let url: URL
    var look = Look()
    /// Icon Services thumbnail already on disk. Nil on the host window and on a cache miss.
    var placeholderImage: NSImage? = nil
    /// Live host already constructed (Quick Look `loadView` prestart). Nil in the document window.
    var host: WebRendererHost? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = ContainerView()
        context.coordinator.attach(
            to: container, url: url, look: look, placeholder: placeholderImage, existing: host
        )
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.setPlaceholder(placeholderImage, in: nsView)
        context.coordinator.reload(url: url, look: look)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    /// Plain container so the web view can be swapped without SwiftUI rebuilding the hierarchy.
    final class ContainerView: NSView {
        override var isFlipped: Bool { true }
    }

    @MainActor
    final class Coordinator {
        private var host: WebRendererHost?
        private var loaded: URL?
        private var appliedLook: Look?
        private var work: Task<Void, Never>?
        private var placeholderView: NSImageView?
        private var loadingHost: NSHostingView<WebCanvasLoadingChrome>?
        private var didRevealLive = false

        func attach(
            to container: NSView,
            url: URL,
            look: Look,
            placeholder: NSImage?,
            existing: WebRendererHost?
        ) {
            if let placeholder {
                installPlaceholder(placeholder, in: container, below: nil)
            }
            installLoadingChrome(in: container)

            do {
                let host = try existing ?? WebRendererHost(mode: .live)
                self.host = host

                let view = host.view
                view.removeFromSuperview()
                view.translatesAutoresizingMaskIntoConstraints = false
                // Visible under the loading chrome so the canvas gets a real size.
                // Alpha 0 made the first `renderFrame` 1×1; revealing then resized
                // (cleared) and the GPU frame ran on an empty screen.
                view.alphaValue = 1
                container.addSubview(view)
                NSLayoutConstraint.activate([
                    view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    view.topAnchor.constraint(equalTo: container.topAnchor),
                    view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])
                if let loadingHost {
                    container.addSubview(loadingHost, positioned: .above, relativeTo: view)
                }

                reload(url: url, look: look)
            } catch {
                AppLog.error(AppLog.webRenderer, "viewport start failed: \(error.localizedDescription)")
            }
        }

        /// `updateNSView` runs on every SwiftUI pass, so both the model and the look are
        /// diffed before touching the renderer — re-parsing a 13 MB GLB on each pass, or
        /// re-sampling an IBL on every slider tick, would be ruinous.
        func reload(url: URL, look: Look) {
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
                                guard !self.didRevealLive else { return }
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
                            "viewport ready \(url.lastPathComponent) tris=\(info.triangles) canvas=\(info.width)x\(info.height) firstFrameMs=\(info.firstFrameMs)"
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
                    AppLog.error(
                        AppLog.webRenderer,
                        "viewport update failed \(url.lastPathComponent): \(error.localizedDescription)"
                    )
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

        func cancel() {
            work?.cancel()
            work = nil
            host = nil
            appliedLook = nil
            placeholderView = nil
            loadingHost?.removeFromSuperview()
            loadingHost = nil
            didRevealLive = false
        }

        private func revealLive(host: WebRendererHost) {
            didRevealLive = true
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
            host.translatesAutoresizingMaskIntoConstraints = false
            host.wantsLayer = true
            host.layer?.isOpaque = false
            host.layer?.backgroundColor = NSColor.clear.cgColor
            container.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                host.topAnchor.constraint(equalTo: container.topAnchor),
                host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            loadingHost = host
        }

        private func installPlaceholder(_ image: NSImage, in container: NSView, below sibling: NSView?) {
            let view = NSImageView()
            view.image = image
            view.imageScaling = .scaleProportionallyUpOrDown
            view.imageAlignment = .alignCenter
            view.wantsLayer = true
            view.layer?.isOpaque = false
            view.translatesAutoresizingMaskIntoConstraints = false
            if let sibling {
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
            placeholderView = view
        }
    }
}
