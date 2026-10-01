import SwiftUI

/// Untitled slider for a glass HUD capsule. Title row lives beside the control, not above it —
/// `DSSlider` is the wrong shape for playback.
public struct DSHUDSlider<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    @Binding private var value: Value
    private let range: ClosedRange<Value>
    private let accessibilityLabel: String
    private let onEditingChanged: (Bool) -> Void

    public init(
        value: Binding<Value>,
        in range: ClosedRange<Value>,
        accessibilityLabel: String,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.range = range
        self.accessibilityLabel = accessibilityLabel
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        Slider(value: $value, in: range, onEditingChanged: onEditingChanged)
            .accessibilityLabel(accessibilityLabel)
    }
}

#Preview("HUD slider") {
    @Previewable @State var time = 0.35
    DSHUDSlider(
        value: $time,
        in: 0...1,
        accessibilityLabel: "Animation time"
    )
    .controlSize(.small)
    .frame(width: 250)
    .padding(DS.Spacing.xxl)
}
