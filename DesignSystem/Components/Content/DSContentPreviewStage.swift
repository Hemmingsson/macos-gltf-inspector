import SwiftUI

/// Preview-only ground for the content and control components: the window background, a
/// section's worth of padding and an inspector-wide column, so `#Preview`s read like the pane they
/// will live in. Internal; not part of the design system's API.
struct DSContentPreviewStage<Content: View>: View {
    var width: CGFloat = DS.Metrics.inspectorWidth
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l, content: content)
            .padding(DS.Spacing.xl)
            .frame(width: width, alignment: .leading)
            .background(DS.Color.windowBackground)
    }
}
