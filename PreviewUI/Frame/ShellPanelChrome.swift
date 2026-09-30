import SwiftUI

/// Per-window sidebar open state.
///
/// Owned by the window host (`ShellWindow` / `DocumentShell`) so the chrome toggle and the
/// View-menu twin share one source of truth. Not an app default — collapse is live chrome, not Settings.
/// Inspector visibility follows selection (open iff something is selected).
@Observable
public final class ShellPanelChrome {
    public var isSidebarVisible: Bool

    public init(isSidebarVisible: Bool = true) {
        self.isSidebarVisible = isSidebarVisible
    }

    public func toggleSidebar() { isSidebarVisible.toggle() }
}

public extension FocusedValues {
    /// Key-window sidebar visibility (chrome toggle + View-menu twin).
    @Entry var shellPanelChrome: ShellPanelChrome?
}
