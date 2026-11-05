import SwiftUI

/// Trailing **Camera** cluster: where you stand and how you move. Each control draws its own
/// glass; nothing is nested glass-on-glass.
struct CameraCluster: View {
    @Bindable var view: ViewState

    var body: some View {
        DSGlassCluster {
            DSGlassToggleButton(
                view.isOrthographic ? "Orthographic" : "Perspective",
                assetImage: view.isOrthographic ? SplineIcons.cameraOrthographic : SplineIcons.cameraPerspective,
                isOn: $view.isOrthographic,
                shortcut: Shortcuts.action(.orthographic)
            )
            FieldOfViewPopover(view: view)
            ViewMenu(view: view)
        }
    }
}
