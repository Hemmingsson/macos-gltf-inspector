import AppKit
import SwiftUI

/// The document window's model canvas, rendered by the shared web renderer.
///
/// First step of the viewport migration: this replaces `PreviewScene`'s `RealityView` as the
/// thing that draws the model. Sidebar, inspector and overlays still read the RealityKit
/// document — decoupling those is `SceneModel from glTF JSON`, a separate task.
struct WebPreviewCanvas: NSViewRepresentable {
    let url: URL
    /// Applied on load; the page keeps rendering with whatever it last received.
    var environment: String = "neutral"

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = ContainerView()
        context.coordinator.attach(to: container, url: url, environment: environment)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.reload(url: url, environment: environment)
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
        private var work: Task<Void, Never>?

        func attach(to container: NSView, url: URL, environment: String) {
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

                reload(url: url, environment: environment)
            } catch {
                AppLog.error(AppLog.webRenderer, "viewport start failed: \(error.localizedDescription)")
            }
        }

        /// Reloads only when the file actually changed — `updateNSView` runs on every SwiftUI
        /// pass, and re-parsing a 13 MB GLB on each one would be ruinous.
        func reload(url: URL, environment: String) {
            guard let host, loaded != url else { return }
            loaded = url

            work?.cancel()
            work = Task { [host] in
                do {
                    try await host.start()
                    try await host.setEnvironment(named: environment)
                    let info = try await host.load(model: url)
                    AppLog.info(
                        AppLog.webRenderer,
                        "viewport ready \(url.lastPathComponent) tris=\(info.triangles) meshes=\(info.meshes)"
                    )
                } catch {
                    AppLog.error(
                        AppLog.webRenderer,
                        "viewport load failed \(url.lastPathComponent): \(error.localizedDescription)"
                    )
                }
            }
        }

        func cancel() {
            work?.cancel()
            work = nil
            host = nil
        }
    }
}
