import SwiftUI

/// Leading **Stage** cluster: how the scene is dressed. Swatches share one island; the floor is
/// its own circle, so the cluster is never one fused stadium.
struct StageCluster: View {
    @Bindable var view: ViewState

    var body: some View {
        DSGlassCluster {
            DSSwatchPicker("Backdrop", selection: $view.backdrop, swatches: [
                .init(id: .window, title: BackdropStyle.window.title, fill: .checkerboard,
                      accessibilityIdentifier: "backdrop-window"),
                .init(id: .white, title: BackdropStyle.white.title, fill: .color(DS.Color.Backdrop.white),
                      accessibilityIdentifier: "backdrop-white"),
                .init(id: .dark, title: BackdropStyle.dark.title, fill: .color(DS.Color.Backdrop.dark),
                      accessibilityIdentifier: "backdrop-dark"),
            ])
            DSGlassToggleButton("Floor", systemImage: DSGlyphs.floor.symbol,
                                assetImage: DSGlyphs.floor.assetImage, isOn: $view.showsFloor)
        }
    }
}
