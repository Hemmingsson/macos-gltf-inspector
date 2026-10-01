import DesignSystem
import SwiftUI

/// Compact chip for geometry facts and present material maps. Wraps `DSChip`
/// (`.quinary` / card fill, secondary text).
public struct InspectorChip: View {
    public var title: String

    public var body: some View {
        DSChip(title)
    }
}

// MARK: - Previews

#Preview("default") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        InspectorChip(title: "12 tris")
            .padding(DS.Spacing.l)
    }
}
