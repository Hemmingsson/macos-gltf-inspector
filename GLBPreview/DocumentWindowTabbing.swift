import AppKit
import SwiftUI

/// Prefers tabs for document windows and merges late-created windows into the front tab group.
struct DocumentWindowTabbing: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TabbingHookView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class TabbingHookView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            HostWindowChrome.applySplitChrome(to: window)
            // DocumentGroup often orders a new window before preferred tabbing applies;
            // split controller may also attach a turn later.
            DispatchQueue.main.async {
                HostWindowChrome.applySplitChrome(to: window)
                Self.mergeIntoPreferredTabGroupIfNeeded(window)
            }
        }

        static func mergeIntoPreferredTabGroupIfNeeded(_ window: NSWindow) {
            window.tabbingIdentifier = Self.tabbingIdentifier
            window.tabbingMode = .preferred

            if let tabs = window.tabbedWindows, tabs.count > 1 {
                return
            }

            let candidates = NSApp.windows.filter { other in
                other !== window
                    && other.isVisible
                    && other.tabbingIdentifier == tabbingIdentifier
                    && !(other.tabbedWindows?.contains(window) ?? false)
            }
            guard let host = candidates.first(where: { ($0.tabbedWindows?.count ?? 1) > 1 })
                ?? candidates.first
            else {
                return
            }

            host.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        static let tabbingIdentifier = "com.laurie.GLBPreview.document"
    }
}
