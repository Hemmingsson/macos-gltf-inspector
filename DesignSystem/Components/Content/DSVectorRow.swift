import SwiftUI

/// One row of a transform: a short axis label ("P") and three `DSValueCell`s (x, y, z).
///
/// Stack rows in a `VStack` (or as full-width cells of a `Grid`): the label column has a
/// `DS.Metrics.vectorLabelWidth` minimum that scales with the text size, and the three cells
/// share the rest equally, so the cells of Position / Rotation / Scale line up without a shared
/// measurement.
///
/// The row is **one** accessibility element — label `title`, value "x, y, z" — so VoiceOver reads
/// "Position, 0.00, 0.50, 0.00" instead of four separate stops.
public struct DSVectorRow: View {
    private let title: String
    private let shortTitle: String?
    private let x: String
    private let y: String
    private let z: String

    @ScaledMetric(relativeTo: .callout) private var labelWidth = DS.Metrics.vectorLabelWidth

    /// - Parameters:
    ///   - title: Full name, read by VoiceOver ("Position").
    ///   - shortTitle: Visible label ("P"). `nil` shows `title`.
    ///   - x: Formatted x component.
    ///   - y: Formatted y component.
    ///   - z: Formatted z component.
    public init(_ title: String, shortTitle: String? = nil, x: String, y: String, z: String) {
        self.title = title
        self.shortTitle = shortTitle
        self.x = x
        self.y = y
        self.z = z
    }

    public var body: some View {
        HStack(spacing: DS.Spacing.s) {
            Text(shortTitle ?? title)
                .font(DS.Font.callout)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
                .frame(minWidth: labelWidth, alignment: .leading)

            DSValueCell(x)
            DSValueCell(y)
            DSValueCell(z)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(x), \(y), \(z)")
    }
}

// MARK: - Previews

#Preview("Vector rows") {
    DSContentPreviewStage {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            DSVectorRow("Position", shortTitle: "P", x: "0.00", y: "0.50", z: "0.00")
            DSVectorRow("Rotation", shortTitle: "R", x: "0.00°", y: "90.00°", z: "0.00°")
            DSVectorRow("Scale", shortTitle: "S", x: "1.00", y: "1.00", z: "1.00")
        }
    }
}

#Preview("Vector rows long text, dark") {
    DSContentPreviewStage {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            DSVectorRow("Position", x: "-12345.67", y: "0.50", z: "99999.99")
            DSVectorRow("Scale", shortTitle: "S", x: "", y: "", z: "")
        }
    }
    .preferredColorScheme(.dark)
}
