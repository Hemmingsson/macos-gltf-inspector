import SwiftUI

public extension View {
    @ViewBuilder
    func keyboardShortcutIfAvailable(_ shortcut: KeyboardShortcut?) -> some View {
        if let shortcut {
            self.keyboardShortcut(shortcut)
        } else {
            self
        }
    }
}
