import SwiftUI

/// A titled continuous value: a label row (title in `.primary`, the current reading in
/// `.secondary` monospaced digits) above a system `Slider`.
///
/// Wraps `Slider(value:in:step:neutralValue:)` (macOS 26). `step` is **required**: that
/// initialiser defaults it to `1`, which silently snaps an exposure slider to whole stops. Pass
/// `neutralValue` when the range has a meaningful rest point (exposure 0 EV) so the fill grows from
/// it rather than from the minimum.
///
/// No tint and no control size are fixed here: the slider follows the user's accent and the
/// surrounding `controlSize(_:)`. VoiceOver reads the title as the label and the reading as the
/// value ("Exposure, +0.5 EV").
public struct DSSlider<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    private let title: String
    @Binding private var value: Value
    private let range: ClosedRange<Value>
    private let step: Value.Stride
    private let neutralValue: Value?
    private let reading: (Value) -> String
    private let accessibilityLabelText: String

    /// - Parameters:
    ///   - title: Shown leading in the label row and used as the accessibility label.
    ///   - value: The bound value.
    ///   - range: Allowed values.
    ///   - step: Snap increment. Required — the system default is `1`.
    ///   - neutralValue: Optional rest point the track fill grows from.
    ///   - reading: Formats the current value for the trailing reading and accessibility value.
    ///   - accessibilityLabel: VoiceOver name when it must differ from the visible title.
    public init(
        _ title: String,
        value: Binding<Value>,
        in range: ClosedRange<Value>,
        step: Value.Stride,
        neutralValue: Value? = nil,
        accessibilityLabel: String? = nil,
        reading: @escaping (Value) -> String
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.neutralValue = neutralValue
        self.reading = reading
        self.accessibilityLabelText = accessibilityLabel ?? title
    }

    /// Same as the closure form, with a reading the caller has already formatted.
    public init(
        _ title: String,
        value: Binding<Value>,
        in range: ClosedRange<Value>,
        step: Value.Stride,
        neutralValue: Value? = nil,
        accessibilityLabel: String? = nil,
        reading: String
    ) {
        self.init(
            title,
            value: value,
            in: range,
            step: step,
            neutralValue: neutralValue,
            accessibilityLabel: accessibilityLabel,
            reading: { _ in reading }
        )
    }

    public var body: some View {
        let currentReading = reading(value)

        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
                Text(title)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer(minLength: DS.Spacing.m)
                Text(currentReading)
                    .monospacedDigit()
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .font(DS.Font.body)
            .lineLimit(1)
            // The slider below carries both strings for VoiceOver.
            .accessibilityHidden(true)

            Slider(value: $value, in: range, step: step, neutralValue: neutralValue) {
                Text(accessibilityLabelText)
            }
            .labelsHidden()
            .accessibilityValue(currentReading)
        }
    }
}

// MARK: - Previews

#Preview("Slider") {
    @Previewable @State var exposure = 0.5
    @Previewable @State var rotation = 120.0
    DSContentPreviewStage {
        DSSlider("Exposure", value: $exposure, in: -3...3, step: 0.1, neutralValue: 0) {
            $0.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + " EV"
        }
        DSSlider("Environment", value: $rotation, in: 0...360, step: 1) {
            $0.formatted(.number.precision(.fractionLength(0))) + "°"
        }
    }
}

#Preview("Slider long title, dark") {
    @Previewable @State var fov = 35.0
    DSContentPreviewStage {
        DSSlider(
            "Vertical field of view for the perspective camera",
            value: $fov,
            in: 15...90,
            step: 1
        ) { $0.formatted(.number.precision(.fractionLength(0))) + "°" }
        DSSlider("Field of View", value: $fov, in: 15...90, step: 1, reading: "35°")
            .controlSize(.small)
    }
    .preferredColorScheme(.dark)
}
