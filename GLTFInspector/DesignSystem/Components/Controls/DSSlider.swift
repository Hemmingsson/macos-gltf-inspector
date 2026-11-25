import SwiftUI

/// A titled continuous value: a label row (title in `.primary`, the current reading in
/// `.secondary` monospaced digits) above a system `Slider`.
///
/// Wraps the continuous `Slider(value:in:neutralValue:)` (macOS 26) and snaps to `step` in the
/// binding instead of handing `step` to the slider: a stepped system slider draws a tick-mark
/// ruler under the track, which is noise on a reading that is already spelled out above it. Pass
/// `neutralValue` when the range has a meaningful rest point (exposure 0 EV) so the fill grows from
/// it rather than from the minimum.
///
/// No tint and no control size are fixed here: the slider follows the user's accent and the
/// surrounding `controlSize(_:)`. VoiceOver reads the title as the label and the reading as the
/// value ("Exposure, +0.5 EV").
struct DSSlider<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
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
    ///   - step: Snap increment, applied in the binding.
    ///   - neutralValue: Optional rest point the track fill grows from.
    ///   - reading: Formats the current value for the trailing reading and accessibility value.
    ///   - accessibilityLabel: VoiceOver name when it must differ from the visible title.
    init(
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
    init(
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

    var body: some View {
        let currentReading = reading(value)

        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: DS.Spacing.m)
                Text(currentReading)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.body)
            .lineLimit(1)
            // The slider below carries both strings for VoiceOver.
            .accessibilityHidden(true)

            Slider(value: snapped, in: range, neutralValue: neutralValue) {
                Text(accessibilityLabelText)
            }
            .labelsHidden()
            .accessibilityValue(currentReading)
            // A notch every detent across the track, plus one on arriving at an end or the rest
            // point. The detent grid is sized to the range, so a 360-step slider has the same
            // feel under the finger as a 60-step one instead of buzzing the whole way.
            .onChange(of: value) { was, now in
                let crossedDetent = Self.detentIndex(now, in: range, step: step)
                    != Self.detentIndex(was, in: range, step: step)
                let arrived = Self.isLandmark(now, in: range, neutralValue: neutralValue)
                    && !Self.isLandmark(was, in: range, neutralValue: neutralValue)
                if crossedDetent || arrived { DSHaptics.detent() }
            }
        }
    }

    /// The bound value, rounded to `step` on the way in. Keeps the slider continuous — and so
    /// free of tick marks — while the value still lands on whole increments.
    private var snapped: Binding<Value> {
        Binding(
            get: { value },
            set: { value = Self.snap($0, in: range, step: step) }
        )
    }

    /// Roughly how many notches a full drag of any slider should give.
    private static var detentsPerTrack: Double { 40 }

    /// Which detent `value` falls in. Detents sit on whole multiples of `step`, spaced so the
    /// track holds about `detentsPerTrack` of them however long the range is.
    static func detentIndex(_ value: Value, in range: ClosedRange<Value>, step: Value.Stride) -> Int {
        let span = Double(range.upperBound - range.lowerBound)
        let increment = Double(step)
        guard span > 0, increment > 0 else { return 0 }
        let stepsPerDetent = max(1, (span / detentsPerTrack / increment).rounded(.up))
        return Int((Double(value - range.lowerBound) / (increment * stepsPerDetent)).rounded())
    }

    /// The points on the track worth feeling on the way past: either end of the range and the
    /// rest point, when there is one.
    static func isLandmark(_ value: Value, in range: ClosedRange<Value>, neutralValue: Value?) -> Bool {
        value <= range.lowerBound || value >= range.upperBound || value == neutralValue
    }

    /// `incoming` rounded to the nearest `step` above `range.lowerBound`, clamped to `range`.
    /// A step of zero or less leaves the value alone.
    static func snap(_ incoming: Value, in range: ClosedRange<Value>, step: Value.Stride) -> Value {
        let increment = Value(step)
        guard increment > 0 else { return min(max(incoming, range.lowerBound), range.upperBound) }
        let steps = ((incoming - range.lowerBound) / increment).rounded()
        return min(max(range.lowerBound + steps * increment, range.lowerBound), range.upperBound)
    }
}
