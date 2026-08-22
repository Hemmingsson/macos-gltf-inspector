import SwiftUI
import AppKit

/// Drops the three system window buttons (traffic lights) so their vertical center lands on
/// `centerY` points from the window top, instead of sitting flush to the window edge.
///
/// A `.hiddenTitleBar` window pins the lights near the very top; the canvas pills and chrome
/// toggles align to `Theme.trafficLightCenterY`, so moving that line down needs the lights to move
/// with it — otherwise the two drift apart. AppKit re-lays the buttons on resize / full-screen, so
/// we reapply, and we set an **absolute** target (never a compounding offset) so repeated calls are
/// idempotent. Zero-size: it exists only to reach the host `NSWindow`.
struct TrafficLightConfigurator: NSViewRepresentable {
    var centerY: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = PositioningView()
        view.centerY = centerY
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? PositioningView else { return }
        view.centerY = centerY
        view.reposition()
    }

    final class PositioningView: NSView {
        var centerY: CGFloat = 16
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            guard let window else { return }
            let names: [NSNotification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
            ]
            for name in names {
                observers.append(
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        self?.reposition()
                    }
                )
            }
            // AppKit finishes its own button layout after this pass; reapply on the next tick.
            DispatchQueue.main.async { [weak self] in self?.reposition() }
        }

        func reposition() {
            guard let window else { return }
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
                .compactMap { window.standardWindowButton($0) }
            let windowHeight = window.frame.height
            for button in buttons {
                guard let container = button.superview else { continue }
                // Window base coords are y-up: window top = windowHeight. Put the button's top
                // `centerY - height/2` below the top, then convert into the button's superview.
                let baseOriginY = windowHeight - centerY - button.frame.height / 2
                let originY = container.convert(NSPoint(x: 0, y: baseOriginY), from: nil).y
                button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: originY))
            }
        }

        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }
}
