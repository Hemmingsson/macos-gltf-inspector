import AppKit
import SwiftUI

/// Right-click menu on the model canvas. Built at click time so Paste reflects the clipboard.
@MainActor
enum CanvasContextMenu {
    static func menu(view: ViewState, chromeHidden: Binding<Bool>) -> NSMenu {
        let menu = CanvasMenu()
        func item(_ title: String, enabled: Bool = true, action: @escaping @MainActor () -> Void) {
            let box = MenuBox(action)
            menu.boxes.append(box)
            let row = NSMenuItem(title: title, action: #selector(MenuBox.fire), keyEquivalent: "")
            row.target = box
            row.isEnabled = enabled
            menu.addItem(row)
        }
        item("Reset Camera", enabled: view.canvas.phase == .ready) { view.resetCamera() }
        item(chromeHidden.wrappedValue ? "Show UI" : "Toggle UI") { chromeHidden.wrappedValue.toggle() }
        item("Select All", enabled: !view.document.nodes.isEmpty) { view.selectAll() }
        item("Paste", enabled: DocumentOpening.pastedGLTFURL() != nil) { DocumentOpening.pasteGLTF() }
        return menu
    }
}

/// Owns the item targets. `NSMenuItem.target` is weak, so the menu has to keep them.
private final class CanvasMenu: NSMenu {
    var boxes: [MenuBox] = []
}

private final class MenuBox: NSObject {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    @objc func fire() { MainActor.assumeIsolated { action() } }
}
