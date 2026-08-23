import SwiftUI

public enum PreviewFocusRingShape {
    case roundedRect(CGFloat)
    case circle
}

/// Accent focus stroke drawn when the enclosing control is focused.
///
/// Prefers `@Environment(\.isFocused)` (works inside `ButtonStyle` labels). Pass
/// `isFocusedOverride` when the ring sits in an overlay driven by `@FocusState`.
public struct PreviewFocusStroke: View {
    public var shape: PreviewFocusRingShape
    public var isFocusedOverride: Bool? = nil
    @Environment(\.isFocused) private var environmentFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(shape: PreviewFocusRingShape, isFocusedOverride: Bool? = nil) {
        self.shape = shape
        self.isFocusedOverride = isFocusedOverride
    }

    private var isFocused: Bool { isFocusedOverride ?? environmentFocused }

    public var body: some View {
        stroke
            .opacity(isFocused ? 1 : 0)
            .animation(Animation.previewChrome(reduceMotion, duration: 0.12), value: isFocused)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var stroke: some View {
        switch shape {
        case .roundedRect(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 2)
        case .circle:
            Circle()
                .strokeBorder(Theme.accent, lineWidth: 2)
        }
    }
}

// MARK: - Previews

#Preview("rounded") {
    RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(Theme.selection)
        .frame(width: 24, height: 24)
        .overlay {
            PreviewFocusStroke(shape: .roundedRect(4), isFocusedOverride: true)
        }
        .padding(24)
}

#Preview("circle") {
    Circle()
        .fill(Theme.selection)
        .frame(width: 24, height: 24)
        .overlay {
            PreviewFocusStroke(shape: .circle, isFocusedOverride: true)
        }
        .padding(24)
}
