import AppKit
import PreviewUI
import SwiftUI

/// SF Symbols for the menu bar. Names live here so the SwiftUI items and the AppKit pass agree.
enum MenuSymbol {
    static let newWindow = "macwindow.badge.plus"
    static let close = "xmark"
    static let rename = "pencil"
    static let moveTo = "folder"
    static let share = "square.and.arrow.up"
    static let exportPNG = "camera"
    static let viewMode = "cube"
    static let backdrop = "swatchpalette"
    static let floor = "circle.grid.cross"
    static let autoRotate = "arrow.trianglehead.counterclockwise.rotate.90"
    static let center = "dot.scope"
    static let orthographic = "perspective"
    static let zoomIn = "plus.magnifyingglass"
    static let zoomOut = "minus.magnifyingglass"
    static let fit = "viewfinder"
    static let reset = "arrow.counterclockwise"
    static let checkForUpdates = "arrow.triangle.2.circlepath"

    /// System items SwiftUI does not build. Titles are AppKit's English menu strings.
    static let systemByTitle: [String: String] = [
        "Open…": "folder",
        "Open Recent": "clock",
        "Close All": "xmark.rectangle",
        "Page Setup…": "doc",
        "Print…": "printer",
        "Show Sidebar": "sidebar.left",
        "Hide Sidebar": "sidebar.left",
        "Show Tab Bar": "rectangle.topthird.inset.filled",
        "Hide Tab Bar": "rectangle.topthird.inset.filled",
        "Show All Tabs": "square.stack",
        "Show Toolbar": "menubar.rectangle",
        "Hide Toolbar": "menubar.rectangle",
        "Customize Toolbar…": "slider.horizontal.3",
        "Enter Full Screen": "arrow.up.left.and.arrow.down.right",
        "Exit Full Screen": "arrow.down.right.and.arrow.up.left",
        "Settings…": "gearshape",
        "Check for Updates…": checkForUpdates,
    ]
}

extension View {
    /// macOS 27 hides a menu symbol unless the label style asks for the title and the icon.
    func menuBarIcons() -> some View {
        labelStyle(.titleAndIcon)
    }
}

/// Puts symbols on the system File, View, and app-menu items SwiftUI does not construct.
///
/// SwiftUI rebuilds the main menu when focus changes and drops images it does not own, so this
/// restamps whenever AppKit adds or retitles an item.
@MainActor
final class MainMenuSymbols: NSObject {
    static let shared = MainMenuSymbols()

    func install() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(menuChanged(_:)),
            name: NSMenu.didAddItemNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(menuChanged(_:)),
            name: NSMenu.didChangeItemNotification,
            object: nil
        )
        decorateMainMenu()
    }

    @objc private func menuChanged(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        guard let index = notification.userInfo?["NSMenuItemIndex"] as? Int,
              menu.items.indices.contains(index) else { return }
        decorate(menu.items[index], in: menu)
    }

    private func decorateMainMenu() {
        guard let main = NSApp.mainMenu else { return }
        for item in main.items {
            decorate(item, in: main)
        }
    }

    private func decorate(_ item: NSMenuItem, in menu: NSMenu) {
        // macOS 27 hides menu images unless the item asks for them. SwiftUI's
        // `.titleAndIcon` does this for commands we build; system items need it here.
        if menuWantsSymbols(menu), let name = symbolName(for: item) {
            if item.image == nil {
                item.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            }
            if #available(macOS 27, *), item.image != nil, item.preferredImageVisibility != .visible {
                item.preferredImageVisibility = .visible
            }
        }
        if let submenu = item.submenu {
            for child in submenu.items {
                decorate(child, in: submenu)
            }
        }
    }

    private func menuWantsSymbols(_ menu: NSMenu) -> Bool {
        if menu == NSApp.mainMenu?.item(at: 0)?.submenu { return true }
        var current: NSMenu? = menu
        while let candidate = current {
            if candidate.title == "File" || candidate.title == "View" { return true }
            current = candidate.supermenu
        }
        return false
    }

    private func symbolName(for item: NSMenuItem) -> String? {
        if item.title.hasPrefix("About ") { return "info.circle" }
        if let symbol = MenuSymbol.systemByTitle[item.title] { return symbol }
        if let mode = ViewMode.base.first(where: { $0.title == item.title }) { return mode.systemImage }
        if let style = BackdropStyle.allCases.first(where: { $0.title == item.title }) {
            return style.systemImage
        }
        if let preset = CameraPreset.allCases.first(where: { $0.title == item.title }) {
            return preset.systemImage
        }
        return switch item.title {
        case "New Window": MenuSymbol.newWindow
        case "Close": MenuSymbol.close
        case "Rename…": MenuSymbol.rename
        case "Move To…": MenuSymbol.moveTo
        case "Share": MenuSymbol.share
        case "Export PNG…": MenuSymbol.exportPNG
        case "View Mode": MenuSymbol.viewMode
        case "Backdrop": MenuSymbol.backdrop
        case "Show Floor": MenuSymbol.floor
        case "Auto-Rotate": MenuSymbol.autoRotate
        case "Center Model": MenuSymbol.center
        case "Orthographic": MenuSymbol.orthographic
        case "Zoom In": MenuSymbol.zoomIn
        case "Zoom Out": MenuSymbol.zoomOut
        case "Fit": MenuSymbol.fit
        case "Reset View": MenuSymbol.reset
        default: nil
        }
    }
}
