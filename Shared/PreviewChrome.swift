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

    var orbitResetNonce = 0

    func resetFit() {
        zoom = 1
        orbitResetNonce += 1
    }

    private func setZoom(_ value: Float) {
        let clamped = min(max(value, 0.12), 8)
        guard abs(clamped - zoom) > 0.0001 else { return }
        zoom = clamped
    }
}

/// Forwards trackpad scroll/magnify into `PreviewInteraction` (SwiftUI misses these on macOS).
final class PreviewHostingView: NSHostingView<PreviewView> {
    var interaction: PreviewInteraction?

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
    }
}

/// Non-hosting root used by Quick Look so scroll events still hit before the hosting view.
final class PreviewEventView: NSView {
    var interaction: PreviewInteraction?

    override var isOpaque: Bool { false }
    override func scrollWheel(with event: NSEvent) { interaction?.applyScroll(event) }
    override func magnify(with event: NSEvent) { interaction?.applyMagnify(event) }
    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
}
