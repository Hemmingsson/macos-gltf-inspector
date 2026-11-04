import SwiftUI

/// Leading **Stage** cluster: how the scene is dressed. Swatches share one island; the floor is
/// its own circle, so the cluster is never one fused stadium.
struct StageCluster: View {
    @Bindable var view: ViewState

    var body: some View {
        DSGlassCluster {
            DSSwatchPicker("Backdrop", selection: $view.backdrop, swatches: [
                .init(id: .window, title: BackdropStyle.window.title, fill: .checkerboard),
                .init(id: .white, title: BackdropStyle.white.title, fill: .color(DS.Color.Backdrop.white)),
                .init(id: .dark, title: BackdropStyle.dark.title, fill: .color(DS.Color.Backdrop.dark)),
            ])
            DSGlassToggleButton("Floor", systemImage: "circle.grid.cross", isOn: $view.showsFloor)
        }
    }
}
