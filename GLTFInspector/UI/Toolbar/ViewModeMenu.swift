import GLTFCore
import SwiftUI

/// The view-mode chip and its menu: Shaded · Wireframe · every debug channel the file *has*
/// (`ViewState.viewModes`, filled from the file). Nothing is shown disabled.
struct ViewModeMenu: View {
    @Bindable var view: ViewState

    var body: some View {
        DSGlassMenuButton(
            "View mode",
            systemImage: view.viewMode.systemImage,
            style: .titled(view.viewMode.title),
            isEngaged: view.viewMode != .shaded
        ) {
            DSInlineMenuPicker("View mode", selection: $view.viewMode) {
                ForEach(view.viewModes, id: \.self) { mode in
                    Text(mode.title)
                        .tag(mode)
                        .keyboardShortcutIfAvailable(DS.Shortcuts.viewMode(mode))
                }
            }
        }
        .contentTransition(.identity)
    }
}
