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
        lockToolbarNowAndNextTurn(window)
    }

    /// Document windows: Finder-like full-height sidebar under traffic lights,
    /// unified blur title area (no solid marked toolbar strip).
    static func applySplitChrome(to window: NSWindow) {
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = true
        window.isMovableByWindowBackground = false
        window.toolbarStyle = .unified
        configureSplitItems(in: window)
        lockToolbarNowAndNextTurn(window) {
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            configureSplitItems(in: window)
        }
    }

    static func lockToolbarIconOnly(_ window: NSWindow) {
        guard let toolbar = window.toolbar else { return }
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
    }

    /// Toolbar may attach one run-loop turn after first layout.
    private static func lockToolbarNowAndNextTurn(_ window: NSWindow, extraAsync: (() -> Void)? = nil) {
        lockToolbarIconOnly(window)
        DispatchQueue.main.async {
            extraAsync?()
            lockToolbarIconOnly(window)
        }
    }

    private static func configureSplitItems(in window: NSWindow) {
        for split in findSplitViewControllers(in: window) {
            for item in split.splitViewItems {
                if item.behavior == .sidebar {
                    item.allowsFullHeightLayout = true
                    item.titlebarSeparatorStyle = .none
                    if item.responds(to: NSSelectorFromString("setWantsFloatingAppearance:")) {
                        item.setValue(false, forKey: "wantsFloatingAppearance")
                    }
                } else if #available(macOS 26, *) {
                    item.automaticallyAdjustsSafeAreaInsets = false
                }
            }
        }
    }

    private static func findSplitViewControllers(in window: NSWindow) -> [NSSplitViewController] {
        var found: [NSSplitViewController] = []
        var seen = Set<ObjectIdentifier>()

        func append(_ split: NSSplitViewController) {
            let id = ObjectIdentifier(split)
            guard !seen.contains(id) else { return }
            seen.insert(id)
            found.append(split)
        }

        func walkController(_ root: NSViewController?) {
            guard let root else { return }
            if let split = root as? NSSplitViewController {
                append(split)
            }
            for child in root.children {
                walkController(child)
            }
        }

        func walkView(_ view: NSView?) {
            guard let view else { return }
            var responder: NSResponder? = view
            while let current = responder {
                if let split = current as? NSSplitViewController {
                    append(split)
                }
                responder = current.nextResponder
            }
            for sub in view.subviews {
                walkView(sub)
            }
        }

        walkController(window.contentViewController)
        walkView(window.contentView)
        return found
    }
}
