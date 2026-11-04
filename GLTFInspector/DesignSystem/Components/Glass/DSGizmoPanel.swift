import SwiftUI

/// Rounded-square glass host for the canvas navigation gizmo.
struct DSGizmoPanel<Content: View>: View {
    private let size: CGFloat
    private let content: Content

    init(size: CGFloat = DS.Metrics.navigationGizmoSize, @ViewBuilder content: () -> Content) {
        self.size = size
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .glassEffect(DS.Glass.hud, in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
    }
}
