import DesignSystem
import SwiftUI

/// `DSSectionHeader` with the inspector's section rhythm: `l` sides, `xs` below, `xl` above
/// (`m` for the sidebar-footer sections). Section bodies keep their own padding.
struct InspectorSectionHeader: View {
    var title: String
    var top: CGFloat = DS.Spacing.xl

    init(_ title: String, top: CGFloat = DS.Spacing.xl) {
        self.title = title
        self.top = top
    }

    var body: some View {
        DSSectionHeader(title)
            .padding(.top, top)
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.xs)
    }
}
