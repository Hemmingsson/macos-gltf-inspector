import SwiftUI

/// A read-only bounded scalar as a filled bar — Metallic 0.000, Roughness 0.650 — in the manner of
/// Blender's factor fields.
///
/// Label leading in `.secondary` callout; the bar takes the trailing half of the row so stacked
/// rows line up whatever their label length. The bar is a `DSValueCell`-style box (opaque
/// `DS.Color.controlBackground`, `DS.Color.separator` hairline, `DS.Radius.small`) filled from the
/// leading edge by `Color.accentColor.opacity(0.45)` in proportion to `value` within `range`, with the reading
/// centred in monospaced digits. It is not a control: this is a viewer. VoiceOver reads it as one
/// element ("Roughness, 0.650").
struct DSFactorRow: View {
    private let label: String
    private let value: Double
    private let range: ClosedRange<Double>
    private let reading: String

    /// - Parameters:
    ///   - label: Leading label and accessibility label.
    ///   - value: The scalar; values outside `range` pin the fill to empty or full.
    ///   - range: The span the bar represents. Defaults to the unit factor range.
    ///   - reading: Text shown in the bar. Defaults to three decimals.
    init(
        _ label: String,
        value: Double,
        in range: ClosedRange<Double> = 0...1,
        reading: String? = nil
    ) {
        self.label = label
        self.value = value
        self.range = range
        self.reading = reading ?? value.formatted(.number.precision(.fractionLength(3)))
    }

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            DSFactorBar(fraction: fraction, reading: reading)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(reading)
    }

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0, value.isFinite else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }
}

/// The bar of a `DSFactorRow`.
struct DSFactorBar: View {
    var fraction: Double
    var reading: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)

        Text(reading)
            .font(.callout.monospacedDigit())
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.Spacing.m)
            .padding(.vertical, DS.Spacing.xs)
            .background {
                ZStack(alignment: .leading) {
                    DS.Color.controlBackground
                    GeometryReader { proxy in
                        Color.accentColor.opacity(0.45)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .clipShape(shape)
            }
            // `strokeBorder`, not `stroke`: a stroke straddles the edge and spills outside it.
            .overlay(shape.strokeBorder(DS.Color.separator, lineWidth: DS.Metrics.hairline))
    }
}
