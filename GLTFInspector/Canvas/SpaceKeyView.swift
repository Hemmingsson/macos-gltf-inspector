import AppKit
import SwiftUI

/// Invisible first-responder target so Space toggles playback through AppKit in tests and SwiftUI hosts.
struct SpaceKeyView: NSViewRepresentable {
    var onSpace: () -> Void

    func makeNSView(context: Context) -> SpaceKeyNSView {
        let view = SpaceKeyNSView()
        view.onSpace = onSpace
        return view
    }

    func updateNSView(_ view: SpaceKeyNSView, context: Context) {
        view.onSpace = onSpace
    }
}

final class SpaceKeyNSView: NSView {
    var onSpace: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            onSpace?()
            return
        }
        super.keyDown(with: event)
    }
}
