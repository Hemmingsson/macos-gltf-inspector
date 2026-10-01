import SwiftUI

/// Preview host for glass components: renders the same content over the three grounds glass must
/// stay legible on — light canvas, dark canvas and the transparent checkerboard.
///
/// Internal: it exists for the `#Preview` blocks in this folder (the DesignCatalog app has its own
/// pages). Each row sets its colour scheme, so glass and hierarchical ink resolve per ground.
struct DSGlassPreviewBackdrops<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            row("Light canvas", scheme: .light) { DS.Color.Canvas.gradient }
            row("Dark canvas", scheme: .dark) { DS.Color.Backdrop.dark }
            row("Checkerboard", scheme: .light) { DSCheckerboard(cell: 8) }
        }
    }

    private func row(
        _ title: String,
        scheme: ColorScheme,
        @ViewBuilder ground: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text(title)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
            content
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { ground() }
        .environment(\.colorScheme, scheme)
    }
}
