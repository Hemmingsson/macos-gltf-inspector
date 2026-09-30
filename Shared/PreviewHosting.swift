import AppKit
import RendererRealityKit
import SwiftUI

/// Forwards trackpad scroll/magnify into `PreviewInteraction` (SwiftUI misses these on macOS).
final class PreviewHostingView: NSHostingView<PreviewView> {
    var interaction: PreviewInteraction?
    private var mouseMonitor: Any?

    required init(rootView: PreviewView) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { PreviewOrbitDragMonitor.remove(&mouseMonitor) }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func scrollWheel(with event: NSEvent) { interaction?.applyScroll(event) }
    override func magnify(with event: NSEvent) { interaction?.applyMagnify(event) }
    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        PreviewOrbitDragMonitor.install(
            on: self,
            interaction: { [weak self] in self?.interaction },
            hitTestBounds: true,
            storage: &mouseMonitor
        )
    }
}

/// Non-hosting root used by Quick Look so scroll events still hit before the hosting view.
/// Orbit/pan monitors stay on the nested `PreviewHostingView` only (one monitor per window).
final class PreviewEventView: NSView {
    var interaction: PreviewInteraction?

    override var isOpaque: Bool { false }
    override func scrollWheel(with event: NSEvent) { interaction?.applyScroll(event) }
    override func magnify(with event: NSEvent) { interaction?.applyMagnify(event) }
    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
}
