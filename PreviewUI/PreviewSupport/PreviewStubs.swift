import DesignSystem
import SwiftUI

/// "Open in" menu items for previews and the catalog (the host injects the real menu).
public struct PreviewOpenInItems: View {
    public init() {}

    public var body: some View {
        Button("Finder") {}
        Button("Blender") {}
    }
}

/// Stand-in for the host-injected renderer canvas — flat gray viewport only.
struct PreviewCanvasPlaceholder: View {
    var body: some View {
        DS.Color.Canvas.gradient
    }
}
