import SwiftUI

/// Per-window sidebar / inspector open state.
///
/// Owned by the window host (`ShellWindow` today) so the chrome toggles and the View-menu twins
/// share one source of truth. Not an app default — collapse is live chrome, not Settings.
@Observable
final class ShellPanelChrome {
    var isSidebarVisible: Bool
    var isInspectorVisible: Bool

    init(isSidebarVisible: Bool = true, isInspectorVisible: Bool = true) {
        self.isSidebarVisible = isSidebarVisible
        self.isInspectorVisible = isInspectorVisible
    }

    func toggleSidebar() { isSidebarVisible.toggle() }
    func toggleInspector() { isInspectorVisible.toggle() }
}
