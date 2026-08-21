import SwiftUI

extension FocusedValues {
    /// Key-window `MockScene` for the shell-only Debug menu.
    ///
    /// Same `@Entry` pattern as `GLBPreviewApp`'s `previewCommands`. Bound via
    /// `.focusedSceneValue(\.mockScene, …)` on `ShellWindow` so each window keeps its own
    /// fixture — never `@State` on `App`.
    @Entry var mockScene: MockScene?

    /// Key-window `MockViewport` for the View menu (keyboard twin of the canvas pills).
    @Entry var mockViewport: MockViewport?

    /// Key-window sidebar / inspector visibility (chrome toggles + View-menu twins).
    @Entry var shellPanelChrome: ShellPanelChrome?
}
