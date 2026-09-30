import SwiftUI

/// A radio group of circular colour swatches in one glass island (the backdrop picker).
///
/// Each swatch is a `DS.Metrics.swatch` disc — a colour or the `DSCheckerboard` — with a hairline
/// `DS.Color.separator` edge so white still reads on white. The selected swatch takes a
/// `DS.Metrics.swatchRingWidth` accent ring outside a clear `DS.Metrics.swatchRingGap`, so the
/// island's glass shows between disc and ring.
///
/// Accessibility: the island is one container labelled with `title` ("Backdrop"); each swatch is
/// a button labelled with its name and marked `.isSelected` when current. Hit targets span the full
/// island height; the system focus ring follows the disc.
public struct DSSwatchPicker<ID: Hashable>: View {
    /// What a swatch paints.
    public enum Fill {
        /// A solid colour.
        case color(SwiftUI.Color)
        /// The "no backdrop" checkerboard.
        case checkerboard
    }

    /// One choice.
    public struct Swatch: Identifiable {
        public let id: ID
        /// Name for the tooltip and VoiceOver ("White").
        public let title: String
        public let fill: Fill

        public init(id: ID, title: String, fill: Fill) {
            self.id = id
            self.title = title
            self.fill = fill
        }
    }

    private let title: String
    @Binding private var selection: ID
    private let swatches: [Swatch]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - title: Group name for accessibility ("Backdrop").
    ///   - selection: The selected swatch's `id`.
    ///   - swatches: The choices, leading to trailing.
    public init(_ title: String, selection: Binding<ID>, swatches: [Swatch]) {
        self.title = title
        self._selection = selection
        self.swatches = swatches
    }

    public var body: some View {
        DSGlassIsland(spacing: DS.Spacing.s) {
            ForEach(swatches) { swatch in
                swatchButton(swatch)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .animation(DS.Motion.chrome(reduceMotion: reduceMotion), value: selection)
    }

    private func swatchButton(_ swatch: Swatch) -> some View {
        let isSelected = swatch.id == selection
        return Button {
            selection = swatch.id
        } label: {
            disc(swatch.fill)
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(DS.Color.accent, lineWidth: DS.Metrics.swatchRingWidth)
                            .frame(width: Self.ringDiameter, height: Self.ringDiameter)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: DS.Metrics.glassControl)
                .contentShape(.interaction, .rect)
                .contentShape(.focusEffect, .circle)
        }
        .buttonStyle(.plain)
        .help(swatch.title)
        .accessibilityLabel(swatch.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func disc(_ fill: Fill) -> some View {
        Group {
            switch fill {
            case .color(let color): color
            case .checkerboard: DSCheckerboard()
            }
        }
        .frame(width: DS.Metrics.swatch, height: DS.Metrics.swatch)
        .clipShape(.circle)
        .overlay {
            Circle().strokeBorder(DS.Color.separator, lineWidth: DS.Metrics.hairline / 2)
        }
    }

    private static var ringDiameter: CGFloat {
        DS.Metrics.swatch + 2 * (DS.Metrics.swatchRingGap + DS.Metrics.swatchRingWidth)
    }
}

// MARK: - Previews

private enum PreviewBackdrop: Hashable {
    case none, white, dark
}

private struct DSSwatchPickerPreview: View {
    @State private var first = PreviewBackdrop.none
    @State private var second = PreviewBackdrop.white
    @State private var third = PreviewBackdrop.dark

    private let swatches: [DSSwatchPicker<PreviewBackdrop>.Swatch] = [
        .init(id: .none, title: "Checkerboard", fill: .checkerboard),
        .init(id: .white, title: "White", fill: .color(DS.Color.Backdrop.white)),
        .init(id: .dark, title: "Dark", fill: .color(DS.Color.Backdrop.dark))
    ]

    var body: some View {
        HStack(spacing: DS.Metrics.clusterSpacing) {
            DSSwatchPicker("Backdrop", selection: $first, swatches: swatches)
            DSSwatchPicker("Backdrop", selection: $second, swatches: swatches)
            DSSwatchPicker("Backdrop", selection: $third, swatches: swatches)
        }
    }
}

#Preview("swatch picker states", traits: .sizeThatFitsLayout) {
    DSGlassPreviewBackdrops {
        DSSwatchPickerPreview()
    }
    .frame(width: 400)
}
