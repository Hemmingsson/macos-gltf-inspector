import SwiftUI

/// Shell stand-in for the renderer: wireframe wash + centred cube.
/// At cutover, `GLBPreview` injects a `RealityView` here instead — PreviewUI stays unchanged.
struct CanvasPlaceholder: View {
    var body: some View {
        ZStack {
            Theme.canvasGradient

            Image(systemName: "cube")
                .font(.system(size: 96, weight: .ultraLight))
                .foregroundStyle(Theme.text3)
                .accessibilityHidden(true)
        }
    }
}
