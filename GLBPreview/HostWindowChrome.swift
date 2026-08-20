import AppKit

enum HostWindowChrome {
    /// Welcome / non-split windows: transparent titlebar + full-size content.
    static func apply(to window: NSWindow) {
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        lockToolbarIconOnly(window)
        DispatchQueue.main.async {
            lockToolbarIconOnly(window)
        }
    }

    /// Document windows using NavigationSplitView: keep system sidebar/titlebar chrome.
    static func applySplitChrome(to window: NSWindow) {
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isOpaque = true
        window.isMovableByWindowBackground = false
        window.toolbarStyle = .unifiedCompact
        lockToolbarIconOnly(window)
        DispatchQueue.main.async {
            window.toolbarStyle = .unifiedCompact
            lockToolbarIconOnly(window)
        }
    }

    static func lockToolbarIconOnly(_ window: NSWindow) {
        guard let toolbar = window.toolbar else { return }
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
    }
}
