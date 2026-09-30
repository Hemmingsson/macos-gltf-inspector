import AppKit
import SwiftUI

/// Forwards trackpad scroll/magnify into `PreviewInteraction` (SwiftUI misses these on macOS).
///
/// Generic over the root view so the host router and the Quick Look router share it.
public final class PreviewHostingView<Content: View>: NSHostingView<Content> {
    public var interaction: PreviewInteraction?
    private var mouseMonitor: Any?

    public required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @MainActor public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { PreviewOrbitDragMonitor.remove(&mouseMonitor) }

    public override var isOpaque: Bool { false }
    public override var mouseDownCanMoveWindow: Bool { false }
    public override func scrollWheel(with event: NSEvent) { interaction?.applyScroll(event) }
    public override func magnify(with event: NSEvent) { interaction?.applyMagnify(event) }
    public override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool { true }
    public override var acceptsFirstResponder: Bool { true }

    public override func viewDidMoveToWindow() {
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
public final class PreviewEventView: NSView {
    public var interaction: PreviewInteraction?

    public override var isOpaque: Bool { false }
    public override func scrollWheel(with event: NSEvent) { interaction?.applyScroll(event) }
    public override func magnify(with event: NSEvent) { interaction?.applyMagnify(event) }
    public override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool { true }
    public override var acceptsFirstResponder: Bool { true }
}
