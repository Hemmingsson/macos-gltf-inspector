import AppKit
import RealityKit
import SwiftUI

/// Host-only overlay applied during RealityView updates. Quick Look and thumbnails pass `nil`.
@MainActor
protocol PreviewOverlay: AnyObject {
    var overlayRevision: Int { get }
    var selectedCameraIndex: Int? { get }
    var document: GLTFSessionDocument { get }
    func applyIfNeeded(to root: Entity)
}

@Observable
final class PreviewInteraction {
    var zoom: Float = 1

    func applyScroll(_ event: NSEvent) {
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
        guard dy != 0 else { return }
        setZoom(zoom * exp(Float(-dy) * 0.004))
    }

    func applyMagnify(_ event: NSEvent) {
        guard event.magnification != 0 else { return }
        setZoom(zoom * Float(1 + event.magnification))
    }

    private func setZoom(_ value: Float) {
        let clamped = min(max(value, 0.12), 8)
        guard abs(clamped - zoom) > 0.0001 else { return }
        zoom = clamped
    }
}

/// AppKit views that forward trackpad zoom into `PreviewInteraction`.
private protocol PreviewZoomForwarding: AnyObject {
    var interaction: PreviewInteraction? { get }
}

extension PreviewZoomForwarding where Self: NSView {
    func forwardScrollWheel(_ event: NSEvent) { interaction?.applyScroll(event) }
    func forwardMagnify(_ event: NSEvent) { interaction?.applyMagnify(event) }
}

/// Forwards trackpad scroll/magnify into `PreviewInteraction` (SwiftUI misses these on macOS).
final class PreviewHostingView: NSHostingView<PreviewView>, PreviewZoomForwarding {
    var interaction: PreviewInteraction?

    required override init(rootView: PreviewView) {
        super.init(rootView: rootView)
        // Size from the AppKit frame so loading/failed content fills the window
        // instead of hugging the ProgressView and landing at the origin.
        sizingOptions = []
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func scrollWheel(with event: NSEvent) { forwardScrollWheel(event) }
    override func magnify(with event: NSEvent) { forwardMagnify(event) }
    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

/// Non-hosting root used by Quick Look so scroll events still hit before the hosting view.
final class PreviewEventView: NSView, PreviewZoomForwarding {
    var interaction: PreviewInteraction?

    override var isOpaque: Bool { false }
    override func scrollWheel(with event: NSEvent) { forwardScrollWheel(event) }
    override func magnify(with event: NSEvent) { forwardMagnify(event) }
    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
}
