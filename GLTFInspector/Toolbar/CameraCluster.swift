import SwiftUI

/// Trailing **Camera** cluster: where you stand and how you move. Each control draws its own
/// glass; nothing is nested glass-on-glass.
struct CameraCluster: View {
    @Bindable var view: ViewState

    var body: some View {
        DSGlassCluster {
            DSGlassToggleButton(
                "Projection",
                systemImage: (view.isOrthographic ? DSGlyphs.orthographic : DSGlyphs.perspective).symbol,
                assetImage: (view.isOrthographic ? DSGlyphs.orthographic : DSGlyphs.perspective).assetImage,
                isOn: $view.isOrthographic,
                shortcut: Shortcuts.action(.orthographic)
            )
            .accessibilityValue(view.isOrthographic ? "Orthographic" : "Perspective")
            FieldOfViewPopover(view: view)
            ViewMenu(view: view)
        }
    }
}
