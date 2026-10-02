import DesignSystem
import SwiftUI

/// Centre cluster — **Look**: how the surface is shaded and lit.
///
/// View mode + lighting stay one island: both answer “what light does to the material”.
struct LookCluster<Capabilities: Availability, Viewport: ViewportController>: View {
    /// Read-only capability snapshot: the view-mode menu offers only channels the file has.
    var availability: Capabilities
    var viewport: Viewport

    var body: some View {
        DSGlassCluster {
            DSGlassIsland {
                ViewModeMenu(availability: availability, viewport: viewport)
                DSGlassIslandDivider()
                LightingPopover(availability: availability, viewport: viewport)
            }
        }
    }
}

// MARK: - Previews

private struct LookClusterPreviewHost: View {
    var availability: MockAvailability
    @State private var viewport: MockViewportController

    init(availability: MockAvailability = MockAvailability(), viewport: MockViewportController) {
        self.availability = availability
        _viewport = State(initialValue: viewport)
    }

    var body: some View {
        PreviewCanvas(width: 260, height: 64, background: .canvas) {
            LookCluster(availability: availability, viewport: viewport)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

#Preview("shaded", traits: .fixedLayout(width: 260, height: 64)) {
    LookClusterPreviewHost(viewport: MockViewportController())
}

#Preview("wireframe", traits: .fixedLayout(width: 260, height: 64)) {
    LookClusterPreviewHost(viewport: MockViewportController(viewMode: .wireframe))
}

#Preview("normals channel", traits: .fixedLayout(width: 260, height: 64)) {
    LookClusterPreviewHost(viewport: MockViewportController(viewMode: .channel(.normals)))
}
