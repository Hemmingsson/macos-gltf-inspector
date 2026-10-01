import SwiftUI

/// A boxed, read-only numeric value — one component of a transform (`0.00`, `90.00°`).
///
/// Looks like a field so columns of numbers scan as a table, but it is not editable: this is a
/// viewer. Opaque `DS.Color.controlBackground` ground with a `DS.Color.separator` hairline at
/// `DS.Radius.small`, monospaced digits so columns do not jitter, and selectable text so a value
/// can be copied. Fills the width it is offered; long values shrink slightly before truncating.
public struct DSValueCell: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)

        Text(text)
            .font(DS.Font.value)
            .foregroundStyle(DS.Color.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Color.controlBackground, in: shape)
            // `strokeBorder`, not `stroke`: a stroke straddles the edge and spills outside it.
            .overlay(shape.strokeBorder(DS.Color.separator, lineWidth: DS.Metrics.cellStrokeWidth))
    }
}

// MARK: - Previews

#Preview("Value cell") {
    DSContentPreviewStage {
        HStack(spacing: DS.Spacing.s) {
            DSValueCell("0.00")
            DSValueCell("0.50")
            DSValueCell("0.00")
        }
        DSValueCell("-12345.678°")
            .frame(width: 60)
        DSValueCell("")
    }
}

#Preview("Value cell, dark") {
    DSContentPreviewStage {
        HStack(spacing: DS.Spacing.s) {
            DSValueCell("90.00°")
            DSValueCell("-0.00°")
            DSValueCell("180.00°")
        }
    }
    .preferredColorScheme(.dark)
}
