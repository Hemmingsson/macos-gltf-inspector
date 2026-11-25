import SwiftUI

/// The content column of a control popover (Lighting, Field of View).
///
/// Plain on purpose: **no background**. The system popover already draws its Liquid Glass; a fill
/// here would be glass-on-glass and kill the vibrancy that keeps `.primary` / `.secondary` text
/// crisp. The width is flexible — `DS.Metrics.popoverMinWidth` minimum, asking for
/// `DS.Metrics.popoverIdealWidth` — so a longer localisation or larger text size grows the popover
/// instead of clipping it, and height always fits the content.
struct DSPopoverPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            content
        }
        .padding(DS.Spacing.xl)
        .frame(
            minWidth: DS.Metrics.popoverMinWidth,
            idealWidth: DS.Metrics.popoverIdealWidth,
            alignment: .leading
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}
