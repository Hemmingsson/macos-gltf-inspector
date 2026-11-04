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
            assetImage: SplineIcons.viewMode(view.viewMode),
            style: .titled(view.viewMode.title),
            isEngaged: view.viewMode != .shaded
        ) {
            Picker("View mode", selection: $view.viewMode) {
                ForEach(view.viewModes, id: \.self) { mode in
                    Label {
                        Text(mode.title)
                    } icon: {
                        viewModeGlyph(mode)
                    }
                    .tag(mode)
                    .keyboardShortcutIfAvailable(Shortcuts.viewMode(mode))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .contentTransition(.identity)
    }

    @ViewBuilder
    private func viewModeGlyph(_ mode: RenderViewMode) -> some View {
        if let asset = SplineIcons.viewMode(mode) {
            Image(asset)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: mode.systemImage)
        }
    }
}
