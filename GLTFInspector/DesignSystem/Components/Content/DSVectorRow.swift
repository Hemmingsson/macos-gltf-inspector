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
struct DSVectorRow: View {
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
    init(_ title: String, shortTitle: String? = nil, x: String, y: String, z: String) {
        self.title = title
        self.shortTitle = shortTitle
        self.x = x
        self.y = y
        self.z = z
    }

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            Text(shortTitle ?? title)
                .font(.callout)
                .foregroundStyle(.secondary)
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
