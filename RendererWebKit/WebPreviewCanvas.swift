import AppKit
import GLTFCore
import SwiftUI

/// The model canvas of a WebKit document window and Quick Look preview: the shared web page,
/// mounted through an owner-held `WebCanvasController`.
public struct WebPreviewCanvas: NSViewRepresentable {
    let url: URL
    var look = Look()
    /// Cached Finder poster. Nil when none is stored — the loading pill is the stand-in.
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

extension WebPreviewCanvas {
    /// What the page can do today (`Look` fields and page commands). No clip playback, morph
    /// weights, hide/solo, skeleton overlay, double-sided override or file-light toggle: the
    /// page renders the file as authored. Host availability hides the matching chrome.
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
