import SwiftUI

/// Per-window sidebar open state.
///
/// Owned by the window host (`ShellWindow` / `DocumentShell`) so the system sidebar toggle,
/// `SidebarCommands()`, and `NavigationSplitView` share one source of truth. Not an app default —
/// collapse is live chrome, not Settings. Inspector visibility follows selection (open iff
/// something is selected).
@Observable
public final class ShellPanelChrome {
    /// Drives `NavigationSplitView(columnVisibility:)`.
    public var columnVisibility: NavigationSplitViewVisibility

    /// Menu-friendly wrapper over `columnVisibility`.
    public var isSidebarVisible: Bool {
        get { columnVisibility != .detailOnly }
        set { columnVisibility = newValue ? .all : .detailOnly }
    }

    public init(isSidebarVisible: Bool = true) {
        columnVisibility = isSidebarVisible ? .all : .detailOnly
    }

    public func toggleSidebar() { isSidebarVisible.toggle() }
}

public extension FocusedValues {
    /// Key-window sidebar visibility (chrome toggle + View-menu twin).
    @Entry var shellPanelChrome: ShellPanelChrome?
}
