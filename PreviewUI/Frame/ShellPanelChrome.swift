import SwiftUI

/// Per-window sidebar open state.
///
/// Owned by the window host (`ShellWindow` / `HostShellRootView`) so the chrome toggle and the
/// View-menu twin share one source of truth. Not an app default — collapse is live chrome, not Settings.
/// Inspector visibility follows selection (open iff something is selected).
@Observable
final class ShellPanelChrome {
    var isSidebarVisible: Bool

    init(isSidebarVisible: Bool = true) {
        self.isSidebarVisible = isSidebarVisible
    }

    func toggleSidebar() { isSidebarVisible.toggle() }
}

extension FocusedValues {
    /// Key-window sidebar visibility (chrome toggle + View-menu twin).
    @Entry var shellPanelChrome: ShellPanelChrome?
}
