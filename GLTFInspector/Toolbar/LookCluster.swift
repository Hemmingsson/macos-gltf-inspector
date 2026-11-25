import SwiftUI

/// Centre **Look** cluster: how the surface is shaded and lit. View mode and lighting share one
/// island; both answer "what light does to the material".
struct LookCluster: View {
    var view: ViewState

    var body: some View {
        DSGlassCluster {
            DSGlassIsland {
                ViewModeMenu(view: view)
                DSGlassIslandDivider()
                LightingPopover(view: view)
            }
        }
    }
}
