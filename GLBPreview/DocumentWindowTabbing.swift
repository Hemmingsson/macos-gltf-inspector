import AppKit
import SwiftUI

/// Configures document windows to prefer tabs and merges late-created windows into the front tab group.
struct DocumentWindowTabbing: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TabbingHookView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class TabbingHookView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.tabbingIdentifier = GLBDocumentOpening.documentTabbingIdentifier
            window.tabbingMode = .preferred
            HostWindowChrome.lockToolbarIconOnly(window)
            // SwiftUI DocumentGroup often orders a new window before tabbingMode applies; merge if needed.
            DispatchQueue.main.async {
                HostWindowChrome.lockToolbarIconOnly(window)
                GLBDocumentOpening.mergeIntoPreferredTabGroupIfNeeded(window)
            }
        }
    }
}

extension GLBDocumentOpening {
    static let documentTabbingIdentifier = "com.laurie.GLBPreview.document"

    static func mergeIntoPreferredTabGroupIfNeeded(_ window: NSWindow) {
        window.tabbingIdentifier = documentTabbingIdentifier
        window.tabbingMode = .preferred

        if let tabs = window.tabbedWindows, tabs.count > 1 {
            return
        }

        let candidates = NSApp.windows.filter { other in
            other !== window
                && other.isVisible
                && other.tabbingIdentifier == documentTabbingIdentifier
                && !(other.tabbedWindows?.contains(window) ?? false)
        }
        guard let host = candidates.first(where: { ($0.tabbedWindows?.count ?? 1) > 1 })
            ?? candidates.first
        else {
            AppLog.info(AppLog.host, "tabbing solo title=\(window.title) id=\(window.tabbingIdentifier) mode=\(window.tabbingMode.rawValue)")
            return
        }

        AppLog.info(
            AppLog.host,
            "tabbing merge title=\(window.title) into=\(host.title) hostTabs=\(host.tabbedWindows?.count ?? -1)"
        )
        host.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
