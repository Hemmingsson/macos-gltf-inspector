import AppKit
import SwiftUI

/// Sketch-style traffic-light indent for `.hiddenTitleBar` / full-size content windows.
///
/// System lights default to ~y=8 from the top. Sketch pushes them down and in so the chrome
/// band has breathing room; we match that and keep `Theme.trafficLightCenterY` in sync so
/// sidebar / pill controls share the same optical centerline.
struct WindowChromeIndent: NSViewRepresentable {
    var topInset: CGFloat = Theme.trafficLightTopInset
    var leadingInset: CGFloat = Theme.trafficLightLeadingInset

    func makeCoordinator() -> Coordinator {
        Coordinator(topInset: topInset, leadingInset: leadingInset)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.topInset = topInset
        context.coordinator.leadingInset = leadingInset
        context.coordinator.apply()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var topInset: CGFloat
        var leadingInset: CGFloat
        private weak var view: NSView?
        private var resizeObserver: NSObjectProtocol?
        private var moveObserver: NSObjectProtocol?

        init(topInset: CGFloat, leadingInset: CGFloat) {
            self.topInset = topInset
            self.leadingInset = leadingInset
        }

        func attach(to view: NSView) {
            self.view = view
            let center = NotificationCenter.default
            resizeObserver = center.addObserver(
                forName: NSWindow.didResizeNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self, let window = note.object as? NSWindow, window === self.view?.window else { return }
                self.apply(to: window)
            }
            moveObserver = center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let self, let window = note.object as? NSWindow, window === self.view?.window else { return }
                self.apply(to: window)
            }
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func detach() {
            let center = NotificationCenter.default
            if let resizeObserver { center.removeObserver(resizeObserver) }
            if let moveObserver { center.removeObserver(moveObserver) }
            resizeObserver = nil
            moveObserver = nil
            view = nil
        }

        func apply() {
            apply(to: view?.window)
        }

        func apply(to window: NSWindow?) {
            guard let window,
                  let close = window.standardWindowButton(.closeButton),
                  let container = close.superview
            else { return }

            let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            let buttonHeight = close.frame.height
            let y = container.bounds.height - topInset - buttonHeight
            var x = leadingInset
            let gap: CGFloat = 6

            for type in types {
                guard let button = window.standardWindowButton(type) else { continue }
                button.setFrameOrigin(NSPoint(x: x, y: max(0, y)))
                x += button.frame.width + gap
            }
        }
    }
}
