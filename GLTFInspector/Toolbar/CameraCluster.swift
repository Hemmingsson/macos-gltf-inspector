import SwiftUI

/// Trailing **Camera** cluster: where you stand and how you move. Each control draws its own
/// glass; nothing is nested glass-on-glass.
struct CameraCluster: View {
    @Bindable var view: ViewState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DSGlassCluster {
            DSGlassToggleButton(
                "Auto-rotate",
                systemImage: "arrow.trianglehead.counterclockwise.rotate.90",
                isOn: autoRotate
            )
            .disabled(reduceMotion)
            DSGlassToggleButton("Center Model", systemImage: "dot.scope", isOn: $view.isCentered)
            DSGlassToggleButton("Orthographic", systemImage: "perspective", isOn: $view.isOrthographic)
            FieldOfViewPopover(view: view)
            ViewMenu(view: view)
        }
    }

    /// Reduce Motion parks the toggle off even if the window's flag is still set.
    private var autoRotate: Binding<Bool> {
        Binding(
            get: { view.autoRotates && !reduceMotion },
            set: { if !reduceMotion { view.autoRotates = $0 } }
        )
    }
}
