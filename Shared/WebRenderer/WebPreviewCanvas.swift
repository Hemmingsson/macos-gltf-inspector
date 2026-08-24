import AppKit
import SwiftUI

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
        var environment: String = "neutral"
        /// Khronos `GltfState.ToneMaps` value.
        var toneMapping: String = "Khronos PBR Neutral"
        /// Exposure compensation in stops.
        var exposure: Double = 0
        /// Environment yaw in degrees.
        var environmentRotation: Double = 0
    }

    let url: URL
    var look = Look()

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = ContainerView()
        context.coordinator.attach(to: container, url: url, look: look)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
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

        func attach(to container: NSView, url: URL, look: Look) {
            do {
                let host = try WebRendererHost(mode: .live)
                self.host = host

                let view = host.view
                view.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(view)
                NSLayoutConstraint.activate([
                    view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    view.topAnchor.constraint(equalTo: container.topAnchor),
                    view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])

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
                    try await host.start()

                    // Re-sampling the environment probe is the expensive one; only on change.
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

                    if modelChanged {
                        let info = try await host.load(model: url)
                        AppLog.info(
                            AppLog.webRenderer,
                            "viewport ready \(url.lastPathComponent) tris=\(info.triangles) meshes=\(info.meshes)"
                        )
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

        func cancel() {
            work?.cancel()
            work = nil
            host = nil
            appliedLook = nil
        }
    }
}
